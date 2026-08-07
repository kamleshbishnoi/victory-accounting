import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgentCommissionReportPage extends StatefulWidget {
  final String branchCode;
  final String branchName;

  const AgentCommissionReportPage({
    super.key,
    required this.branchCode,
    required this.branchName,
  });

  @override
  State<AgentCommissionReportPage> createState() =>
      _AgentCommissionReportPageState();
}

class _AgentCommissionReportPageState extends State<AgentCommissionReportPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;

  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _rows = [];

  String _agentFilter = 'ALL';
  String _statusFilter = 'ALL';

  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();

  String get _branchCode => widget.branchCode.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmt(dynamic v) => _toDouble(v).toStringAsFixed(2);

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final agentData = await supabase
          .from('agents')
          .select()
          .eq('branch_code', _branchCode)
          .eq('active', true)
          .order('agent_name', ascending: true);

      _agents = List<Map<String, dynamic>>.from(agentData);
      await _loadRows();
    } catch (e) {
      _msg('Load error: $e');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadRows() async {
    try {
      dynamic query = supabase
          .from('tickets')
          .select(
            'id, ticket_no, final_amount, commission_percent, commission_amount, '
            'commission_paid, ticket_date, created_at, agent_id',
          )
          .eq('branch_code', _branchCode)
          .gte('ticket_date', _dateOnly(_fromDate))
          .lte('ticket_date', _dateOnly(_toDate))
          .not('agent_id', 'is', null);

      if (_statusFilter == 'PAID') {
        query = query.eq('commission_paid', true);
      } else if (_statusFilter == 'PENDING') {
        query = query.eq('commission_paid', false);
      }

      if (_agentFilter != 'ALL') {
        query = query.eq('agent_id', _agentFilter);
      }

      final data = await query.order('created_at', ascending: false);
      _rows = List<Map<String, dynamic>>.from(data);
      setState(() {});
    } catch (e) {
      _msg('Rows load error: $e');
    }
  }

  Map<String, dynamic>? _agentById(String? id) {
    if (id == null) return null;
    try {
      return _agents.firstWhere((e) => e['id'].toString() == id);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _buildSummary() {
    final Map<String, Map<String, dynamic>> summary = {};

    for (final row in _rows) {
      final agentId = row['agent_id']?.toString();
      if (agentId == null || agentId.isEmpty) continue;

      final agent = _agentById(agentId);
      final agentName = (agent?['agent_name'] ?? '-').toString();
      final agentCode = (agent?['agent_code'] ?? '-').toString();
      final amount = _toDouble(row['commission_amount']);
      final paid = (row['commission_paid'] ?? false) == true;

      summary.putIfAbsent(agentId, () {
        return {
          'agent_name': agentName,
          'agent_code': agentCode,
          'entries': 0,
          'total_commission': 0.0,
          'paid_commission': 0.0,
          'pending_commission': 0.0,
        };
      });

      summary[agentId]!['entries'] = (summary[agentId]!['entries'] as int) + 1;
      summary[agentId]!['total_commission'] =
          (summary[agentId]!['total_commission'] as double) + amount;

      if (paid) {
        summary[agentId]!['paid_commission'] =
            (summary[agentId]!['paid_commission'] as double) + amount;
      } else {
        summary[agentId]!['pending_commission'] =
            (summary[agentId]!['pending_commission'] as double) + amount;
      }
    }

    final list = summary.entries.map((e) {
      return {'agent_id': e.key, ...e.value};
    }).toList();

    list.sort(
      (a, b) => (a['agent_name'] ?? '').toString().compareTo(
        (b['agent_name'] ?? '').toString(),
      ),
    );

    return list;
  }

  double get _totalCommission =>
      _rows.fold(0.0, (sum, e) => sum + _toDouble(e['commission_amount']));

  double get _paidCommission => _rows.fold(
    0.0,
    (sum, e) =>
        sum +
        (((e['commission_paid'] ?? false) == true)
            ? _toDouble(e['commission_amount'])
            : 0),
  );

  double get _pendingCommission => _rows.fold(
    0.0,
    (sum, e) =>
        sum +
        (((e['commission_paid'] ?? false) == false)
            ? _toDouble(e['commission_amount'])
            : 0),
  );

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() => _fromDate = d);
      await _loadRows();
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
      await _loadRows();
    }
  }

  Future<void> _exportCsv() async {
    try {
      final summary = _buildSummary();

      final buffer = StringBuffer();
      buffer.writeln(
        'Agent Name,Agent Code,Entries,Total Commission,Paid,Pending',
      );

      for (final s in summary) {
        buffer.writeln(
          '"${s['agent_name']}","${s['agent_code']}",${s['entries']},'
          '${_fmt(s['total_commission'])},${_fmt(s['paid_commission'])},${_fmt(s['pending_commission'])}',
        );
      }

      final fileName =
          'agent_commission_report_${_branchCode}_${_dateOnly(_fromDate)}_to_${_dateOnly(_toDate)}.csv';

      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );

      if (location == null) {
        _msg('Export cancelled');
        return;
      }

      final file = File(location.path);
      await file.writeAsString(buffer.toString(), flush: true);

      _msg('CSV exported successfully');
    } catch (e) {
      _msg('Export error: $e');
    }
  }

  void _msg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _chip(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '$title: $value',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _buildSummary();

    return Scaffold(
      appBar: AppBar(
        title: Text('Agent Commission Report • ${widget.branchName}'),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _exportCsv, icon: const Icon(Icons.download)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _chip('Branch', widget.branchName),
                _chip('Entries', '${_rows.length}'),
                _chip('Total', '₹${_fmt(_totalCommission)}'),
                _chip('Paid', '₹${_fmt(_paidCommission)}'),
                _chip('Pending', '₹${_fmt(_pendingCommission)}'),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
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
                    DropdownButton<String>(
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('All')),
                        DropdownMenuItem(value: 'PAID', child: Text('Paid')),
                        DropdownMenuItem(
                          value: 'PENDING',
                          child: Text('Pending'),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _statusFilter = v);
                        await _loadRows();
                      },
                    ),
                    DropdownButton<String>(
                      value: _agentFilter,
                      items: [
                        const DropdownMenuItem(
                          value: 'ALL',
                          child: Text('All Agents'),
                        ),
                        ..._agents.map((a) {
                          final name = (a['agent_name'] ?? '').toString();
                          final code = (a['agent_code'] ?? '').toString();
                          return DropdownMenuItem(
                            value: a['id'].toString(),
                            child: Text('$name (${code.isEmpty ? "-" : code})'),
                          );
                        }),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _agentFilter = v);
                        await _loadRows();
                      },
                    ),
                    ElevatedButton.icon(
                      onPressed: _loadRows,
                      icon: const Icon(Icons.search),
                      label: const Text('Show Report'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _exportCsv,
                      icon: const Icon(Icons.download),
                      label: const Text('Export CSV'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : summary.isEmpty
                  ? const Center(child: Text('No report data found'))
                  : ListView.separated(
                      itemCount: summary.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final s = summary[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    '${s['agent_name']} (${s['agent_code']})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text('Entries: ${s['entries']}'),
                                ),
                                Expanded(
                                  child: Text(
                                    'Total: ₹${_fmt(s['total_commission'])}',
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Paid: ₹${_fmt(s['paid_commission'])}',
                                    style: const TextStyle(color: Colors.green),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Pending: ₹${_fmt(s['pending_commission'])}',
                                    style: const TextStyle(
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
