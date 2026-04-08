import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCommissionMonitorPage extends StatefulWidget {
  final String username;

  const AdminCommissionMonitorPage({
    super.key,
    required this.username,
  });

  @override
  State<AdminCommissionMonitorPage> createState() =>
      _AdminCommissionMonitorPageState();
}

class _AdminCommissionMonitorPageState
    extends State<AdminCommissionMonitorPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  String _branchFilter = 'ALL';
  String _statusFilter = 'ALL';
  String _searchText = '';

  List<String> _branches = [];
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _branchSummary = [];

  double _totalSale = 0;
  double _totalCommission = 0;
  double _paidCommission = 0;
  double _pendingCommission = 0;

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

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await _loadBranches();
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
          .from('tickets')
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

  Future<void> _applyFilters() async {
    await _loadRows();
    if (mounted) setState(() {});
  }

  void _buildBranchSummary() {
    final Map<String, Map<String, double>> map = {};

    for (final row in _rows) {
      final branch = (row['branch_code'] ?? '').toString();
      final sale = _toDouble(row['final_amount']);
      final comm = _toDouble(row['commission_amount']);
      final paid = (row['commission_paid'] ?? false) == true;

      map.putIfAbsent(branch, () => {
            'sale': 0,
            'commission': 0,
            'paid': 0,
            'pending': 0,
          });

      map[branch]!['sale'] = map[branch]!['sale']! + sale;
      map[branch]!['commission'] = map[branch]!['commission']! + comm;

      if (paid) {
        map[branch]!['paid'] = map[branch]!['paid']! + comm;
      } else {
        map[branch]!['pending'] = map[branch]!['pending']! + comm;
      }
    }

    _branchSummary = map.entries.map((e) {
      return {
        'branch': e.key,
        'sale': e.value['sale'] ?? 0,
        'commission': e.value['commission'] ?? 0,
        'paid': e.value['paid'] ?? 0,
        'pending': e.value['pending'] ?? 0,
      };
    }).toList()
      ..sort((a, b) =>
          a['branch'].toString().compareTo(b['branch'].toString()));
  }

  Future<void> _loadRows() async {
    dynamic query = supabase
        .from('tickets')
        .select(
          'id, ticket_no, branch_code, final_amount, ticket_date, created_at, '
          'agent_id, commission_percent, commission_amount, commission_paid, commission_paid_at',
        )
        .gte('ticket_date', '${_dateOnly(_fromDate)}T00:00:00')
        .lte('ticket_date', '${_dateOnly(_toDate)}T23:59:59');

    if (_branchFilter != 'ALL') {
      query = query.eq('branch_code', _branchFilter);
    }

    if (_statusFilter == 'PAID') {
      query = query.eq('commission_paid', true);
    } else if (_statusFilter == 'PENDING') {
      query = query.eq('commission_paid', false);
    }

    final data = await query.order('created_at', ascending: false);

    List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(data);

    if (_searchText.trim().isNotEmpty) {
      final q = _searchText.trim().toLowerCase();
      rows = rows.where((e) {
        final ticketNo = (e['ticket_no'] ?? '').toString().toLowerCase();
        final branch = (e['branch_code'] ?? '').toString().toLowerCase();
        return ticketNo.contains(q) || branch.contains(q);
      }).toList();
    }

    _rows = rows;

    _totalSale = _rows.fold(
      0.0,
      (sum, e) => sum + _toDouble(e['final_amount']),
    );

    _totalCommission = _rows.fold(
      0.0,
      (sum, e) => sum + _toDouble(e['commission_amount']),
    );

    _paidCommission = _rows.fold(
      0.0,
      (sum, e) => sum + (((e['commission_paid'] ?? false) == true)
          ? _toDouble(e['commission_amount'])
          : 0.0),
    );

    _pendingCommission = _rows.fold(
      0.0,
      (sum, e) => sum + (((e['commission_paid'] ?? false) == false)
          ? _toDouble(e['commission_amount'])
          : 0.0),
    );

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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _summaryBox('Total Sale', '₹${_fmt(_totalSale)}'),
        _summaryBox('Total Commission', '₹${_fmt(_totalCommission)}'),
        _summaryBox(
          'Paid Commission',
          '₹${_fmt(_paidCommission)}',
          color: Colors.green.shade50,
        ),
        _summaryBox(
          'Pending Commission',
          '₹${_fmt(_pendingCommission)}',
          color: Colors.orange.shade50,
        ),
        _summaryBox('Entries', '${_rows.length}'),
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
              width: 150,
              child: DropdownButtonFormField<String>(
                value: _statusFilter,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All')),
                  DropdownMenuItem(value: 'PAID', child: Text('Paid')),
                  DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _statusFilter = v);
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Search ticket / branch',
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
    if (_branchSummary.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Branch Wise Commission Summary',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            ..._branchSummary.map((e) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(
                        e['branch'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(child: Text('Sale: ₹${_fmt(e['sale'])}')),
                    Expanded(child: Text('Comm: ₹${_fmt(e['commission'])}')),
                    Expanded(child: Text('Paid: ₹${_fmt(e['paid'])}')),
                    Expanded(child: Text('Pending: ₹${_fmt(e['pending'])}')),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool paid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: paid ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        paid ? 'PAID' : 'PENDING',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: paid ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> e) {
    final ticketNo = (e['ticket_no'] ?? '-').toString();
    final branch = (e['branch_code'] ?? '-').toString();
    final sale = _fmt(e['final_amount']);
    final percent = _fmt(e['commission_percent']);
    final commission = _fmt(e['commission_amount']);
    final paid = (e['commission_paid'] ?? false) == true;
    final ticketDate = (e['ticket_date'] ?? '').toString().split('T').first;
    final paidAt = (e['commission_paid_at'] ?? '').toString();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(
              color: paid ? Colors.green : Colors.orange,
              width: 5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      branch,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _statusChip(paid),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Ticket: $ticketNo',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '₹$commission',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: paid
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  Text('Sale: ₹$sale'),
                  Text('Percent: $percent %'),
                  Text('Date: $ticketDate'),
                ],
              ),
              if (paidAt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Paid At: $paidAt',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
          title: const Text('Commission Monitor'),
        ),
        body: const Center(
          child: Text('Access denied'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commission Monitor'),
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
                  _buildSummary(),
                  const SizedBox(height: 12),
                  _buildFilters(),
                  const SizedBox(height: 12),
                  _buildBranchSummaryTable(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _rows.isEmpty
                        ? const Center(child: Text('No commission records found'))
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