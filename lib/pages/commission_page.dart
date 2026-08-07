import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommissionPage extends StatefulWidget {
  final String branchCode;
  final String branchName;

  const CommissionPage({
    super.key,
    required this.branchCode,
    required this.branchName,
  });

  @override
  State<CommissionPage> createState() => _CommissionPageState();
}

class _CommissionPageState extends State<CommissionPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _rates = [];
  List<Map<String, dynamic>> _rows = [];

  String? _selectedTicketId;
  String? _selectedAgentId;
  String? _selectedRateId;

  String _statusFilter = 'ALL';
  String _agentFilter = 'ALL';

  double _finalAmount = 0;
  double _commissionPercent = 0;
  double _commissionAmount = 0;
  bool _commissionPaid = false;

  DateTime _fromDate = DateTime.now();
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

  Map<String, dynamic>? get _selectedTicket {
    try {
      return _tickets.firstWhere((e) => e['id'] == _selectedTicketId);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? get _selectedRate {
    try {
      return _rates.firstWhere((e) => e['id'].toString() == _selectedRateId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await Future.wait([_loadTickets(), _loadAgents(), _loadRates()]);
      await _loadRows();
    } catch (e) {
      _msg('Load error: $e');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadTickets() async {
    try {
      final data = await supabase
          .from('tickets')
          .select(
            'id, ticket_no, branch_code, final_amount, ticket_date, created_at, '
            'agent_id, commission_rate_id, commission_percent, commission_amount, '
            'commission_paid, commission_paid_at',
          )
          .eq('branch_code', _branchCode)
          .gte('ticket_date', _dateOnly(DateTime.now()))
          .lte('ticket_date', _dateOnly(DateTime.now()))
          .order('created_at', ascending: false)
          .limit(500);

      _tickets = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _tickets = [];
      _msg('Tickets load error: $e');
    }
  }

  Future<void> _loadAgents() async {
    try {
      final data = await supabase
          .from('agents')
          .select()
          .eq('branch_code', _branchCode)
          .eq('active', true)
          .order('agent_name', ascending: true);

      _agents = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _agents = [];
      _msg('Agents load error: $e');
    }
  }

  Future<void> _loadRates() async {
    try {
      final data = await supabase
          .from('commission_rate_settings')
          .select()
          .eq('branch_code', _branchCode)
          .order('commission_percent', ascending: true);

      _rates = List<Map<String, dynamic>>.from(data);

      if (_selectedRateId == null && _rates.isNotEmpty) {
        Map<String, dynamic>? primary;
        try {
          primary = _rates.firstWhere(
            (e) => (e['is_primary'] ?? false) == true,
          );
        } catch (_) {
          primary = _rates.first;
        }
        _selectedRateId = primary['id'].toString();
        _commissionPercent = _toDouble(primary['commission_percent']);
        _commissionAmount = (_finalAmount * _commissionPercent) / 100.0;
      }
    } catch (e) {
      _rates = [];
      _msg('Rates load error: $e');
    }
  }

  Future<void> _loadRows() async {
    try {
      dynamic query = supabase
          .from('tickets')
          .select(
            'id, ticket_no, branch_code, final_amount, ticket_date, created_at, '
            'agent_id, commission_rate_id, commission_percent, commission_amount, '
            'commission_paid, commission_paid_at',
          )
          .eq('branch_code', _branchCode)
          .gte('ticket_date', _dateOnly(_fromDate))
          .lte('ticket_date', _dateOnly(_toDate));

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
    } catch (e) {
      _rows = [];
      _msg('Commission rows load error: $e');
    }
  }

  void _onTicketChanged(String? value) {
    setState(() {
      _selectedTicketId = value;

      final t = _selectedTicket;
      _finalAmount = _toDouble(t?['final_amount']);
      _commissionPaid = (t?['commission_paid'] ?? false) == true;
      _selectedAgentId = t?['agent_id']?.toString();

      if (t?['commission_rate_id'] != null) {
        _selectedRateId = t!['commission_rate_id'].toString();
        _commissionPercent = _toDouble(t['commission_percent']);
        _commissionAmount = _toDouble(t['commission_amount']);
      } else {
        Map<String, dynamic>? primary;
        try {
          primary = _rates.firstWhere(
            (e) => (e['is_primary'] ?? false) == true,
          );
        } catch (_) {
          primary = _rates.isNotEmpty ? _rates.first : null;
        }

        _selectedRateId = primary?['id']?.toString();
        _commissionPercent = _toDouble(primary?['commission_percent']);
        _commissionAmount = (_finalAmount * _commissionPercent) / 100.0;
      }
    });
  }

  void _onRateChanged(String? value) {
    setState(() {
      _selectedRateId = value;
      final r = _selectedRate;
      _commissionPercent = _toDouble(r?['commission_percent']);
      _commissionAmount = (_finalAmount * _commissionPercent) / 100.0;
    });
  }

  Future<void> _saveCommission({required bool paid}) async {
    if (_selectedTicketId == null) {
      _msg('Ticket select karo');
      return;
    }
    if (_selectedAgentId == null) {
      _msg('Agent select karo');
      return;
    }
    if (_selectedRateId == null) {
      _msg('Commission rate select karo');
      return;
    }

    setState(() => _saving = true);

    try {
      final selectedTicket = _selectedTicket;
      final oldPaid = (selectedTicket?['commission_paid'] ?? false) == true;

      final agent = _agentById(_selectedAgentId);
      final agentName = (agent?['agent_name'] ?? '').toString();
      final ticketNo = (selectedTicket?['ticket_no'] ?? '').toString();

      await supabase
          .from('tickets')
          .update({
            'agent_id': _selectedAgentId,
            'commission_rate_id': _selectedRateId,
            'commission_percent': _commissionPercent,
            'commission_amount': _commissionAmount,
            'commission_paid': paid,
            'commission_paid_at': paid
                ? DateTime.now().toIso8601String()
                : null,
          })
          .eq('id', _selectedTicketId!);

      // sirf tab transaction entry banao jab pending se paid ho raha ho
      if (!oldPaid && paid) {
        await supabase.from('transactions').insert({
          'branch_code': _branchCode,
          'tx_date': DateTime.now().toIso8601String(),
          'flow_type': 'OUT',
          'category': 'Commission Paid',
          'amount': _commissionAmount,
          'note': 'Commission paid for $ticketNo',
          'person_name': agentName,
          'created_by': 'admin',
          'payment_method': 'Cash',
        });
      }

      _msg(paid ? 'Commission paid saved' : 'Commission pending saved');

      setState(() {
        _selectedTicketId = null;
        _selectedAgentId = null;

        Map<String, dynamic>? primary;
        try {
          primary = _rates.firstWhere(
            (e) => (e['is_primary'] ?? false) == true,
          );
        } catch (_) {
          primary = _rates.isNotEmpty ? _rates.first : null;
        }

        _selectedRateId = primary?['id']?.toString();
        _commissionPercent = _toDouble(primary?['commission_percent']);
        _finalAmount = 0;
        _commissionAmount = 0;
        _commissionPaid = false;
      });

      await _loadAll();
    } catch (e) {
      _msg('Save error: $e');
    }

    if (mounted) {
      setState(() => _saving = false);
    }
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

  void _msg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Map<String, dynamic>? _agentById(String? id) {
    if (id == null) return null;
    try {
      return _agents.firstWhere((e) => e['id'].toString() == id);
    } catch (_) {
      return null;
    }
  }

  double get _totalSale {
    return _rows.fold(0.0, (sum, e) => sum + _toDouble(e['final_amount']));
  }

  double get _totalCommission {
    return _rows.fold(0.0, (sum, e) => sum + _toDouble(e['commission_amount']));
  }

  double get _paidCommission {
    return _rows.fold(
      0.0,
      (sum, e) =>
          sum +
          (((e['commission_paid'] ?? false) == true)
              ? _toDouble(e['commission_amount'])
              : 0),
    );
  }

  Widget _summaryChip(String title, String value) {
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

  Widget _buildSummaryCard() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _summaryChip('Branch', '${widget.branchName} ($_branchCode)'),
        _summaryChip('Tickets', '${_rows.length}'),
        _summaryChip('Total Sale', '₹${_fmt(_totalSale)}'),
        _summaryChip('Total Commission', '₹${_fmt(_totalCommission)}'),
        _summaryChip('Paid', '₹${_fmt(_paidCommission)}'),
      ],
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedTicketId,
                    decoration: const InputDecoration(
                      labelText: 'Ticket',
                      border: OutlineInputBorder(),
                    ),
                    items: _tickets.map((t) {
                      final ticketNo = (t['ticket_no'] ?? '').toString();
                      final amt = _fmt(t['final_amount']);
                      return DropdownMenuItem<String>(
                        value: t['id'].toString(),
                        child: Text('$ticketNo  |  ₹$amt'),
                      );
                    }).toList(),
                    onChanged: _onTicketChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedAgentId,
                    decoration: const InputDecoration(
                      labelText: 'Agent',
                      border: OutlineInputBorder(),
                    ),
                    items: _agents.map((a) {
                      final name = (a['agent_name'] ?? '').toString();
                      final code = (a['agent_code'] ?? '').toString();
                      return DropdownMenuItem<String>(
                        value: a['id'].toString(),
                        child: Text('$name (${code.isEmpty ? "-" : code})'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() => _selectedAgentId = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedRateId,
                    decoration: const InputDecoration(
                      labelText: 'Commission %',
                      border: OutlineInputBorder(),
                    ),
                    items: _rates.map((r) {
                      final label = (r['rate_label'] ?? '').toString();
                      final percent = _fmt(r['commission_percent']);
                      return DropdownMenuItem<String>(
                        value: r['id'].toString(),
                        child: Text(
                          (r['is_primary'] ?? false) == true
                              ? '$label ($percent %) • Default'
                              : '$label ($percent %)',
                        ),
                      );
                    }).toList(),
                    onChanged: _onRateChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('fa_${_finalAmount.toStringAsFixed(2)}'),
                    initialValue: _fmt(_finalAmount),
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Final Amount',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('ca_${_commissionAmount.toStringAsFixed(2)}'),
                    initialValue: _fmt(_commissionAmount),
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Commission Amount',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Pending'),
                  selected: !_commissionPaid,
                  selectedColor: Colors.orange.shade100,
                  onSelected: (_) {
                    setState(() => _commissionPaid = false);
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('Paid'),
                  selected: _commissionPaid,
                  selectedColor: Colors.green.shade100,
                  onSelected: (_) {
                    setState(() => _commissionPaid = true);
                  },
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _commissionPaid
                        ? Colors.green
                        : Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saving
                      ? null
                      : () => _saveCommission(paid: _commissionPaid),
                  icon: Icon(_commissionPaid ? Icons.check_circle : Icons.save),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : (_commissionPaid ? 'Paid & Save' : 'Save Pending'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
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
                DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
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
                const DropdownMenuItem(value: 'ALL', child: Text('All Agents')),
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
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBox(bool paid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: paid ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        paid ? 'PAID' : 'PENDING',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: paid ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rows.isEmpty) {
      return const Center(child: Text('No commission records found'));
    }

    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final r = _rows[index];
        final ticketNo = (r['ticket_no'] ?? '').toString();
        final finalAmt = _fmt(r['final_amount']);
        final percent = _fmt(r['commission_percent']);
        final amount = _fmt(r['commission_amount']);
        final paid = (r['commission_paid'] ?? false) == true;

        final agent = _agentById(r['agent_id']?.toString());
        final agentName = (agent?['agent_name'] ?? '-').toString();
        final agentCode = (agent?['agent_code'] ?? '-').toString();

        return Card(
          color: paid ? Colors.green.shade50 : Colors.orange.shade50,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '$ticketNo  |  ₹$finalAmt  |  Comm: ₹$amount',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _statusBox(paid),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Agent: $agentName ($agentCode)\nPercent: $percent %',
              ),
            ),
            trailing: IconButton(
              tooltip: 'Edit',
              onPressed: () {
                setState(() {
                  _selectedTicketId = r['id'].toString();
                  _selectedAgentId = r['agent_id']?.toString();
                  _selectedRateId = r['commission_rate_id']?.toString();
                  _finalAmount = _toDouble(r['final_amount']);
                  _commissionPercent = _toDouble(r['commission_percent']);
                  _commissionAmount = _toDouble(r['commission_amount']);
                  _commissionPaid = paid;
                });
              },
              icon: const Icon(Icons.edit),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Commission • ${widget.branchName} ($_branchCode)'),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 12),
            _buildFormCard(),
            const SizedBox(height: 12),
            _buildFilterCard(),
            const SizedBox(height: 12),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }
}
