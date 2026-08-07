import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCashDashboardPage extends StatefulWidget {
  final String username;

  const AdminCashDashboardPage({super.key, required this.username});

  @override
  State<AdminCashDashboardPage> createState() => _AdminCashDashboardPageState();
}

class _AdminCashDashboardPageState extends State<AdminCashDashboardPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  DateTime _selectedDate = DateTime.now();

  List<String> _branches = [];
  String _selectedBranch = 'ALL';

  List<Map<String, dynamic>> _branchSummary = [];
  Map<String, dynamic> _detail = {};

  bool get _isAdmin {
    final u = widget.username.trim().toLowerCase();
    return u == 'admin' || u == 'kamlesh' || u == 'ks.29bishnoi@gmail.com';
  }

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmt(dynamic v) => _toDouble(v).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() => _selectedDate = d);
      await _loadDashboard();
    }
  }

  Future<void> _loadDashboard() async {
    setState(() => _loading = true);
    try {
      await _loadBranches();
      await _loadBranchSummary();

      if (_selectedBranch != 'ALL') {
        await _loadBranchDetail(_selectedBranch);
      } else {
        _detail = {};
      }
    } catch (e) {
      _msg('Dashboard load error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadBranches() async {
    final data = await supabase
        .from('tickets')
        .select('branch_code')
        .order('branch_code');

    final set = <String>{};
    for (final row in data) {
      final b = (row['branch_code'] ?? '').toString().trim();
      if (b.isNotEmpty) set.add(b);
    }

    _branches = set.toList()..sort();
  }

  Future<void> _loadBranchSummary() async {
    final date = _dateOnly(_selectedDate);
    final summary = <Map<String, dynamic>>[];

    for (final branch in _branches) {
      final tickets = await supabase
          .from('tickets')
          .select('final_amount,payment_method')
          .eq('branch_code', branch)
          .gte('ticket_date', '${date} 00:00:00')
          .lte('ticket_date', '${date} 23:59:59');

      double totalSale = 0;
      double cashSale = 0;
      double upiSale = 0;
      double cardSale = 0;

      for (final row in tickets) {
        final amt = _toDouble(row['final_amount']);
        final pm = (row['payment_method'] ?? '').toString().toUpperCase();

        totalSale += amt;
        if (pm == 'CASH') cashSale += amt;
        if (pm == 'UPI') upiSale += amt;
        if (pm == 'CARD') cardSale += amt;
      }

      final txns = await supabase
          .from('transactions')
          .select('flow_type,category,amount')
          .eq('branch_code', branch)
          .gte('tx_date', '${date} 00:00:00')
          .lte('tx_date', '${date} 23:59:59');

      double otherCashIn = 0;
      double totalCashOut = 0;
      double commissionPaid = 0;
      double expense = 0;

      for (final row in txns) {
        final amt = _toDouble(row['amount']);
        final flow = (row['flow_type'] ?? '').toString().toUpperCase();
        final cat = (row['category'] ?? '').toString();

        if (flow == 'IN') {
          otherCashIn += amt;
        } else if (flow == 'OUT') {
          totalCashOut += amt;
          if (cat == 'Commission Paid') commissionPaid += amt;
          if (cat == 'Expense' || cat == 'Other Cash Out') expense += amt;
        }
      }

      double openingBalance = 0;
      try {
        final prev = _selectedDate.subtract(const Duration(days: 1));
        final closing = await supabase
            .from('cash_day_closing')
            .select('actual_closing_balance')
            .eq('branch_code', branch)
            .eq('closing_date', _dateOnly(prev))
            .limit(1);

        if (closing.isNotEmpty) {
          openingBalance = _toDouble(closing.first['actual_closing_balance']);
        }
      } catch (_) {}

      final cashInHand = openingBalance + cashSale + otherCashIn - totalCashOut;

      summary.add({
        'branch_code': branch,
        'opening_balance': openingBalance,
        'total_sale': totalSale,
        'cash_sale': cashSale,
        'upi_sale': upiSale,
        'card_sale': cardSale,
        'other_cash_in': otherCashIn,
        'expense': expense,
        'commission_paid': commissionPaid,
        'cash_out': totalCashOut,
        'cash_in_hand': cashInHand,
      });
    }

    _branchSummary = summary;
  }

  Future<void> _loadBranchDetail(String branch) async {
    final item = _branchSummary.firstWhere(
      (e) => e['branch_code'] == branch,
      orElse: () => <String, dynamic>{},
    );
    _detail = item;
  }

  double get _allTotalSale =>
      _branchSummary.fold(0.0, (s, e) => s + _toDouble(e['total_sale']));
  double get _allCashSale =>
      _branchSummary.fold(0.0, (s, e) => s + _toDouble(e['cash_sale']));
  double get _allUpiSale =>
      _branchSummary.fold(0.0, (s, e) => s + _toDouble(e['upi_sale']));
  double get _allCardSale =>
      _branchSummary.fold(0.0, (s, e) => s + _toDouble(e['card_sale']));
  double get _allExpense =>
      _branchSummary.fold(0.0, (s, e) => s + _toDouble(e['expense']));
  double get _allCommission =>
      _branchSummary.fold(0.0, (s, e) => s + _toDouble(e['commission_paid']));
  double get _allCashInHand =>
      _branchSummary.fold(0.0, (s, e) => s + _toDouble(e['cash_in_hand']));

  Widget _topBox(String title, String value, {Color? color}) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _branchCard(Map<String, dynamic> e) {
    final branch = e['branch_code'].toString();
    final selected = _selectedBranch == branch;

    return InkWell(
      onTap: () async {
        setState(() => _selectedBranch = branch);
        await _loadBranchDetail(branch);
        setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                branch,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(child: Text('Sale: ₹${_fmt(e['total_sale'])}')),
            Expanded(child: Text('Cash: ₹${_fmt(e['cash_sale'])}')),
            Expanded(child: Text('UPI: ₹${_fmt(e['upi_sale'])}')),
            Expanded(child: Text('Card: ₹${_fmt(e['card_sale'])}')),
            Expanded(child: Text('Exp: ₹${_fmt(e['expense'])}')),
            Expanded(child: Text('Comm: ₹${_fmt(e['commission_paid'])}')),
            Expanded(
              child: Text(
                'Cash In Hand: ₹${_fmt(e['cash_in_hand'])}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection() {
    if (_selectedBranch == 'ALL' || _detail.isEmpty) {
      return const SizedBox();
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _topBox('Branch', _selectedBranch),
            _topBox('Opening', '₹${_fmt(_detail['opening_balance'])}'),
            _topBox('Total Sale', '₹${_fmt(_detail['total_sale'])}'),
            _topBox('Cash Sale', '₹${_fmt(_detail['cash_sale'])}'),
            _topBox('UPI Sale', '₹${_fmt(_detail['upi_sale'])}'),
            _topBox('Card Sale', '₹${_fmt(_detail['card_sale'])}'),
            _topBox('Other Cash In', '₹${_fmt(_detail['other_cash_in'])}'),
            _topBox('Expense', '₹${_fmt(_detail['expense'])}'),
            _topBox('Commission', '₹${_fmt(_detail['commission_paid'])}'),
            _topBox(
              'Cash In Hand',
              '₹${_fmt(_detail['cash_in_hand'])}',
              color: Colors.green.shade50,
            ),
          ],
        ),
      ),
    );
  }

  void _msg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Cash Dashboard')),
        body: const Center(child: Text('Access denied')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Cash Dashboard • ${_dateOnly(_selectedDate)}'),
        actions: [
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
          ),
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _topBox('All Sale', '₹${_fmt(_allTotalSale)}'),
                      _topBox('All Cash', '₹${_fmt(_allCashSale)}'),
                      _topBox('All UPI', '₹${_fmt(_allUpiSale)}'),
                      _topBox('All Card', '₹${_fmt(_allCardSale)}'),
                      _topBox('All Expense', '₹${_fmt(_allExpense)}'),
                      _topBox('All Comm.', '₹${_fmt(_allCommission)}'),
                      _topBox(
                        'All Cash In Hand',
                        '₹${_fmt(_allCashInHand)}',
                        color: Colors.green.shade50,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _detailSection(),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _branchSummary.length,
                      itemBuilder: (context, index) {
                        return _branchCard(_branchSummary[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
