import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAttendancePage extends StatefulWidget {
  const AdminAttendancePage({super.key});

  @override
  State<AdminAttendancePage> createState() => _AdminAttendancePageState();
}

class _AdminAttendancePageState extends State<AdminAttendancePage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _exporting = false;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  String _branchFilter = 'ALL';
  String _statusFilter = 'ALL';
  String _searchText = '';

  List<Map<String, dynamic>> _allRows = [];
  List<Map<String, dynamic>> _rows = [];
  List<String> _branches = ['ALL'];

  int _presentCount = 0;
  int _absentCount = 0;
  int _halfDayCount = 0;
  int _lateCount = 0;
  int _paidOffCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;

  String _displayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
  }

  DateTime _parseDate(dynamic value) {
    return DateTime.tryParse((value ?? '').toString()) ?? DateTime.now();
  }

  String _statusOf(Map<String, dynamic> row) {
    return (row['status'] ?? '').toString().trim();
  }

  String _branchOf(Map<String, dynamic> row) {
    final String branch = (row['branch_code'] ?? '').toString().trim();
    return branch.isEmpty ? '-' : branch.toUpperCase();
  }

  String _staffName(Map<String, dynamic> row) {
    return (row['staff_name'] ?? '').toString().trim();
  }

  void _msg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadAttendance() async {
    if (mounted) setState(() => _loading = true);

    try {
      final List<dynamic> data = await supabase
          .from('attendance')
          .select()
          .order('att_date', ascending: false);

      _allRows = data
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final Set<String> branchSet = {};
      for (final Map<String, dynamic> row in _allRows) {
        final String branch = _branchOf(row);
        if (branch != '-') branchSet.add(branch);
      }

      _branches = ['ALL', ...branchSet.toList()..sort()];
      if (!_branches.contains(_branchFilter)) _branchFilter = 'ALL';

      _applyFilters(showRefresh: false);
    } catch (error) {
      _msg('Attendance load error: $error');
    }

    if (mounted) setState(() => _loading = false);
  }

  void _applyFilters({bool showRefresh = true}) {
    if (_fromDate.isAfter(_toDate)) {
      _msg('From Date, To Date se baad ki nahi ho sakti.');
      return;
    }

    final DateTime from =
        DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
    final DateTime to =
        DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
    final String search = _searchText.trim().toLowerCase();

    _rows = _allRows.where((Map<String, dynamic> row) {
      final DateTime date = _parseDate(row['att_date']);
      final String status = _statusOf(row).toUpperCase();

      final bool dateMatch = !date.isBefore(from) && !date.isAfter(to);
      final bool branchMatch =
          _branchFilter == 'ALL' || _branchOf(row) == _branchFilter;
      final bool statusMatch =
          _statusFilter == 'ALL' || status == _statusFilter;

      final String searchable = [
        _staffName(row),
        _branchOf(row),
        row['status'],
        row['att_date'],
        row['in_time'],
        row['out_time'],
        row['remarks'],
      ].map((dynamic value) => (value ?? '').toString().toLowerCase()).join(' ');

      return dateMatch &&
          branchMatch &&
          statusMatch &&
          (search.isEmpty || searchable.contains(search));
    }).toList()
      ..sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            _parseDate(b['att_date']).compareTo(_parseDate(a['att_date'])),
      );

    _calculateSummary();
    if (showRefresh && mounted) setState(() {});
  }

  void _calculateSummary() {
    _presentCount = 0;
    _absentCount = 0;
    _halfDayCount = 0;
    _lateCount = 0;
    _paidOffCount = 0;

    for (final Map<String, dynamic> row in _rows) {
      switch (_statusOf(row).toUpperCase()) {
        case 'PRESENT':
          _presentCount++;
          break;
        case 'ABSENT':
          _absentCount++;
          break;
        case 'HALF DAY':
        case 'HALF_DAY':
          _halfDayCount++;
          break;
        case 'LATE':
          _lateCount++;
          break;
        case 'PAID OFF':
          _paidOffCount++;
          break;
      }
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: from ? _fromDate : _toDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        if (from) {
          _fromDate = date;
          if (_fromDate.isAfter(_toDate)) _toDate = date;
        } else {
          _toDate = date;
          if (_toDate.isBefore(_fromDate)) _fromDate = date;
        }
      });
    }
  }

  Future<void> _resetFilters() async {
    setState(() {
      _fromDate = DateTime.now();
      _toDate = DateTime.now();
      _branchFilter = 'ALL';
      _statusFilter = 'ALL';
      _searchText = '';
      _searchController.clear();
    });
    _applyFilters();
  }

  Future<void> _editAttendance(Map<String, dynamic> row) async {
    final dynamic id = row['id'];
    if (id == null) {
      _msg('Attendance ID nahi mili.');
      return;
    }

    DateTime selectedDate = _parseDate(row['att_date']);
    String status = _statusOf(row);

    const List<String> statuses = [
      'Present',
      'Absent',
      'Late',
      'Half Day',
      '3/4 Day',
      '1/4 Day',
      'Paid Off',
    ];

    if (!statuses.contains(status)) status = 'Present';

    final TextEditingController staffController = TextEditingController(
      text: _staffName(row),
    );
    final TextEditingController inController = TextEditingController(
      text: (row['in_time'] ?? '').toString(),
    );
    final TextEditingController outController = TextEditingController(
      text: (row['out_time'] ?? '').toString(),
    );
    final TextEditingController remarksController = TextEditingController(
      text: (row['remarks'] ?? '').toString(),
    );

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setD) {
            return AlertDialog(
              title: const Text('Edit Attendance'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: staffController,
                        decoration: const InputDecoration(
                          labelText: 'Staff Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final DateTime? date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2100),
                          );
                          if (date != null) setD(() => selectedDate = date);
                        },
                        icon: const Icon(Icons.calendar_month),
                        label: Text(_displayDate(selectedDate)),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: statuses
                            .map(
                              (String value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (String? value) {
                          if (value != null) status = value;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: inController,
                              decoration: const InputDecoration(
                                labelText: 'In Time',
                                hintText: '09:00',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: outController,
                              decoration: const InputDecoration(
                                labelText: 'Out Time',
                                hintText: '18:30',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: remarksController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Remarks',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final String staffName = staffController.text.trim();
                    if (staffName.isEmpty) {
                      _msg('Staff name enter karo.');
                      return;
                    }

                    try {
                      await supabase.from('attendance').update({
                        'staff_name': staffName,
                        'att_date': _dateOnly(selectedDate),
                        'status': status,
                        'in_time': inController.text.trim().isEmpty
                            ? null
                            : inController.text.trim(),
                        'out_time': outController.text.trim().isEmpty
                            ? null
                            : outController.text.trim(),
                        'remarks': remarksController.text.trim(),
                      }).eq('id', id);

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (error) {
                      _msg('Attendance update error: $error');
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    staffController.dispose();
    inController.dispose();
    outController.dispose();
    remarksController.dispose();

    if (saved == true) {
      _msg('Attendance update ho gayi.');
      await _loadAttendance();
    }
  }

  Future<void> _deleteAttendance(Map<String, dynamic> row) async {
    final dynamic id = row['id'];
    if (id == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete Attendance?'),
        content: Text('${_staffName(row)} ki entry delete ho jayegi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete),
            label: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('attendance').delete().eq('id', id);
      _msg('Attendance delete ho gayi.');
      await _loadAttendance();
    } catch (error) {
      _msg('Delete error: $error');
    }
  }

  Future<pw.Document> _buildPdf() async {
    final pw.Document document = pw.Document();

    final List<List<String>> tableRows = _rows.map((row) {
      return [
        (row['att_date'] ?? '').toString(),
        _branchOf(row),
        _staffName(row),
        _statusOf(row),
        (row['in_time'] ?? '').toString(),
        (row['out_time'] ?? '').toString(),
        (row['remarks'] ?? '').toString(),
      ];
    }).toList();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Victory Attendance Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${_displayDate(_fromDate)} to ${_displayDate(_toDate)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Branch',
              'Staff',
              'Status',
              'In',
              'Out',
              'Remarks',
            ],
            data: tableRows,
            headerStyle:
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            border:
                pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
          ),
        ],
      ),
    );

    return document;
  }

  Future<void> _printA4() async {
    if (_rows.isEmpty) {
      _msg('Print ke liye attendance record nahi hai.');
      return;
    }

    setState(() => _exporting = true);
    try {
      final pw.Document document = await _buildPdf();
      await Printing.layoutPdf(
        name: 'attendance_report.pdf',
        format: PdfPageFormat.a4.landscape,
        onLayout: (_) async => document.save(),
      );
    } catch (error) {
      _msg('Print error: $error');
    }
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) {
      _msg('Export ke liye attendance record nahi hai.');
      return;
    }

    setState(() => _exporting = true);
    try {
      final pw.Document document = await _buildPdf();
      final Uint8List bytes = Uint8List.fromList(await document.save());
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'victory_attendance_report.pdf',
      );
    } catch (error) {
      _msg('PDF export error: $error');
    }
    if (mounted) setState(() => _exporting = false);
  }

  Widget _summaryCard(
    String title,
    int value, {
    required IconData icon,
    required Color background,
  }) {
    return Container(
      width: 145,
      height: 80,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 5),
              Text(title, style: const TextStyle(fontSize: 11)),
            ],
          ),
          const Spacer(),
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        initialValue: values.contains(value) ? value : values.first,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        ),
        items: values
            .map(
              (String item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item == 'ALL' ? 'All' : item),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickDate(from: true),
              icon: const Icon(Icons.calendar_month),
              label: Text('From ${_displayDate(_fromDate)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDate(from: false),
              icon: const Icon(Icons.event_available),
              label: Text('To ${_displayDate(_toDate)}'),
            ),
            _dropdown(
              label: 'Branch',
              value: _branchFilter,
              values: _branches,
              onChanged: (String? value) {
                if (value != null) setState(() => _branchFilter = value);
              },
            ),
            _dropdown(
              label: 'Status',
              value: _statusFilter,
              values: const [
                'ALL',
                'PRESENT',
                'ABSENT',
                'LATE',
                'HALF DAY',
                'PAID OFF',
              ],
              onChanged: (String? value) {
                if (value != null) setState(() => _statusFilter = value);
              },
            ),
            SizedBox(
              width: 250,
              child: TextFormField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (String value) => _searchText = value,
                onFieldSubmitted: (_) => _applyFilters(),
              ),
            ),
            FilledButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.filter_alt),
              label: const Text('Apply'),
            ),
            TextButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final String upper = status.toUpperCase();
    Color color = Colors.grey.shade200;

    if (upper == 'PRESENT') color = Colors.green.shade100;
    if (upper == 'ABSENT') color = Colors.red.shade100;
    if (upper == 'LATE') color = Colors.purple.shade100;
    if (upper == 'HALF DAY') color = Colors.orange.shade100;
    if (upper == 'PAID OFF') color = Colors.teal.shade100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          _staffName(row),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Wrap(
          spacing: 12,
          runSpacing: 5,
          children: [
            Text('Date: ${row['att_date'] ?? ''}'),
            Text('Branch: ${_branchOf(row)}'),
            Text('In: ${row['in_time'] ?? '--:--'}'),
            Text('Out: ${row['out_time'] ?? '--:--'}'),
            if ((row['remarks'] ?? '').toString().isNotEmpty)
              Text('Remarks: ${row['remarks']}'),
          ],
        ),
        trailing: SizedBox(
          width: 220,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _statusChip(_statusOf(row)),
              IconButton(
                tooltip: 'Edit',
                onPressed: () => _editAttendance(row),
                icon: const Icon(Icons.edit),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _deleteAttendance(row),
                icon: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Monitor'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAttendance,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAttendance,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _sectionTitle(
                    'Overview',
                    trailing: Wrap(
                      spacing: 7,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _exporting ? null : _printA4,
                          icon: const Icon(Icons.print),
                          label: const Text('Print A4'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _exporting ? null : _exportPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Export A4 PDF'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _summaryCard(
                        'Present',
                        _presentCount,
                        icon: Icons.check_circle,
                        background: Colors.green.shade50,
                      ),
                      _summaryCard(
                        'Absent',
                        _absentCount,
                        icon: Icons.cancel,
                        background: Colors.red.shade50,
                      ),
                      _summaryCard(
                        'Half Day',
                        _halfDayCount,
                        icon: Icons.timelapse,
                        background: Colors.orange.shade50,
                      ),
                      _summaryCard(
                        'Late',
                        _lateCount,
                        icon: Icons.schedule,
                        background: Colors.purple.shade50,
                      ),
                      _summaryCard(
                        'Paid Off',
                        _paidOffCount,
                        icon: Icons.beach_access,
                        background: Colors.teal.shade50,
                      ),
                      _summaryCard(
                        'Entries',
                        _rows.length,
                        icon: Icons.list_alt,
                        background: Colors.grey.shade200,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('Search & Filters'),
                  const SizedBox(height: 8),
                  _buildFilters(),
                  const SizedBox(height: 12),
                  _sectionTitle(
                    'Attendance Entries',
                    trailing: Text('${_rows.length} records'),
                  ),
                  const SizedBox(height: 8),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: Text('No attendance records found')),
                    )
                  else
                    ..._rows.map(_buildRow),
                ],
              ),
            ),
    );
  }
}
