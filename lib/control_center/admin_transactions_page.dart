import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminTransactionsPage extends StatefulWidget {
  final String username;

  const AdminTransactionsPage({
    super.key,
    required this.username,
  });

  @override
  State<AdminTransactionsPage> createState() => _AdminTransactionsPageState();
}

class _AdminTransactionsPageState extends State<AdminTransactionsPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  String _branchFilter = 'ALL';
  String _flowFilter = 'ALL';
  String _categoryFilter = 'ALL';
  String _paymentFilter = 'ALL';
  String _searchText = '';

  List<String> _branches = [];
  List<String> _categories = [];
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _branchSummary = [];

  double _totalIn = 0;
  double _totalOut = 0;
  double _totalExpense = 0;
  double _totalCommission = 0;
  double _totalSalaryAdvance = 0;

  double _todaySale = 0;
  double _cashSale = 0;
  double _upiSale = 0;
  double _cardSale = 0;

  bool get _isAdmin {
    final u = widget.username.trim().toLowerCase();
    return u == 'admin' ||
        u == 'kamlesh' ||
        u == 'ks.29bishnoi@gmail.com';
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmt(dynamic v) => _toDouble(v).toStringAsFixed(2);

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;
  DateTime _onlyDate(DateTime d) {
  return DateTime(d.year, d.month, d.day);
}

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await _loadBranches();
      await _loadCategories();
      await _applyFilters();
    } catch (e) {
      _msg('Load error: $e');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadBranches() async {
    try {
      final data = await supabase
          .from('transactions')
          .select('branch_code')
          .order('branch_code');

      final set = <String>{};
      for (final row in data) {
        final b = (row['branch_code'] ?? '').toString().trim();
        if (b.isNotEmpty) set.add(b);
      }

      _branches = ['ALL', ...set.toList()..sort()];
    } catch (_) {
      _branches = ['ALL'];
    }
  }

  Future<void> _loadCategories() async {
    try {
      final data = await supabase
          .from('transactions')
          .select('category')
          .order('category');

      final set = <String>{};
      for (final row in data) {
        final c = (row['category'] ?? '').toString().trim();
        if (c.isNotEmpty) set.add(c);
      }

      _categories = ['ALL', ...set.toList()..sort()];
    } catch (_) {
      _categories = ['ALL'];
    }
  }

  Future<void> _applyFilters() async {
    await _loadSalesSummary();
    await _loadTransactions();
    if (mounted) setState(() {});
  }

  Future<void> _loadSalesSummary() async {
    dynamic ticketQuery = supabase
        .from('tickets')
        .select('final_amount,payment_method,branch_code')
        .gte('ticket_date', '${_dateOnly(_fromDate)}T00:00:00')
        .lte('ticket_date', '${_dateOnly(_toDate)}T23:59:59');

    if (_branchFilter != 'ALL') {
      ticketQuery = ticketQuery.eq('branch_code', _branchFilter);
    }

    final data = await ticketQuery;

    _todaySale = 0;
    _cashSale = 0;
    _upiSale = 0;
    _cardSale = 0;

    for (final row in data) {
      final amt = _toDouble(row['final_amount']);
      final pm = (row['payment_method'] ?? '').toString().toUpperCase();

      _todaySale += amt;
      if (pm == 'CASH') _cashSale += amt;
      if (pm == 'UPI') _upiSale += amt;
      if (pm == 'CARD') _cardSale += amt;
    }
  }

  void _buildBranchSummary() {
    final Map<String, Map<String, double>> map = {};

    for (final row in _rows) {
      final branch = (row['branch_code'] ?? '').toString();
      final flow = (row['flow_type'] ?? '').toString().toUpperCase();
      final cat = (row['category'] ?? '').toString();
      final amt = _toDouble(row['amount']);

      map.putIfAbsent(branch, () => {
            'cash_in': 0,
            'cash_out': 0,
            'expense': 0,
            'salary_advance': 0,
          });

      if (flow == 'IN') {
        map[branch]!['cash_in'] = map[branch]!['cash_in']! + amt;
      } else {
        map[branch]!['cash_out'] = map[branch]!['cash_out']! + amt;
      }

      if (cat == 'Expense' ||
          cat == 'Other Cash Out' ||
          cat == 'Vendor Payment' ||
          cat == 'Refund') {
        map[branch]!['expense'] = map[branch]!['expense']! + amt;
      }

      if (cat == 'Salary Advance') {
        map[branch]!['salary_advance'] =
            map[branch]!['salary_advance']! + amt;
      }
    }

    _branchSummary = map.entries.map((e) {
      return {
        'branch': e.key,
        'cash_in': e.value['cash_in'] ?? 0,
        'cash_out': e.value['cash_out'] ?? 0,
        'expense': e.value['expense'] ?? 0,
        'salary_advance': e.value['salary_advance'] ?? 0,
      };
    }).toList()
      ..sort(
        (a, b) => a['branch']
            .toString()
            .compareTo(b['branch'].toString()),
      );
  }

  Future<void> _loadTransactions() async {
    dynamic query = supabase
        .from('transactions')
        .select()
        .gte('tx_date', '${_dateOnly(_fromDate)}T00:00:00')
        .lte('tx_date', '${_dateOnly(_toDate)}T23:59:59');

    if (_branchFilter != 'ALL') {
      query = query.eq('branch_code', _branchFilter);
    }

    if (_flowFilter != 'ALL') {
      query = query.eq('flow_type', _flowFilter);
    }

    if (_categoryFilter != 'ALL') {
      query = query.eq('category', _categoryFilter);
    }

    if (_paymentFilter != 'ALL') {
      query = query.ilike('payment_method', _paymentFilter);
    }

    final data = await query.order('created_at', ascending: false);

    List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(data);

    if (_searchText.trim().isNotEmpty) {
      final q = _searchText.trim().toLowerCase();
      rows = rows.where((e) {
        final person = (e['person_name'] ?? '').toString().toLowerCase();
        final note = (e['note'] ?? '').toString().toLowerCase();
        final staff = (e['staff_name'] ?? '').toString().toLowerCase();
        final category = (e['category'] ?? '').toString().toLowerCase();
        final branch = (e['branch_code'] ?? '').toString().toLowerCase();
        final createdBy = (e['created_by'] ?? '').toString().toLowerCase();
        return person.contains(q) ||
            note.contains(q) ||
            staff.contains(q) ||
            category.contains(q) ||
            branch.contains(q) ||
            createdBy.contains(q);
      }).toList();
    }

    rows = rows.where((e) {
      final cat = (e['category'] ?? '').toString();
      return cat != 'Commission Paid';
    }).toList();

    _rows = rows;

    _totalIn = _rows
        .where((e) => (e['flow_type'] ?? '').toString().toUpperCase() == 'IN')
        .fold(0.0, (sum, e) => sum + _toDouble(e['amount']));

    _totalOut = _rows
        .where((e) => (e['flow_type'] ?? '').toString().toUpperCase() == 'OUT')
        .fold(0.0, (sum, e) => sum + _toDouble(e['amount']));

    _totalExpense = _rows.where((e) {
      final cat = (e['category'] ?? '').toString();
      return cat == 'Expense' ||
          cat == 'Other Cash Out' ||
          cat == 'Vendor Payment' ||
          cat == 'Refund';
    }).fold(0.0, (sum, e) => sum + _toDouble(e['amount']));

    _totalCommission = List<Map<String, dynamic>>.from(data)
        .where((e) => (e['category'] ?? '').toString() == 'Commission Paid')
        .fold(0.0, (sum, e) => sum + _toDouble(e['amount']));

    _totalSalaryAdvance = _rows
        .where((e) => (e['category'] ?? '').toString() == 'Salary Advance')
        .fold(0.0, (sum, e) => sum + _toDouble(e['amount']));

    _buildBranchSummary();
  }

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() => _fromDate = d);
    }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() => _toDate = d);
    }
  }

  void _msg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Widget _summaryBox(String title, String value, {Color? color}) {
  return Container(
    width: 160,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color ?? Colors.grey.shade100,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSummary() {
  return Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      _summaryBox(
        'Total Sale',
        '₹${_fmt(_todaySale)}',
        color: Colors.blue.shade50,
      ),
      _summaryBox(
        'Cash',
        '₹${_fmt(_cashSale)}',
        color: Colors.green.shade50,
      ),
      _summaryBox(
        'UPI',
        '₹${_fmt(_upiSale)}',
        color: Colors.indigo.shade50,
      ),
      _summaryBox(
        'Card',
        '₹${_fmt(_cardSale)}',
        color: Colors.deepPurple.shade50,
      ),
      _summaryBox(
        'Cash In',
        '₹${_fmt(_totalIn)}',
        color: Colors.green.shade100,
      ),
      _summaryBox(
        'Cash Out',
        '₹${_fmt(_totalOut)}',
        color: Colors.orange.shade100,
      ),
      _summaryBox(
        'Expense',
        '₹${_fmt(_totalExpense)}',
        color: Colors.red.shade50,
      ),
      _summaryBox(
        'Commission',
        '₹${_fmt(_totalCommission)}',
        color: Colors.purple.shade50,
      ),
      _summaryBox(
        'Salary Adv',
        '₹${_fmt(_totalSalaryAdvance)}',
        color: Colors.teal.shade50,
      ),
      _summaryBox(
        'Entries',
        '${_rows.length}',
        color: Colors.grey.shade200,
      ),
    ],
  );
}

  Widget _buildFilters() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _pickFromDate,
              icon: const Icon(Icons.date_range),
              label: Text('From: ${_dateOnly(_fromDate)}'),
            ),
            OutlinedButton.icon(
              onPressed: _pickToDate,
              icon: const Icon(Icons.date_range),
              label: Text('To: ${_dateOnly(_toDate)}'),
            ),
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                value: _branchFilter,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _branches
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _branchFilter = v);
                },
              ),
            ),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<String>(
                value: _flowFilter,
                decoration: const InputDecoration(
                  labelText: 'Flow',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All')),
                  DropdownMenuItem(value: 'IN', child: Text('Cash In')),
                  DropdownMenuItem(value: 'OUT', child: Text('Cash Out')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _flowFilter = v);
                },
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _categoryFilter,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _categories
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _categoryFilter = v);
                },
              ),
            ),
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                value: _paymentFilter,
                decoration: const InputDecoration(
                  labelText: 'Payment',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All')),
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                  DropdownMenuItem(value: 'Card', child: Text('Card')),
                  DropdownMenuItem(value: 'Bank', child: Text('Bank')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _paymentFilter = v);
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Search person / note / staff',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  _searchText = v;
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.search),
              label: const Text('Apply Filters'),
            ),
            TextButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchSummaryTable() {
  if (_branchSummary.isEmpty) return const SizedBox();

  return Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Branch Summary",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ..._branchSummary.map((e) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    e['branch'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text("IN ₹${_fmt(e['cash_in'])}"),
                  Text("OUT ₹${_fmt(e['cash_out'])}"),
                  Text("EXP ₹${_fmt(e['expense'])}"),
                  Text("SAL ₹${_fmt(e['salary_advance'])}"),
                ],
              ),
            );
          }),
        ],
      ),
    ),
  );
}

Widget _chip(dynamic text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text.toString(),
      style: const TextStyle(fontSize: 11),
    ),
  );
}

  Widget _flowChip(bool isIn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isIn ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isIn ? 'Cash In' : 'Cash Out',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isIn ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> e) {
  final isIn =
      (e['flow_type'] ?? '').toString().toUpperCase() == 'IN';

  return Card(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: isIn ? Colors.green : Colors.red,
            width: 5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (e['branch_code'] ?? '').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  "₹${_fmt(e['amount'])}",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isIn ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(e['category']),
                _chip(e['payment_method']),
                _flowChip(isIn),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if ((e['person_name'] ?? '').toString().isNotEmpty)
                  Text("Person: ${e['person_name']}"),
                if ((e['staff_name'] ?? '').toString().isNotEmpty)
                  Text("Staff: ${e['staff_name']}"),
                Text(
                  "Date: ${(e['tx_date'] ?? '').toString().split('T').first}",
                ),
              ],
            ),
            if ((e['note'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                e['note'],
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Victory • Transactions Monitor'),
        ),
        body: const Center(
          child: Text('Access denied'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Victory • Transactions Monitor'),
        actions: [
          IconButton(
            onPressed: _loadAll,
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
  const Align(
    alignment: Alignment.centerLeft,
    child: Text(
      'Overview',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
  const SizedBox(height: 10),
  _buildSummary(),
  const SizedBox(height: 14),

  const Align(
    alignment: Alignment.centerLeft,
    child: Text(
      'Filters',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
  const SizedBox(height: 10),
  _buildFilters(),
  const SizedBox(height: 14),

  const Align(
    alignment: Alignment.centerLeft,
    child: Text(
      'Branch Summary',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
  const SizedBox(height: 10),
  _buildBranchSummaryTable(),
  const SizedBox(height: 14),

  const Align(
    alignment: Alignment.centerLeft,
    child: Text(
      'Transaction Entries',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
  const SizedBox(height: 10),

  Expanded(
                    child: _rows.isEmpty
                        ? const Center(child: Text('No transactions found'))
                        : ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (context, index) {
                              return _buildRow(_rows[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}