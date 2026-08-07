import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSalaryPage extends StatefulWidget {
  const AdminSalaryPage({super.key});

  @override
  State<AdminSalaryPage> createState() => _AdminSalaryPageState();
}

class _AdminSalaryPageState extends State<AdminSalaryPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _loading = true;
  bool _exporting = false;

  DateTime _selectedMonth = DateTime.now();
  String _branchFilter = 'ALL';

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rows = [];

  double _totalNet = 0;
  double _totalAdvance = 0;
  double _totalPaid = 0;
  double _totalRemaining = 0;

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _fmt(dynamic value) => _toDouble(value).toStringAsFixed(2);

  String _dateOnly(DateTime date) =>
      date.toIso8601String().split('T').first;

  String _monthText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  String _staffName(Map<String, dynamic> row) {
    return (row['name'] ?? row['staff_name'] ?? '').toString().trim();
  }

  void _msg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSalary();
  }

  Future<void> _loadSalary() async {
    if (mounted) setState(() => _loading = true);

    try {
      final List<dynamic> branchData = await supabase
          .from('branches')
          .select('id, code, name')
          .order('code');

      _branches = branchData
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final DateTime start =
          DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final DateTime end =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

      final List<Map<String, dynamic>> selectedBranches =
          _branchFilter == 'ALL'
              ? _branches
              : _branches
                  .where(
                    (Map<String, dynamic> b) =>
                        (b['code'] ?? '').toString() == _branchFilter,
                  )
                  .toList();

      final List<Map<String, dynamic>> resultRows = [];

      for (final Map<String, dynamic> branch in selectedBranches) {
        final String branchId = (branch['id'] ?? '').toString();
        final String branchCode = (branch['code'] ?? '').toString();

        final List<dynamic> staffData = await supabase
            .from('staff')
            .select()
            .eq('branch_id', branchId)
            .order('name');

        final List<dynamic> attendanceData = await supabase
            .from('attendance')
            .select()
            .eq('branch_code', branchCode)
            .gte('att_date', _dateOnly(start))
            .lte('att_date', _dateOnly(end));

        final List<dynamic> transactionData = await supabase
            .from('transactions')
            .select()
            .eq('branch_code', branchCode)
            .gte('tx_date', _dateOnly(start))
            .lte('tx_date', _dateOnly(end));

        final Map<String, Map<String, dynamic>> result = {};

        for (final dynamic item in staffData) {
          final Map<String, dynamic> staff =
              Map<String, dynamic>.from(item as Map);
          final String name = _staffName(staff);
          if (name.isEmpty) continue;

          result[name.toLowerCase()] = {
            'staff_name': name,
            'branch_code': branchCode,
            'salary': _toDouble(staff['salary']),
            'present_days': 0.0,
            'late_count': 0,
            'advance': 0.0,
            'paid': 0.0,
          };
        }

        for (final dynamic item in attendanceData) {
          final Map<String, dynamic> attendance =
              Map<String, dynamic>.from(item as Map);
          final String name =
              (attendance['staff_name'] ?? '').toString().trim().toLowerCase();
          if (!result.containsKey(name)) continue;

          result[name]!['present_days'] =
              _toDouble(result[name]!['present_days']) +
                  _toDouble(attendance['day_fraction']);

          if (attendance['late_mark'] == true) {
            result[name]!['late_count'] =
                ((result[name]!['late_count'] ?? 0) as int) + 1;
          }
        }

        for (final dynamic item in transactionData) {
          final Map<String, dynamic> transaction =
              Map<String, dynamic>.from(item as Map);
          final String name = (transaction['staff_name'] ??
                  transaction['person_name'] ??
                  '')
              .toString()
              .trim()
              .toLowerCase();

          if (!result.containsKey(name)) continue;

          final String category =
              (transaction['category'] ?? '').toString().trim();
          final double amount = _toDouble(transaction['amount']);

          if (category == 'Salary Advance') {
            result[name]!['advance'] =
                _toDouble(result[name]!['advance']) + amount;
          } else if (category == 'Salary Paid') {
            result[name]!['paid'] =
                _toDouble(result[name]!['paid']) + amount;
          }
        }

        final int totalDays = end.day;

        for (final Map<String, dynamic> value in result.values) {
          final double monthlySalary = _toDouble(value['salary']);
          final double presentDays = _toDouble(value['present_days']);
          final int lateCount = (value['late_count'] ?? 0) as int;
          final int latePenaltyDays = lateCount ~/ 3;
          final double payableDays =
              (presentDays - latePenaltyDays).clamp(0, totalDays).toDouble();
          final double perDay = totalDays == 0 ? 0 : monthlySalary / totalDays;
          final double netSalary = perDay * payableDays;
          final double advance = _toDouble(value['advance']);
          final double paid = _toDouble(value['paid']);
          final double remaining = netSalary - advance - paid;

          resultRows.add({
            ...value,
            'total_days': totalDays,
            'payable_days': payableDays,
            'late_penalty_days': latePenaltyDays,
            'net_salary': netSalary,
            'remaining': remaining,
          });
        }
      }

      resultRows.sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) {
          final int branchCompare = a['branch_code']
              .toString()
              .compareTo(b['branch_code'].toString());
          if (branchCompare != 0) return branchCompare;
          return a['staff_name'].toString().compareTo(
                b['staff_name'].toString(),
              );
        },
      );

      _rows = resultRows;
      _totalNet = _rows.fold(
        0,
        (double sum, Map<String, dynamic> row) =>
            sum + _toDouble(row['net_salary']),
      );
      _totalAdvance = _rows.fold(
        0,
        (double sum, Map<String, dynamic> row) =>
            sum + _toDouble(row['advance']),
      );
      _totalPaid = _rows.fold(
        0,
        (double sum, Map<String, dynamic> row) =>
            sum + _toDouble(row['paid']),
      );
      _totalRemaining = _rows.fold(
        0,
        (double sum, Map<String, dynamic> row) =>
            sum + _toDouble(row['remaining']),
      );
    } catch (error) {
      _msg('Salary load error: $error');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => _selectedMonth = picked);
      await _loadSalary();
    }
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;

    setState(() => _exporting = true);
    try {
      final pw.Document document = pw.Document();

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (_) => [
            pw.Text(
              'Victory Salary Report - ${_monthText(_selectedMonth)}',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Branch',
                'Staff',
                'Salary',
                'Days',
                'Late',
                'Net',
                'Advance',
                'Paid',
                'Remaining',
              ],
              data: _rows
                  .map(
                    (Map<String, dynamic> row) => [
                      row['branch_code'].toString(),
                      row['staff_name'].toString(),
                      _fmt(row['salary']),
                      _fmt(row['payable_days']),
                      row['late_count'].toString(),
                      _fmt(row['net_salary']),
                      _fmt(row['advance']),
                      _fmt(row['paid']),
                      _fmt(row['remaining']),
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );

      final Uint8List bytes = Uint8List.fromList(await document.save());
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'victory_salary_${_monthText(_selectedMonth)}.pdf',
      );
    } catch (error) {
      _msg('PDF error: $error');
    }
    if (mounted) setState(() => _exporting = false);
  }

  Widget _box(String title, String value, Color color) {
    return Container(
      width: 155,
      height: 80,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                row['branch_code'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                row['staff_name'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: Text('₹${_fmt(row['salary'])}')),
            Expanded(child: Text(_fmt(row['payable_days']))),
            Expanded(child: Text('${row['late_count']}')),
            Expanded(child: Text('₹${_fmt(row['net_salary'])}')),
            Expanded(child: Text('₹${_fmt(row['advance'])}')),
            Expanded(child: Text('₹${_fmt(row['paid'])}')),
            Expanded(child: Text('₹${_fmt(row['remaining'])}')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> branchCodes = [
      'ALL',
      ..._branches.map(
        (Map<String, dynamic> b) => (b['code'] ?? '').toString(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary Monitor'),
        actions: [
          IconButton(
            tooltip: 'Select Month',
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadSalary,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _box(
                      'Month',
                      _monthText(_selectedMonth),
                      Colors.blue.shade50,
                    ),
                    _box(
                      'Net Payable',
                      '₹${_fmt(_totalNet)}',
                      Colors.indigo.shade50,
                    ),
                    _box(
                      'Advance',
                      '₹${_fmt(_totalAdvance)}',
                      Colors.orange.shade50,
                    ),
                    _box(
                      'Paid',
                      '₹${_fmt(_totalPaid)}',
                      Colors.green.shade50,
                    ),
                    _box(
                      'Remaining',
                      '₹${_fmt(_totalRemaining)}',
                      Colors.red.shade50,
                    ),
                    _box(
                      'Staff',
                      '${_rows.length}',
                      Colors.grey.shade200,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            initialValue: branchCodes.contains(_branchFilter)
                                ? _branchFilter
                                : 'ALL',
                            decoration: const InputDecoration(
                              labelText: 'Branch',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: branchCodes
                                .map(
                                  (String value) =>
                                      DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(
                                      value == 'ALL' ? 'All' : value,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (String? value) async {
                              if (value == null) return;
                              setState(() => _branchFilter = value);
                              await _loadSalary();
                            },
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickMonth,
                          icon: const Icon(Icons.calendar_month),
                          label: Text(_monthText(_selectedMonth)),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _exporting ? null : _exportPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Export A4 PDF'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(child: Text('No salary data found')),
                  )
                else ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('Branch')),
                        Expanded(flex: 4, child: Text('Staff')),
                        Expanded(child: Text('Salary')),
                        Expanded(child: Text('Days')),
                        Expanded(child: Text('Late')),
                        Expanded(child: Text('Net')),
                        Expanded(child: Text('Advance')),
                        Expanded(child: Text('Paid')),
                        Expanded(child: Text('Remaining')),
                      ],
                    ),
                  ),
                  const Divider(),
                  ..._rows.map(_buildRow),
                ],
              ],
            ),
    );
  }
}
