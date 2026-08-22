import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionsPage extends StatefulWidget {
  final String username;
  final String branch;

  const TransactionsPage({
    super.key,
    required this.username,
    required this.branch,
  });

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _closingSaving = false;

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _personCtrl = TextEditingController();
  final TextEditingController _systemBalanceCtrl = TextEditingController();
  final TextEditingController _actualClosingCtrl = TextEditingController();
  final TextEditingController _closingNoteCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();

  String _flowType = 'OUT';
  String _category = 'Expense';
  String _paymentMethod = 'Cash';

  String? _resolvedBranchId;
  String? _selectedStaffName;

  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _entries = [];

  double _openingBalance = 0;
  double _todayCashSale = 0;
  double _otherCashIn = 0;
  double _cashOut = 0;
  double _balanceNow = 0;

  final List<String> _inCategories = const [
    'Other Cash In',
    'Bank Withdraw',
    'Owner Cash',
    'Advance Received',
  ];

  final List<String> _outCategories = const [
    'Expense',
    'Commission Paid',
    'Photo Commission Paid',
    'VR Commission Paid',
    'Salary Advance',
    'Salary Paid',
    'Staff Payment',
    'Vendor Payment',
    'Refund',
    'Deposit To Bank',
    'Other Cash Out',
  ];

  String get _branchCode => widget.branch.trim().toUpperCase();

  bool get _isSalaryCategory =>
      _category == 'Salary Advance' || _category == 'Salary Paid';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _personCtrl.dispose();
    _systemBalanceCtrl.dispose();
    _actualClosingCtrl.dispose();
    _closingNoteCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmt(dynamic v) => _toDouble(v).toStringAsFixed(2);

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  void _msg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _staffName(Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final staffName = (row['staff_name'] ?? '').toString().trim();
    if (staffName.isNotEmpty) return staffName;

    return '';
  }

  Future<void> _resolveBranchId() async {
    final byCode = await supabase
        .from('branches')
        .select('id, code, name')
        .eq('code', _branchCode)
        .maybeSingle();

    if (byCode != null) {
      _resolvedBranchId = (byCode['id'] ?? '').toString();
      return;
    }

    final byName = await supabase
        .from('branches')
        .select('id, code, name')
        .eq('name', widget.branch)
        .maybeSingle();

    if (byName != null) {
      _resolvedBranchId = (byName['id'] ?? '').toString();
    }
  }

  Future<void> _loadStaffList() async {
    await _resolveBranchId();

    if (_resolvedBranchId == null || _resolvedBranchId!.isEmpty) {
      _staffList = [];
      _selectedStaffName = null;
      return;
    }

    try {
      final data = await supabase
          .from('staff')
          .select()
          .eq('branch_id', _resolvedBranchId)
          .order('name', ascending: true);

      _staffList = List<Map<String, dynamic>>.from(data);

      final names = _staffList
          .map((e) => _staffName(e))
          .where((e) => e.isNotEmpty)
          .toList();

      if (_selectedStaffName != null && !names.contains(_selectedStaffName)) {
        _selectedStaffName = null;
      }
    } catch (_) {
      _staffList = [];
      _selectedStaffName = null;
    }
  }

  void _resetClosingFieldsForSelectedDate() {
    _systemBalanceCtrl.clear();
    _actualClosingCtrl.clear();
    _closingNoteCtrl.clear();
  }

  void _syncClosingFields() {
    _systemBalanceCtrl.text = _fmt(_balanceNow);

    if (_actualClosingCtrl.text.trim().isEmpty) {
      _actualClosingCtrl.text = _fmt(_balanceNow);
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    try {
      _resetClosingFieldsForSelectedDate();

      await _loadStaffList();
      await _loadOpeningBalance();
      await _loadCashSale();
      await _loadTransactions();

      _recalculateSummary();

      await _loadTodayClosingIfAny();
    } catch (e) {
      _msg('Load error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadOpeningBalance() async {
    try {
      final previousDate = _selectedDate.subtract(const Duration(days: 1));
      final prevDate = _dateOnly(previousDate);

      final data = await supabase
          .from('cash_day_closing')
          .select('actual_closing_balance, system_balance, closing_date')
          .eq('branch_code', _branchCode)
          .gte('closing_date', '${prevDate}T00:00:00')
          .lte('closing_date', '${prevDate}T23:59:59')
          .order('closing_date', ascending: false)
          .limit(1);

      if (data.isNotEmpty) {
        final row = data.first;
        final actual = _toDouble(row['actual_closing_balance']);
        final system = _toDouble(row['system_balance']);
        _openingBalance = actual > 0 ? actual : system;
      } else {
        _openingBalance = 0;
      }
    } catch (e) {
      _openingBalance = 0;
      _msg('Opening balance load error: $e');
    }
  }

  Future<void> _loadTodayClosingIfAny() async {
    try {
      final date = _dateOnly(_selectedDate);

      final data = await supabase
          .from('cash_day_closing')
          .select('actual_closing_balance, note, system_balance, closing_date')
          .eq('branch_code', _branchCode)
          .gte('closing_date', '${date}T00:00:00')
          .lte('closing_date', '${date}T23:59:59')
          .order('closing_date', ascending: false)
          .limit(1);

      if (data.isNotEmpty) {
        final row = data.first;
        _systemBalanceCtrl.text = _fmt(row['system_balance']);
        _actualClosingCtrl.text = _fmt(
          _toDouble(row['actual_closing_balance']) == 0
              ? _toDouble(row['system_balance'])
              : row['actual_closing_balance'],
        );
        _closingNoteCtrl.text = (row['note'] ?? '').toString();
      } else {
        _systemBalanceCtrl.text = _fmt(_balanceNow);
        _actualClosingCtrl.text = _fmt(_balanceNow);
        _closingNoteCtrl.clear();
      }
    } catch (_) {
      _systemBalanceCtrl.text = _fmt(_balanceNow);
      _actualClosingCtrl.text = _fmt(_balanceNow);
      _closingNoteCtrl.clear();
    }
  }

  Future<void> _loadCashSale() async {
    try {
      final date = _dateOnly(_selectedDate);

      final data = await supabase
          .from('tickets')
          .select('final_amount')
          .eq('branch_code', _branchCode)
          .gte('ticket_date', '${date}T00:00:00')
          .lte('ticket_date', '${date}T23:59:59')
          .ilike('payment_method', 'cash');

      double total = 0;

      for (final row in data) {
        final value = row['final_amount'];
        if (value != null) {
          total += (value as num).toDouble();
        }
      }

      _todayCashSale = total;
    } catch (e) {
      _todayCashSale = 0;
      _msg('Cash sale load error: $e');
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final date = _dateOnly(_selectedDate);

      final data = await supabase
          .from('transactions')
          .select()
          .eq('branch_code', _branchCode)
          .gte('tx_date', '${date}T00:00:00')
          .lte('tx_date', '${date}T23:59:59')
          .order('created_at', ascending: false);

      _entries = List<Map<String, dynamic>>.from(data);
    } catch (_) {
      _entries = [];
    }
  }

  void _recalculateSummary() {
    _otherCashIn = _entries
        .where((e) => (e['flow_type'] ?? '').toString().toUpperCase() == 'IN')
        .fold<double>(0.0, (sum, e) => sum + _toDouble(e['amount']));

    _cashOut = _entries
        .where((e) => (e['flow_type'] ?? '').toString().toUpperCase() == 'OUT')
        .fold<double>(0.0, (sum, e) => sum + _toDouble(e['amount']));

    _balanceNow = _openingBalance + _todayCashSale + _otherCashIn - _cashOut;

    _syncClosingFields();
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
      await _loadAll();
    }
  }

  Future<void> _saveTransaction() async {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amt <= 0) {
      _msg('Amount sahi bharo');
      return;
    }

    if (_isSalaryCategory &&
        (_selectedStaffName == null || _selectedStaffName!.trim().isEmpty)) {
      _msg('Staff select karo');
      return;
    }

    setState(() => _saving = true);

    try {
      await supabase.from('transactions').insert({
        'branch_code': _branchCode,
        'tx_date': _selectedDate.toIso8601String(),
        'flow_type': _flowType,
        'category': _category,
        'amount': amt,
        'note': _noteCtrl.text.trim(),
        'person_name': _personCtrl.text.trim(),
        'created_by': widget.username,
        'payment_method': _paymentMethod,
        'staff_name': _selectedStaffName,
        'salary_linked': _isSalaryCategory,
      });

      _amountCtrl.clear();
      _noteCtrl.clear();
      _personCtrl.clear();
      _selectedStaffName = null;

      await _loadTransactions();
      _recalculateSummary();

      if (mounted) {
        setState(() {});
      }

      _msg('Transaction saved');
    } catch (e) {
      _msg('Save error: $e');
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteTransaction(String id) async {
    try {
      await supabase.from('transactions').delete().eq('id', id);
      await _loadTransactions();
      _recalculateSummary();

      if (mounted) {
        setState(() {});
      }

      _msg('Deleted');
    } catch (e) {
      _msg('Delete error: $e');
    }
  }

  Future<void> _saveClosing() async {
    final actual =
        double.tryParse(_actualClosingCtrl.text.trim()) ?? _balanceNow;

    setState(() => _closingSaving = true);

    try {
      final date = _dateOnly(_selectedDate);

      final existing = await supabase
          .from('cash_day_closing')
          .select('id')
          .eq('branch_code', _branchCode)
          .gte('closing_date', '${date}T00:00:00')
          .lte('closing_date', '${date}T23:59:59')
          .limit(1);

      final payload = {
        'branch_code': _branchCode,
        'closing_date': _selectedDate.toIso8601String(),
        'opening_balance': _openingBalance,
        'cash_sale': _todayCashSale,
        'other_cash_in': _otherCashIn,
        'cash_out': _cashOut,
        'system_balance': _balanceNow,
        'actual_closing_balance': actual,
        'note': _closingNoteCtrl.text.trim(),
        'created_by': widget.username,
      };

      if (existing.isNotEmpty) {
        await supabase
            .from('cash_day_closing')
            .update(payload)
            .eq('id', existing.first['id']);
      } else {
        await supabase.from('cash_day_closing').insert(payload);
      }

      _systemBalanceCtrl.text = _fmt(_balanceNow);
      _actualClosingCtrl.text = _fmt(actual);

      _msg('Closing saved');
    } catch (e) {
      _msg('Closing save error: $e');
    }

    if (mounted) {
      setState(() => _closingSaving = false);
    }
  }

  Widget _summaryCard(String title, String value, {Color? color}) {
    return Container(
      width: 185,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSummary() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _summaryCard('Opening Balance', '₹${_fmt(_openingBalance)}'),
        _summaryCard('Today Cash Sale', '₹${_fmt(_todayCashSale)}'),
        _summaryCard(
          'Other Cash In',
          '₹${_fmt(_otherCashIn)}',
          color: Colors.green.shade50,
        ),
        _summaryCard(
          'Cash Out',
          '₹${_fmt(_cashOut)}',
          color: Colors.orange.shade50,
        ),
        _summaryCard(
          'Cash In Hand Now',
          '₹${_fmt(_balanceNow)}',
          color: Colors.blue.shade50,
        ),
      ],
    );
  }

  Widget _buildEntryForm() {
    final categories = _flowType == 'IN' ? _inCategories : _outCategories;

    if (!categories.contains(_category)) {
      _category = categories.first;
    }

    final staffNames = _staffList
        .map((s) => _staffName(s))
        .where((name) => name.isNotEmpty)
        .toList();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _flowType,
                    decoration: const InputDecoration(
                      labelText: 'Flow Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'IN', child: Text('Cash In')),
                      DropdownMenuItem(value: 'OUT', child: Text('Cash Out')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _flowType = v;
                        _category = v == 'IN'
                            ? _inCategories.first
                            : _outCategories.first;
                        _selectedStaffName = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: categories
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e,
                            child: Text(e),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _category = v;
                        if (!_isSalaryCategory) {
                          _selectedStaffName = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _personCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Person / From / To',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'Bank', child: Text('Bank')),
                      DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _paymentMethod = v);
                    },
                  ),
                ),
              ],
            ),
            if (_isSalaryCategory) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedStaffName,
                decoration: const InputDecoration(
                  labelText: 'Select Staff',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: staffNames
                    .map(
                      (name) => DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedStaffName = v;
                  });
                },
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.date_range),
                  label: Text(_dateOnly(_selectedDate)),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _saveTransaction,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(_saving ? 'Saving...' : 'Save Entry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosingCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Day Closing',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _systemBalanceCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'System Balance',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _actualClosingCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Actual Closing Cash',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _closingNoteCtrl,
              decoration: const InputDecoration(
                labelText: 'Closing Note',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _closingSaving ? null : _saveClosing,
                icon: const Icon(Icons.save, size: 18),
                label: Text(_closingSaving ? 'Saving...' : 'Save Closing'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return const Center(child: Text('No transactions found'));
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final e = _entries[index];
        final isIn = (e['flow_type'] ?? '').toString().toUpperCase() == 'IN';
        final category = (e['category'] ?? '').toString();
        final amt = _fmt(e['amount']);
        final note = (e['note'] ?? '').toString();
        final person = (e['person_name'] ?? '').toString();
        final staff = (e['staff_name'] ?? '').toString();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isIn ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isIn ? Colors.green.shade200 : Colors.orange.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isIn ? Icons.south_west : Icons.north_east,
                size: 18,
                color: isIn ? Colors.green.shade800 : Colors.orange.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$category • ₹$amt'
                  '${person.isNotEmpty ? ' • $person' : ''}'
                  '${staff.isNotEmpty ? ' • $staff' : ''}'
                  '${note.isNotEmpty ? ' • $note' : ''}',
                  style: const TextStyle(fontSize: 12.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => _deleteTransaction(e['id'].toString()),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transactions • $_branchCode • ${_dateOnly(_selectedDate)}',
        ),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopSummary(),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildEntryForm(),
                    const SizedBox(height: 12),
                    _buildClosingCard(),
                    const SizedBox(height: 12),
                    SizedBox(height: 220, child: _buildEntryList()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
