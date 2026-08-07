import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminStaffPage extends StatefulWidget {
  const AdminStaffPage({super.key});

  @override
  State<AdminStaffPage> createState() => _AdminStaffPageState();
}

class _AdminStaffPageState extends State<AdminStaffPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _exporting = false;

  String _branchFilter = 'ALL';
  String _searchText = '';

  List<Map<String, dynamic>> _allRows = [];
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _branches = [];

  double _totalSalary = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _fmt(dynamic value) => _toDouble(value).toStringAsFixed(2);

  String _name(Map<String, dynamic> row) =>
      (row['name'] ?? row['staff_name'] ?? '').toString();

  String _branchCode(Map<String, dynamic> row) {
    final String branchId = (row['branch_id'] ?? '').toString();
    final Map<String, dynamic>? branch = _branches.cast<Map<String, dynamic>?>().firstWhere(
      (Map<String, dynamic>? item) => (item?['id'] ?? '').toString() == branchId,
      orElse: () => null,
    );
    return (branch?['code'] ?? '-').toString();
  }

  void _msg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);

    try {
      final List<dynamic> branchesData = await supabase
          .from('branches')
          .select('id, code, name')
          .order('code');

      _branches = branchesData
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final List<dynamic> staffData =
          await supabase.from('staff').select().order('name');

      _allRows = staffData
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList();

      _applyFilters(showRefresh: false);
    } catch (error) {
      _msg('Staff load error: $error');
    }

    if (mounted) setState(() => _loading = false);
  }

  void _applyFilters({bool showRefresh = true}) {
    final String search = _searchText.trim().toLowerCase();

    _rows = _allRows.where((Map<String, dynamic> row) {
      final String code = _branchCode(row);
      final bool branchMatch =
          _branchFilter == 'ALL' || code == _branchFilter;

      final String searchable = [
        _name(row),
        row['mobile'],
        row['role'],
        row['salary'],
        code,
      ].map((dynamic value) => (value ?? '').toString().toLowerCase()).join(' ');

      return branchMatch &&
          (search.isEmpty || searchable.contains(search));
    }).toList();

    _totalSalary = _rows.fold(
      0,
      (double sum, Map<String, dynamic> row) =>
          sum + _toDouble(row['salary']),
    );

    if (showRefresh && mounted) setState(() {});
  }

  Future<void> _resetFilters() async {
    setState(() {
      _branchFilter = 'ALL';
      _searchText = '';
      _searchController.clear();
    });
    _applyFilters();
  }

  Future<void> _editStaff(Map<String, dynamic> row) async {
    final dynamic id = row['id'];
    if (id == null) return;

    final TextEditingController nameController =
        TextEditingController(text: _name(row));
    final TextEditingController mobileController =
        TextEditingController(text: (row['mobile'] ?? '').toString());
    final TextEditingController roleController =
        TextEditingController(text: (row['role'] ?? '').toString());
    final TextEditingController salaryController =
        TextEditingController(text: _fmt(row['salary']));

    String branchId = (row['branch_id'] ?? '').toString();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setD) {
            return AlertDialog(
              title: const Text('Edit Staff'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: mobileController,
                        decoration: const InputDecoration(
                          labelText: 'Mobile',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: roleController,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: salaryController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Salary',
                          prefixText: '₹ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _branches.any(
                          (Map<String, dynamic> b) =>
                              (b['id'] ?? '').toString() == branchId,
                        )
                            ? branchId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Branch',
                          border: OutlineInputBorder(),
                        ),
                        items: _branches
                            .map(
                              (Map<String, dynamic> branch) =>
                                  DropdownMenuItem<String>(
                                value: (branch['id'] ?? '').toString(),
                                child: Text(
                                  '${branch['code']} - ${branch['name']}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (String? value) {
                          if (value != null) branchId = value;
                        },
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
                    final String name = nameController.text.trim();
                    final double? salary =
                        double.tryParse(salaryController.text.trim());

                    if (name.isEmpty || salary == null || salary < 0) {
                      _msg('Name aur salary sahi enter karo.');
                      return;
                    }

                    try {
                      await supabase.from('staff').update({
                        'name': name,
                        'staff_name': name,
                        'mobile': mobileController.text.trim(),
                        'role': roleController.text.trim(),
                        'salary': salary,
                        'branch_id': branchId,
                      }).eq('id', id);

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (error) {
                      _msg('Staff update error: $error');
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    mobileController.dispose();
    roleController.dispose();
    salaryController.dispose();

    if (saved == true) {
      _msg('Staff update ho gaya.');
      await _loadAll();
    }
  }

  Future<void> _deleteStaff(Map<String, dynamic> row) async {
    final dynamic id = row['id'];
    if (id == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete Staff?'),
        content: Text('${_name(row)} delete ho jayega.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('staff').delete().eq('id', id);
      await _loadAll();
      _msg('Staff delete ho gaya.');
    } catch (error) {
      _msg('Delete error: $error');
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
              'Victory Staff Report',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Name',
                'Branch',
                'Mobile',
                'Role',
                'Salary',
              ],
              data: _rows
                  .map(
                    (Map<String, dynamic> row) => [
                      _name(row),
                      _branchCode(row),
                      (row['mobile'] ?? '').toString(),
                      (row['role'] ?? '').toString(),
                      _fmt(row['salary']),
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
        filename: 'victory_staff_report.pdf',
      );
    } catch (error) {
      _msg('PDF error: $error');
    }
    if (mounted) setState(() => _exporting = false);
  }

  Widget _buildRow(Map<String, dynamic> row) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            _name(row).isEmpty
                ? '?'
                : _name(row).substring(0, 1).toUpperCase(),
          ),
        ),
        title: Text(
          _name(row),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_branchCode(row)} • ${row['role'] ?? '-'} • ${row['mobile'] ?? '-'}',
        ),
        trailing: SizedBox(
          width: 190,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '₹${_fmt(row['salary'])}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              IconButton(
                onPressed: () => _editStaff(row),
                icon: const Icon(Icons.edit),
              ),
              IconButton(
                onPressed: () => _deleteStaff(row),
                icon: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> branchCodes = [
      'ALL',
      ..._branches.map((Map<String, dynamic> b) => (b['code'] ?? '').toString()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Monitor'),
        actions: [
          IconButton(
            onPressed: _loadAll,
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
                    _infoBox('Staff', '${_rows.length}', Colors.blue.shade50),
                    _infoBox(
                      'Salary Total',
                      '₹${_fmt(_totalSalary)}',
                      Colors.purple.shade50,
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
                          width: 150,
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
                            onChanged: (String? value) {
                              if (value != null) {
                                setState(() => _branchFilter = value);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'Search',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (String value) => _searchText = value,
                            onSubmitted: (_) => _applyFilters(),
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
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('No staff found')),
                  )
                else
                  ..._rows.map(_buildRow),
              ],
            ),
    );
  }

  Widget _infoBox(String title, String value, Color color) {
    return Container(
      width: 160,
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
}
