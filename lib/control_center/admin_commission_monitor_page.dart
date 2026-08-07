import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _exporting = false;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  String _branchFilter = 'ALL';
  String _statusFilter = 'ALL';
  String _sortFilter = 'NEWEST';
  String _searchText = '';

  List<String> _branches = ['ALL'];
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _branchSummary = [];

  double _totalSale = 0;
  double _totalCommission = 0;
  double _paidCommission = 0;
  double _pendingCommission = 0;

  bool get _isAdmin {
    final String user = widget.username.trim().toLowerCase();
    return user == 'admin' ||
        user == 'kamlesh' ||
        user == 'ks.29bishnoi@gmail.com';
  }

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

  String _dateOnly(DateTime date) {
    return date.toIso8601String().split('T').first;
  }

  String _displayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
  }

  DateTime _parseDate(dynamic value) {
    return DateTime.tryParse((value ?? '').toString()) ?? DateTime.now();
  }

  Future<void> _loadAll() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      await _loadBranches();
      await _applyFilters(showLoader: false);
    } catch (error) {
      _msg('Load error: $error');
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadBranches() async {
    try {
      final List<dynamic> data = await supabase
          .from('tickets')
          .select('branch_code')
          .order('branch_code');

      final Set<String> values = {};

      for (final dynamic item in data) {
        final Map<String, dynamic> row =
            Map<String, dynamic>.from(item as Map);

        final String branch =
            (row['branch_code'] ?? '').toString().trim().toUpperCase();

        if (branch.isNotEmpty) {
          values.add(branch);
        }
      }

      _branches = ['ALL', ...values.toList()..sort()];

      if (!_branches.contains(_branchFilter)) {
        _branchFilter = 'ALL';
      }
    } catch (_) {
      _branches = ['ALL'];
      _branchFilter = 'ALL';
    }
  }

  Future<void> _applyFilters({bool showLoader = true}) async {
    if (_fromDate.isAfter(_toDate)) {
      _msg('From Date, To Date se baad ki nahi ho sakti.');
      return;
    }

    if (showLoader && mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      await _loadRows();
    } catch (error) {
      _msg('Filter error: $error');
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadRows() async {
    dynamic query = supabase
        .from('tickets')
        .select(
          'id, ticket_no, branch_code, final_amount, ticket_date, created_at, '
          'agent_id, commission_percent, commission_amount, '
          'commission_paid, commission_paid_at',
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

    final List<dynamic> data =
        await query.order('created_at', ascending: false);

    List<Map<String, dynamic>> rows = data
        .map(
          (dynamic item) =>
              Map<String, dynamic>.from(item as Map),
        )
        .toList();

    if (_searchText.trim().isNotEmpty) {
      final String search = _searchText.trim().toLowerCase();

      rows = rows.where((Map<String, dynamic> row) {
        final String searchable = [
          row['ticket_no'],
          row['branch_code'],
          row['agent_id'],
          row['final_amount'],
          row['commission_amount'],
          row['commission_percent'],
        ].map((dynamic value) => (value ?? '').toString().toLowerCase()).join(' ');

        return searchable.contains(search);
      }).toList();
    }

    _sortRows(rows);

    _rows = rows;

    _totalSale = _rows.fold(
      0,
      (double sum, Map<String, dynamic> row) =>
          sum + _toDouble(row['final_amount']),
    );

    _totalCommission = _rows.fold(
      0,
      (double sum, Map<String, dynamic> row) =>
          sum + _toDouble(row['commission_amount']),
    );

    _paidCommission = _rows
        .where(
          (Map<String, dynamic> row) =>
              (row['commission_paid'] ?? false) == true,
        )
        .fold(
          0,
          (double sum, Map<String, dynamic> row) =>
              sum + _toDouble(row['commission_amount']),
        );

    _pendingCommission = _rows
        .where(
          (Map<String, dynamic> row) =>
              (row['commission_paid'] ?? false) != true,
        )
        .fold(
          0,
          (double sum, Map<String, dynamic> row) =>
              sum + _toDouble(row['commission_amount']),
        );

    _buildBranchSummary();
  }

  void _sortRows(List<Map<String, dynamic>> rows) {
    switch (_sortFilter) {
      case 'OLDEST':
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _parseDate(a['created_at'] ?? a['ticket_date']).compareTo(
            _parseDate(b['created_at'] ?? b['ticket_date']),
          ),
        );
        break;
      case 'HIGHEST':
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _toDouble(b['commission_amount']).compareTo(
            _toDouble(a['commission_amount']),
          ),
        );
        break;
      case 'LOWEST':
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _toDouble(a['commission_amount']).compareTo(
            _toDouble(b['commission_amount']),
          ),
        );
        break;
      case 'NEWEST':
      default:
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _parseDate(b['created_at'] ?? b['ticket_date']).compareTo(
            _parseDate(a['created_at'] ?? a['ticket_date']),
          ),
        );
    }
  }

  void _buildBranchSummary() {
    final Map<String, Map<String, double>> summary = {};

    for (final Map<String, dynamic> row in _rows) {
      final String branch =
          (row['branch_code'] ?? '-').toString().toUpperCase();
      final double sale = _toDouble(row['final_amount']);
      final double commission = _toDouble(row['commission_amount']);
      final bool paid = (row['commission_paid'] ?? false) == true;

      summary.putIfAbsent(branch, () {
        return {
          'sale': 0,
          'commission': 0,
          'paid': 0,
          'pending': 0,
        };
      });

      summary[branch]!['sale'] =
          (summary[branch]!['sale'] ?? 0) + sale;

      summary[branch]!['commission'] =
          (summary[branch]!['commission'] ?? 0) + commission;

      if (paid) {
        summary[branch]!['paid'] =
            (summary[branch]!['paid'] ?? 0) + commission;
      } else {
        summary[branch]!['pending'] =
            (summary[branch]!['pending'] ?? 0) + commission;
      }
    }

    _branchSummary = summary.entries.map((entry) {
      return {
        'branch': entry.key,
        'sale': entry.value['sale'] ?? 0,
        'commission': entry.value['commission'] ?? 0,
        'paid': entry.value['paid'] ?? 0,
        'pending': entry.value['pending'] ?? 0,
      };
    }).toList()
      ..sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            a['branch'].toString().compareTo(b['branch'].toString()),
      );
  }

  Future<void> _pickFromDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _fromDate = date;
      });
    }
  }

  Future<void> _pickToDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _toDate = date;
      });
    }
  }

  Future<void> _resetFilters() async {
    setState(() {
      _fromDate = DateTime.now();
      _toDate = DateTime.now();
      _branchFilter = 'ALL';
      _statusFilter = 'ALL';
      _sortFilter = 'NEWEST';
      _searchText = '';
      _searchController.clear();
    });

    await _applyFilters();
  }

  void _msg(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> _editCommission(Map<String, dynamic> row) async {
    final dynamic ticketId = row['id'];

    if (ticketId == null) {
      _msg('Ticket ID nahi mili.');
      return;
    }

    final TextEditingController percentController =
        TextEditingController(
      text: _fmt(row['commission_percent']),
    );

    final TextEditingController amountController =
        TextEditingController(
      text: _fmt(row['commission_amount']),
    );

    bool paid = (row['commission_paid'] ?? false) == true;

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(void Function()) setDialogState,
          ) {
            return AlertDialog(
              title: const Text('Edit Commission'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ticket: ${(row['ticket_no'] ?? '-')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: percentController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Commission Percent',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Commission Amount',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Commission Paid'),
                      subtitle: Text(
                        paid ? 'Status: PAID' : 'Status: PENDING',
                      ),
                      value: paid,
                      onChanged: (bool value) {
                        setDialogState(() {
                          paid = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final double? percent =
                        double.tryParse(percentController.text.trim());

                    final double? amount =
                        double.tryParse(amountController.text.trim());

                    if (percent == null || percent < 0) {
                      _msg('Sahi commission percent enter karo.');
                      return;
                    }

                    if (amount == null || amount < 0) {
                      _msg('Sahi commission amount enter karo.');
                      return;
                    }

                    try {
                      await supabase.from('tickets').update({
                        'commission_percent': percent,
                        'commission_amount': amount,
                        'commission_paid': paid,
                        'commission_paid_at':
                            paid ? DateTime.now().toIso8601String() : null,
                      }).eq('id', ticketId);

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (error) {
                      _msg('Update error: $error');
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

    percentController.dispose();
    amountController.dispose();

    if (saved == true) {
      _msg('Commission successfully update ho gaya.');
      await _applyFilters();
    }
  }

  Future<void> _changePaidStatus(
    Map<String, dynamic> row,
    bool paid,
  ) async {
    final dynamic ticketId = row['id'];

    if (ticketId == null) {
      _msg('Ticket ID nahi mili.');
      return;
    }

    try {
      await supabase.from('tickets').update({
        'commission_paid': paid,
        'commission_paid_at':
            paid ? DateTime.now().toIso8601String() : null,
      }).eq('id', ticketId);

      _msg(
        paid
            ? 'Commission PAID mark ho gaya.'
            : 'Commission PENDING mark ho gaya.',
      );

      await _applyFilters();
    } catch (error) {
      _msg('Status update error: $error');
    }
  }

  Future<pw.Document> _buildA4Pdf() async {
    final pw.Document document = pw.Document();

    final String branchText =
        _branchFilter == 'ALL' ? 'All Branches' : _branchFilter;

    final List<List<String>> tableRows = _rows.map((row) {
      final bool paid = (row['commission_paid'] ?? false) == true;

      return [
        (row['ticket_date'] ?? '').toString().split('T').first,
        (row['branch_code'] ?? '').toString(),
        (row['ticket_no'] ?? '').toString(),
        (row['agent_id'] ?? '').toString(),
        _fmt(row['final_amount']),
        _fmt(row['commission_percent']),
        _fmt(row['commission_amount']),
        paid ? 'PAID' : 'PENDING',
        (row['commission_paid_at'] ?? '').toString(),
      ];
    }).toList();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Victory Commission Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$branchText | ${_displayDate(_fromDate)} to ${_displayDate(_toDate)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text(
                'Generated by: ${widget.username}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          );
        },
        build: (pw.Context context) {
          return [
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pdfSummaryBox('Total Sale', _totalSale),
                _pdfSummaryBox(
                  'Total Commission',
                  _totalCommission,
                ),
                _pdfSummaryBox(
                  'Paid Commission',
                  _paidCommission,
                ),
                _pdfSummaryBox(
                  'Pending Commission',
                  _pendingCommission,
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Date',
                'Branch',
                'Ticket No.',
                'Agent',
                'Sale',
                'Comm. %',
                'Commission',
                'Status',
                'Paid At',
              ],
              data: tableRows,
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignments: {
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
              border: pw.TableBorder.all(
                color: PdfColors.grey500,
                width: 0.4,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total Entries: ${_rows.length}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return document;
  }

  pw.Widget _pdfSummaryBox(String title, double amount) {
    return pw.Container(
      width: 145,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey500,
          width: 0.5,
        ),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'INR ${_fmt(amount)}',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printA4() async {
    if (_rows.isEmpty) {
      _msg('Print karne ke liye koi commission record nahi hai.');
      return;
    }

    setState(() {
      _exporting = true;
    });

    try {
      final pw.Document document = await _buildA4Pdf();

      await Printing.layoutPdf(
        name:
            'commission_${_dateOnly(_fromDate)}_${_dateOnly(_toDate)}.pdf',
        format: PdfPageFormat.a4.landscape,
        onLayout: (PdfPageFormat format) async => document.save(),
      );
    } catch (error) {
      _msg('Print error: $error');
    }

    if (mounted) {
      setState(() {
        _exporting = false;
      });
    }
  }

  Future<void> _exportA4Pdf() async {
    if (_rows.isEmpty) {
      _msg('Export karne ke liye koi commission record nahi hai.');
      return;
    }

    setState(() {
      _exporting = true;
    });

    try {
      final pw.Document document = await _buildA4Pdf();
      final Uint8List bytes =
          Uint8List.fromList(await document.save());

      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'victory_commission_${_dateOnly(_fromDate)}_${_dateOnly(_toDate)}.pdf',
      );
    } catch (error) {
      _msg('PDF export error: $error');
    }

    if (mounted) {
      setState(() {
        _exporting = false;
      });
    }
  }

  Widget _summaryBox(
    String title,
    String value, {
    required IconData icon,
    Color? background,
    Color? iconColor,
  }) {
    return Container(
      width: 150,
      height: 82,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: background ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: iconColor ?? Colors.black87,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
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
        _summaryBox(
          'Total Sale',
          '₹${_fmt(_totalSale)}',
          icon: Icons.bar_chart,
          background: Colors.blue.shade50,
          iconColor: Colors.blue.shade800,
        ),
        _summaryBox(
          'Total Commission',
          '₹${_fmt(_totalCommission)}',
          icon: Icons.handshake,
          background: Colors.purple.shade50,
          iconColor: Colors.purple.shade800,
        ),
        _summaryBox(
          'Paid Commission',
          '₹${_fmt(_paidCommission)}',
          icon: Icons.check_circle,
          background: Colors.green.shade50,
          iconColor: Colors.green.shade800,
        ),
        _summaryBox(
          'Pending Commission',
          '₹${_fmt(_pendingCommission)}',
          icon: Icons.pending_actions,
          background: Colors.orange.shade50,
          iconColor: Colors.orange.shade900,
        ),
        _summaryBox(
          'Entries',
          '${_rows.length}',
          icon: Icons.format_list_numbered,
          background: Colors.grey.shade200,
          iconColor: Colors.blueGrey.shade800,
        ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
    double width = 145,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: values.contains(value) ? value : values.first,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 11,
          ),
        ),
        items: values
            .map(
              (String item) => DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item == 'ALL' ? 'All' : item,
                  overflow: TextOverflow.ellipsis,
                ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pickFromDate,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text('From ${_displayDate(_fromDate)}'),
            ),
            OutlinedButton.icon(
              onPressed: _pickToDate,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text('To ${_displayDate(_toDate)}'),
            ),
            _dropdown(
              label: 'Branch',
              value: _branchFilter,
              values: _branches,
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _branchFilter = value;
                  });
                }
              },
            ),
            _dropdown(
              label: 'Status',
              value: _statusFilter,
              values: const ['ALL', 'PAID', 'PENDING'],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _statusFilter = value;
                  });
                }
              },
              width: 140,
            ),
            _dropdown(
              label: 'Sort',
              value: _sortFilter,
              values: const ['NEWEST', 'OLDEST', 'HIGHEST', 'LOWEST'],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _sortFilter = value;
                  });
                }
              },
              width: 145,
            ),
            SizedBox(
              width: 250,
              child: TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search',
                  hintText: 'Ticket, branch, agent, amount...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchText = '';
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (String value) {
                  setState(() {
                    _searchText = value;
                  });
                },
                onFieldSubmitted: (_) {
                  _applyFilters();
                },
              ),
            ),
            FilledButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.filter_alt, size: 18),
              label: const Text('Apply'),
            ),
            TextButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh, size: 18),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _branchSummary.map((Map<String, dynamic> entry) {
            return Container(
              width: 300,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry['branch'].toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    children: [
                      Text(
                        'Sale ₹${_fmt(entry['sale'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Comm ₹${_fmt(entry['commission'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.purple.shade800,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Paid ₹${_fmt(entry['paid'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade800,
                        ),
                      ),
                      Text(
                        'Pending ₹${_fmt(entry['pending'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _statusChip(bool paid) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: paid
            ? Colors.green.shade100
            : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        paid ? 'PAID' : 'PENDING',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: paid
              ? Colors.green.shade800
              : Colors.orange.shade900,
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final bool paid = (row['commission_paid'] ?? false) == true;

    final String ticketNo =
        (row['ticket_no'] ?? '-').toString();

    final String branch =
        (row['branch_code'] ?? '-').toString();

    final String ticketDate =
        (row['ticket_date'] ?? '').toString().split('T').first;

    final String paidAt =
        (row['commission_paid_at'] ?? '').toString();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border(
            left: BorderSide(
              color: paid ? Colors.green : Colors.orange,
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          branch,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        _statusChip(paid),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            'Ticket $ticketNo',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        if ((row['agent_id'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              'Agent ${row['agent_id']}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₹${_fmt(row['commission_amount'])}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: paid
                          ? Colors.green.shade800
                          : Colors.orange.shade900,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    onSelected: (String value) {
                      if (value == 'EDIT') {
                        _editCommission(row);
                      } else if (value == 'PAID') {
                        _changePaidStatus(row, true);
                      } else if (value == 'PENDING') {
                        _changePaidStatus(row, false);
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      const PopupMenuItem<String>(
                        value: 'EDIT',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.edit),
                          title: Text('Edit / Modify'),
                        ),
                      ),
                      if (!paid)
                        const PopupMenuItem<String>(
                          value: 'PAID',
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                            title: Text('Mark as Paid'),
                          ),
                        ),
                      if (paid)
                        const PopupMenuItem<String>(
                          value: 'PENDING',
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.pending_actions,
                              color: Colors.orange,
                            ),
                            title: Text('Mark as Pending'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 16,
                runSpacing: 5,
                children: [
                  Text(
                    'Sale: ₹${_fmt(row['final_amount'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Percent: ${_fmt(row['commission_percent'])}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Date: $ticketDate',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              if (paidAt.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  'Paid At: $paidAt',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _editCommission(row);
                    },
                    icon: const Icon(Icons.edit, size: 17),
                    label: const Text('Edit'),
                  ),
                  if (!paid)
                    FilledButton.tonalIcon(
                      onPressed: () {
                        _changePaidStatus(row, true);
                      },
                      icon: const Icon(
                        Icons.check_circle,
                        size: 17,
                      ),
                      label: const Text('Mark Paid'),
                    )
                  else
                    TextButton.icon(
                      onPressed: () {
                        _changePaidStatus(row, false);
                      },
                      icon: const Icon(
                        Icons.pending_actions,
                        size: 17,
                      ),
                      label: const Text('Mark Pending'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exportButtons() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        OutlinedButton.icon(
          onPressed: _exporting ? null : _printA4,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('Print A4'),
        ),
        FilledButton.tonalIcon(
          onPressed: _exporting ? null : _exportA4Pdf,
          icon: const Icon(Icons.picture_as_pdf, size: 18),
          label: Text(
            _exporting ? 'Preparing...' : 'Export A4 PDF',
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
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
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _sectionTitle(
                    'Overview',
                    trailing: _exportButtons(),
                  ),
                  const SizedBox(height: 8),
                  _buildSummary(),
                  const SizedBox(height: 12),
                  _sectionTitle('Search & Filters'),
                  const SizedBox(height: 8),
                  _buildFilters(),
                  const SizedBox(height: 12),
                  if (_branchSummary.isNotEmpty) ...[
                    _sectionTitle('Branch Summary'),
                    const SizedBox(height: 8),
                    _buildBranchSummaryTable(),
                    const SizedBox(height: 12),
                  ],
                  _sectionTitle(
                    'Commission Entries',
                    trailing: Text(
                      '${_rows.length} records',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_rows.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 50,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'No commission records found',
                      ),
                    )
                  else
                    ..._rows.map(_buildRow),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
