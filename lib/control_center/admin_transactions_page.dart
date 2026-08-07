import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

class AdminTransactionsPage extends StatefulWidget {
  final String username;

  const AdminTransactionsPage({
    super.key,
    required this.username,
  });

  @override
  State<AdminTransactionsPage> createState() =>
      _AdminTransactionsPageState();
}

class _AdminTransactionsPageState extends State<AdminTransactionsPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _exporting = false;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  String _branchFilter = 'ALL';
  String _flowFilter = 'ALL';
  String _categoryFilter = 'ALL';
  String _paymentFilter = 'ALL';
  String _sortFilter = 'NEWEST';
  String _searchText = '';

  List<String> _branches = ['ALL'];
  List<String> _categories = ['ALL'];
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _branchSummary = [];

  double _totalIn = 0;
  double _totalOut = 0;
  double _totalExpense = 0;
  double _totalCommission = 0;
  double _totalSalaryAdvance = 0;

  double _totalSale = 0;
  double _cashSale = 0;
  double _upiSale = 0;
  double _cardSale = 0;

  bool get _isAdmin {
    final String user = widget.username.trim().toLowerCase();
    return user == 'admin' ||
        user == 'kamlesh' ||
        user == 'ks.29bishnoi@gmail.com';
  }

  double get _netCash => _totalIn - _totalOut;

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
      await _loadCategories();
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
          .from('transactions')
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

  Future<void> _loadCategories() async {
    try {
      final List<dynamic> data = await supabase
          .from('transactions')
          .select('category')
          .order('category');

      final Set<String> values = {};

      for (final dynamic item in data) {
        final Map<String, dynamic> row =
            Map<String, dynamic>.from(item as Map);
        final String category =
            (row['category'] ?? '').toString().trim();

        if (category.isNotEmpty) {
          values.add(category);
        }
      }

      _categories = ['ALL', ...values.toList()..sort()];

      if (!_categories.contains(_categoryFilter)) {
        _categoryFilter = 'ALL';
      }
    } catch (_) {
      _categories = ['ALL'];
      _categoryFilter = 'ALL';
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
      await Future.wait([
        _loadSalesSummary(),
        _loadTransactions(),
      ]);
    } catch (error) {
      _msg('Filter error: $error');
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadSalesSummary() async {
    dynamic query = supabase
        .from('tickets')
        .select('final_amount,payment_method,branch_code,ticket_date')
        .gte('ticket_date', '${_dateOnly(_fromDate)}T00:00:00')
        .lte('ticket_date', '${_dateOnly(_toDate)}T23:59:59');

    if (_branchFilter != 'ALL') {
      query = query.eq('branch_code', _branchFilter);
    }

    final List<dynamic> data = await query;

    double totalSale = 0;
    double cashSale = 0;
    double upiSale = 0;
    double cardSale = 0;

    for (final dynamic item in data) {
      final Map<String, dynamic> row =
          Map<String, dynamic>.from(item as Map);

      final double amount = _toDouble(row['final_amount']);
      final String payment =
          (row['payment_method'] ?? '').toString().trim().toUpperCase();

      totalSale += amount;

      if (payment == 'CASH') {
        cashSale += amount;
      } else if (payment == 'UPI' ||
          payment == 'UPI_CREDIT_CARD' ||
          payment == 'UPI_PPIWALLET' ||
          payment == 'UPI_LITE') {
        upiSale += amount;
      } else if (payment == 'CARD' ||
          payment == 'CREDIT CARD' ||
          payment == 'DEBIT CARD') {
        cardSale += amount;
      }
    }

    _totalSale = totalSale;
    _cashSale = cashSale;
    _upiSale = upiSale;
    _cardSale = cardSale;
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
          row['person_name'],
          row['note'],
          row['staff_name'],
          row['category'],
          row['branch_code'],
          row['created_by'],
          row['payment_method'],
          row['amount'],
        ].map((dynamic value) => (value ?? '').toString().toLowerCase()).join(' ');

        return searchable.contains(search);
      }).toList();
    }

    final List<Map<String, dynamic>> allRows = List.from(rows);

    rows = rows.where((Map<String, dynamic> row) {
      return (row['category'] ?? '').toString() != 'Commission Paid';
    }).toList();

    _sortRows(rows);

    _rows = rows;

    _totalIn = _rows
        .where(
          (Map<String, dynamic> row) =>
              (row['flow_type'] ?? '').toString().toUpperCase() == 'IN',
        )
        .fold(
          0,
          (double sum, Map<String, dynamic> row) =>
              sum + _toDouble(row['amount']),
        );

    _totalOut = _rows
        .where(
          (Map<String, dynamic> row) =>
              (row['flow_type'] ?? '').toString().toUpperCase() == 'OUT',
        )
        .fold(
          0,
          (double sum, Map<String, dynamic> row) =>
              sum + _toDouble(row['amount']),
        );

    _totalExpense = _rows
        .where((Map<String, dynamic> row) {
          final String category = (row['category'] ?? '').toString();

          return category == 'Expense' ||
              category == 'Other Cash Out' ||
              category == 'Vendor Payment' ||
              category == 'Refund';
        })
        .fold(
          0,
          (double sum, Map<String, dynamic> row) =>
              sum + _toDouble(row['amount']),
        );

    _totalCommission = allRows
        .where(
          (Map<String, dynamic> row) =>
              (row['category'] ?? '').toString() == 'Commission Paid',
        )
        .fold(
          0,
          (double sum, Map<String, dynamic> row) =>
              sum + _toDouble(row['amount']),
        );

    _totalSalaryAdvance = _rows
        .where(
          (Map<String, dynamic> row) =>
              (row['category'] ?? '').toString() == 'Salary Advance',
        )
        .fold(
          0,
          (double sum, Map<String, dynamic> row) =>
              sum + _toDouble(row['amount']),
        );

    _buildBranchSummary();
  }

  void _sortRows(List<Map<String, dynamic>> rows) {
    switch (_sortFilter) {
      case 'OLDEST':
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _parseDate(a['created_at'] ?? a['tx_date']).compareTo(
            _parseDate(b['created_at'] ?? b['tx_date']),
          ),
        );
        break;
      case 'HIGHEST':
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _toDouble(b['amount']).compareTo(_toDouble(a['amount'])),
        );
        break;
      case 'LOWEST':
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _toDouble(a['amount']).compareTo(_toDouble(b['amount'])),
        );
        break;
      case 'NEWEST':
      default:
        rows.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _parseDate(b['created_at'] ?? b['tx_date']).compareTo(
            _parseDate(a['created_at'] ?? a['tx_date']),
          ),
        );
    }
  }

  void _buildBranchSummary() {
    final Map<String, Map<String, double>> summary = {};

    for (final Map<String, dynamic> row in _rows) {
      final String branch =
          (row['branch_code'] ?? '-').toString().toUpperCase();
      final String flow =
          (row['flow_type'] ?? '').toString().toUpperCase();
      final String category = (row['category'] ?? '').toString();
      final double amount = _toDouble(row['amount']);

      summary.putIfAbsent(branch, () {
        return {
          'cash_in': 0,
          'cash_out': 0,
          'expense': 0,
          'salary_advance': 0,
        };
      });

      if (flow == 'IN') {
        summary[branch]!['cash_in'] =
            (summary[branch]!['cash_in'] ?? 0) + amount;
      } else {
        summary[branch]!['cash_out'] =
            (summary[branch]!['cash_out'] ?? 0) + amount;
      }

      if (category == 'Expense' ||
          category == 'Other Cash Out' ||
          category == 'Vendor Payment' ||
          category == 'Refund') {
        summary[branch]!['expense'] =
            (summary[branch]!['expense'] ?? 0) + amount;
      }

      if (category == 'Salary Advance') {
        summary[branch]!['salary_advance'] =
            (summary[branch]!['salary_advance'] ?? 0) + amount;
      }
    }

    _branchSummary = summary.entries.map((entry) {
      return {
        'branch': entry.key,
        'cash_in': entry.value['cash_in'] ?? 0,
        'cash_out': entry.value['cash_out'] ?? 0,
        'expense': entry.value['expense'] ?? 0,
        'salary_advance': entry.value['salary_advance'] ?? 0,
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
      _flowFilter = 'ALL';
      _categoryFilter = 'ALL';
      _paymentFilter = 'ALL';
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

  Future<void> _editTransaction(Map<String, dynamic> row) async {
    final dynamic transactionId = row['id'];

    if (transactionId == null) {
      _msg('Is entry me transaction ID nahi mili.');
      return;
    }

    DateTime selectedDate = _parseDate(row['tx_date']);

    final TextEditingController amountController = TextEditingController(
      text: _fmt(row['amount']),
    );
    final TextEditingController personController = TextEditingController(
      text: (row['person_name'] ?? '').toString(),
    );
    final TextEditingController staffController = TextEditingController(
      text: (row['staff_name'] ?? '').toString(),
    );
    final TextEditingController noteController = TextEditingController(
      text: (row['note'] ?? '').toString(),
    );

    String branch = (row['branch_code'] ?? '').toString();
    String flow = (row['flow_type'] ?? 'OUT').toString().toUpperCase();
    String category = (row['category'] ?? '').toString();
    String payment = (row['payment_method'] ?? 'Cash').toString();

    final List<String> dialogBranches = {
      ..._branches.where((String value) => value != 'ALL'),
      if (branch.isNotEmpty) branch,
    }.toList()
      ..sort();

    final List<String> dialogCategories = {
      ..._categories.where((String value) => value != 'ALL'),
      if (category.isNotEmpty) category,
    }.toList()
      ..sort();

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
              title: const Text('Edit Transaction'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final DateTime? date = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2100),
                                );

                                if (date != null) {
                                  setDialogState(() {
                                    selectedDate = date;
                                  });
                                }
                              },
                              icon: const Icon(Icons.calendar_month),
                              label: Text(_displayDate(selectedDate)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  dialogBranches.contains(branch) ? branch : null,
                              decoration: const InputDecoration(
                                labelText: 'Branch',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: dialogBranches
                                  .map(
                                    (String value) =>
                                        DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (String? value) {
                                if (value != null) {
                                  branch = value;
                                }
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
                              initialValue: flow,
                              decoration: const InputDecoration(
                                labelText: 'Flow',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'IN',
                                  child: Text('Cash In'),
                                ),
                                DropdownMenuItem(
                                  value: 'OUT',
                                  child: Text('Cash Out'),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) {
                                  flow = value;
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: dialogCategories.contains(category)
                                  ? category
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: dialogCategories
                                  .map(
                                    (String value) =>
                                        DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (String? value) {
                                if (value != null) {
                                  category = value;
                                }
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
                              initialValue: const [
                                'Cash',
                                'UPI',
                                'Card',
                                'Bank',
                              ].contains(payment)
                                  ? payment
                                  : 'Cash',
                              decoration: const InputDecoration(
                                labelText: 'Payment',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Cash',
                                  child: Text('Cash'),
                                ),
                                DropdownMenuItem(
                                  value: 'UPI',
                                  child: Text('UPI'),
                                ),
                                DropdownMenuItem(
                                  value: 'Card',
                                  child: Text('Card'),
                                ),
                                DropdownMenuItem(
                                  value: 'Bank',
                                  child: Text('Bank'),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) {
                                  payment = value;
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Amount',
                                prefixText: '₹ ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: personController,
                        decoration: const InputDecoration(
                          labelText: 'Person Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: staffController,
                        decoration: const InputDecoration(
                          labelText: 'Staff Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: noteController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Note',
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
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final double? amount =
                        double.tryParse(amountController.text.trim());

                    if (branch.trim().isEmpty) {
                      _msg('Branch select karo.');
                      return;
                    }

                    if (category.trim().isEmpty) {
                      _msg('Category select karo.');
                      return;
                    }

                    if (amount == null || amount <= 0) {
                      _msg('Sahi amount enter karo.');
                      return;
                    }

                    try {
                      await supabase.from('transactions').update({
                        'tx_date': _dateOnly(selectedDate),
                        'branch_code': branch.trim(),
                        'flow_type': flow,
                        'category': category.trim(),
                        'payment_method': payment,
                        'amount': amount,
                        'person_name': personController.text.trim(),
                        'staff_name': staffController.text.trim(),
                        'note': noteController.text.trim(),
                      }).eq('id', transactionId);

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

    amountController.dispose();
    personController.dispose();
    staffController.dispose();
    noteController.dispose();

    if (saved == true) {
      _msg('Transaction successfully update ho gaya.');
      await _applyFilters();
    }
  }

  Future<void> _deleteTransaction(Map<String, dynamic> row) async {
    final dynamic transactionId = row['id'];

    if (transactionId == null) {
      _msg('Is entry me transaction ID nahi mili.');
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Transaction?'),
          content: Text(
            '₹${_fmt(row['amount'])} ki entry permanently delete ho jayegi.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.delete),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await supabase
          .from('transactions')
          .delete()
          .eq('id', transactionId);

      _msg('Transaction delete ho gaya.');
      await _applyFilters();
    } catch (error) {
      _msg('Delete error: $error');
    }
  }

  Future<pw.Document> _buildA4Pdf() async {
    final pw.Document document = pw.Document();

    final String branchText =
        _branchFilter == 'ALL' ? 'All Branches' : _branchFilter;

    final List<List<String>> tableRows = _rows.map((row) {
      return [
        (row['tx_date'] ?? '').toString().split('T').first,
        (row['branch_code'] ?? '').toString(),
        (row['flow_type'] ?? '').toString(),
        (row['category'] ?? '').toString(),
        (row['payment_method'] ?? '').toString(),
        (row['person_name'] ?? row['staff_name'] ?? '').toString(),
        (row['note'] ?? '').toString(),
        _fmt(row['amount']),
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
                'Victory Transactions Report',
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
                _pdfSummaryBox('Cash Sale', _cashSale),
                _pdfSummaryBox('UPI Sale', _upiSale),
                _pdfSummaryBox('Card Sale', _cardSale),
                _pdfSummaryBox('Cash In', _totalIn),
                _pdfSummaryBox('Cash Out', _totalOut),
                _pdfSummaryBox('Net Cash', _netCash),
                _pdfSummaryBox('Expense', _totalExpense),
                _pdfSummaryBox('Commission', _totalCommission),
                _pdfSummaryBox('Salary Advance', _totalSalaryAdvance),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Date',
                'Branch',
                'Flow',
                'Category',
                'Payment',
                'Person/Staff',
                'Note',
                'Amount',
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
                7: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(58),
                1: const pw.FixedColumnWidth(42),
                2: const pw.FixedColumnWidth(34),
                3: const pw.FixedColumnWidth(82),
                4: const pw.FixedColumnWidth(55),
                5: const pw.FixedColumnWidth(82),
                6: const pw.FlexColumnWidth(),
                7: const pw.FixedColumnWidth(58),
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
      width: 118,
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
      _msg('Print karne ke liye koi transaction nahi hai.');
      return;
    }

    setState(() {
      _exporting = true;
    });

    try {
      final pw.Document document = await _buildA4Pdf();

      await Printing.layoutPdf(
        name:
            'transactions_${_dateOnly(_fromDate)}_${_dateOnly(_toDate)}.pdf',
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
      _msg('Export karne ke liye koi transaction nahi hai.');
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
            'victory_transactions_${_dateOnly(_fromDate)}_${_dateOnly(_toDate)}.pdf',
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

  Widget _summaryBox(
    String title,
    String value, {
    required IconData icon,
    Color? background,
    Color? iconColor,
  }) {
    return Container(
      width: 145,
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
          'Cash Sale',
          '₹${_fmt(_cashSale)}',
          icon: Icons.payments,
          background: Colors.green.shade50,
          iconColor: Colors.green.shade800,
        ),
        _summaryBox(
          'UPI Sale',
          '₹${_fmt(_upiSale)}',
          icon: Icons.qr_code_scanner,
          background: Colors.indigo.shade50,
          iconColor: Colors.indigo.shade800,
        ),
        _summaryBox(
          'Card Sale',
          '₹${_fmt(_cardSale)}',
          icon: Icons.credit_card,
          background: Colors.deepPurple.shade50,
          iconColor: Colors.deepPurple.shade800,
        ),
        _summaryBox(
          'Cash In',
          '₹${_fmt(_totalIn)}',
          icon: Icons.south_west,
          background: Colors.green.shade100,
          iconColor: Colors.green.shade900,
        ),
        _summaryBox(
          'Cash Out',
          '₹${_fmt(_totalOut)}',
          icon: Icons.north_east,
          background: Colors.orange.shade100,
          iconColor: Colors.orange.shade900,
        ),
        _summaryBox(
          'Net Cash',
          '₹${_fmt(_netCash)}',
          icon: Icons.account_balance_wallet,
          background: _netCash >= 0
              ? Colors.lightGreen.shade50
              : Colors.red.shade50,
          iconColor:
              _netCash >= 0 ? Colors.green.shade900 : Colors.red.shade900,
        ),
        _summaryBox(
          'Expense',
          '₹${_fmt(_totalExpense)}',
          icon: Icons.trending_down,
          background: Colors.red.shade50,
          iconColor: Colors.red.shade800,
        ),
        _summaryBox(
          'Commission',
          '₹${_fmt(_totalCommission)}',
          icon: Icons.handshake,
          background: Colors.purple.shade50,
          iconColor: Colors.purple.shade800,
        ),
        _summaryBox(
          'Salary Adv.',
          '₹${_fmt(_totalSalaryAdvance)}',
          icon: Icons.currency_rupee,
          background: Colors.teal.shade50,
          iconColor: Colors.teal.shade800,
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
              label: 'Flow',
              value: _flowFilter,
              values: const ['ALL', 'IN', 'OUT'],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _flowFilter = value;
                  });
                }
              },
              width: 125,
            ),
            _dropdown(
              label: 'Category',
              value: _categoryFilter,
              values: _categories,
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _categoryFilter = value;
                  });
                }
              },
              width: 175,
            ),
            _dropdown(
              label: 'Payment',
              value: _paymentFilter,
              values: const ['ALL', 'Cash', 'UPI', 'Card', 'Bank'],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _paymentFilter = value;
                  });
                }
              },
              width: 135,
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
              width: 240,
              child: TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search',
                  hintText: 'Person, note, staff, amount...',
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
              width: 280,
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
                        'IN ₹${_fmt(entry['cash_in'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'OUT ₹${_fmt(entry['cash_out'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'EXP ₹${_fmt(entry['expense'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade800,
                        ),
                      ),
                      Text(
                        'SAL ₹${_fmt(entry['salary_advance'])}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.teal.shade800,
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

  Widget _chip(
    dynamic text, {
    Color? background,
    Color? foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: background ?? Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        (text ?? '-').toString(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final bool isIn =
        (row['flow_type'] ?? '').toString().toUpperCase() == 'IN';

    final String transactionDate =
        (row['tx_date'] ?? '').toString().split('T').first;

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
              color: isIn ? Colors.green : Colors.red,
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
                          (row['branch_code'] ?? '-').toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        _chip(
                          isIn ? 'Cash In' : 'Cash Out',
                          background: isIn
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                          foreground: isIn
                              ? Colors.green.shade900
                              : Colors.orange.shade900,
                        ),
                        _chip(row['category']),
                        _chip(row['payment_method']),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₹${_fmt(row['amount'])}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isIn
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    onSelected: (String value) {
                      if (value == 'EDIT') {
                        _editTransaction(row);
                      } else if (value == 'DELETE') {
                        _deleteTransaction(row);
                      }
                    },
                    itemBuilder: (BuildContext context) => const [
                      PopupMenuItem<String>(
                        value: 'EDIT',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.edit),
                          title: Text('Edit / Modify'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'DELETE',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.delete,
                            color: Colors.red,
                          ),
                          title: Text('Delete'),
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
                    'Date: $transactionDate',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if ((row['person_name'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      'Person: ${row['person_name']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if ((row['staff_name'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      'Staff: ${row['staff_name']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if ((row['created_by'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      'By: ${row['created_by']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
              ),
              if ((row['note'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  row['note'].toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _editTransaction(row);
                    },
                    icon: const Icon(Icons.edit, size: 17),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () {
                      _deleteTransaction(row);
                    },
                    icon: const Icon(Icons.delete_outline, size: 17),
                    label: const Text('Delete'),
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
          label: Text(_exporting ? 'Preparing...' : 'Export A4 PDF'),
        ),
      ],
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
                    'Transaction Entries',
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
                      child: const Text('No transactions found'),
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
