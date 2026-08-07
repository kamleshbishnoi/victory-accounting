import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminGstReportPage extends StatefulWidget {
  const AdminGstReportPage({super.key});

  @override
  State<AdminGstReportPage> createState() => _AdminGstReportPageState();
}

class _AdminGstReportPageState extends State<AdminGstReportPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _selectedBranch = 'ALL';
  String _selectedItem = 'ALL';
  String _selectedPayment = 'ALL';
  String _searchText = '';

  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _itemRows = [];
  List<Map<String, dynamic>> _summaryRows = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
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

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;

  String _displayDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String _money(dynamic value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(_toDouble(value));

  String _number(dynamic value) {
    final double number = _toDouble(value);
    return number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(2);
  }

  String _paymentText(Map<String, dynamic> ticket) {
    final String method =
        (ticket['payment_method'] ?? ticket['payment_mode'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
    return method.isEmpty ? '-' : method;
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _loadReport() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final List<dynamic> response = await supabase
          .from('tickets')
          .select('''
            id,
            ticket_no,
            ticket_date,
            created_at,
            branch_code,
            payment_method,
            payment_mode,
            subtotal,
            discount_amount,
            discount,
            final_amount,
            ticket_items(
              id,
              qty,
              item_name_snapshot,
              unit_price_snapshot,
              line_total,
              gst_percent_snapshot,
              hsn_sac_snapshot,
              gst_inclusive_snapshot,
              taxable_amount_snapshot,
              gst_amount_snapshot,
              cgst_amount_snapshot,
              sgst_amount_snapshot
            )
          ''')
          .gte('ticket_date', '${_dateOnly(_fromDate)}T00:00:00')
          .lte('ticket_date', '${_dateOnly(_toDate)}T23:59:59')
          .order('created_at', ascending: false)
          .limit(5000);

      _tickets = response
          .map((dynamic value) => Map<String, dynamic>.from(value as Map))
          .toList();

      _buildRows();
    } catch (error) {
      _error = error.toString();
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _buildRows() {
    final List<Map<String, dynamic>> rows = [];

    for (final Map<String, dynamic> ticket in _tickets) {
      final String branch =
          (ticket['branch_code'] ?? '-').toString().trim().toUpperCase();
      final String payment = _paymentText(ticket);
      final String ticketNo = (ticket['ticket_no'] ?? '-').toString();
      final String ticketDate =
          (ticket['ticket_date'] ?? ticket['created_at'] ?? '')
              .toString()
              .split('T')
              .first;

      final double subtotal = _toDouble(ticket['subtotal']);
      final double discount = _toDouble(ticket['discount_amount']) != 0
          ? _toDouble(ticket['discount_amount'])
          : _toDouble(ticket['discount']);
      final double discountRatio = subtotal > 0 ? discount / subtotal : 0;

      final dynamic rawItems = ticket['ticket_items'];
      if (rawItems is! List) continue;

      for (final dynamic rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final Map<String, dynamic> item = Map<String, dynamic>.from(rawItem);

        final String itemName =
            (item['item_name_snapshot'] ?? 'Item').toString().trim();
        final int qty = _toInt(item['qty']);
        final double rate = _toDouble(item['unit_price_snapshot']);
        final double gross = _toDouble(item['line_total']);
        final double allocatedDiscount = gross * discountRatio;
        final double discountedTotal = gross - allocatedDiscount;
        final double gstPercent = _toDouble(item['gst_percent_snapshot']);
        final bool inclusive = item['gst_inclusive_snapshot'] != false;

        double taxable = _toDouble(item['taxable_amount_snapshot']);
        double gstAmount = _toDouble(item['gst_amount_snapshot']);
        double cgst = _toDouble(item['cgst_amount_snapshot']);
        double sgst = _toDouble(item['sgst_amount_snapshot']);

        if (gstPercent > 0) {
          if (inclusive) {
            taxable = discountedTotal / (1 + gstPercent / 100);
            gstAmount = discountedTotal - taxable;
          } else {
            taxable = discountedTotal;
            gstAmount = taxable * gstPercent / 100;
          }
          cgst = gstAmount / 2;
          sgst = gstAmount / 2;
        } else {
          taxable = discountedTotal;
          gstAmount = 0;
          cgst = 0;
          sgst = 0;
        }

        rows.add({
          'ticket_no': ticketNo,
          'ticket_date': ticketDate,
          'branch': branch,
          'payment': payment,
          'item_name': itemName,
          'hsn_sac': (item['hsn_sac_snapshot'] ?? '').toString(),
          'gst_percent': gstPercent,
          'qty': qty,
          'rate': rate,
          'gross': gross,
          'discount': allocatedDiscount,
          'taxable': taxable,
          'cgst': cgst,
          'sgst': sgst,
          'gst_amount': gstAmount,
          'final_amount': inclusive ? discountedTotal : discountedTotal + gstAmount,
        });
      }
    }

    final String search = _searchText.trim().toLowerCase();

    _itemRows = rows.where((Map<String, dynamic> row) {
      final bool branchOk = _selectedBranch == 'ALL' ||
          row['branch'].toString() == _selectedBranch;
      final bool itemOk = _selectedItem == 'ALL' ||
          row['item_name'].toString() == _selectedItem;
      final bool paymentOk = _selectedPayment == 'ALL' ||
          row['payment'].toString() == _selectedPayment;
      final bool searchOk = search.isEmpty ||
          [
            row['ticket_no'],
            row['item_name'],
            row['branch'],
            row['hsn_sac'],
          ].map((dynamic value) => value.toString().toLowerCase()).join(' ').contains(search);
      return branchOk && itemOk && paymentOk && searchOk;
    }).toList();

    final Map<String, Map<String, dynamic>> grouped = {};

    for (final Map<String, dynamic> row in _itemRows) {
      final String key = '${row['item_name']}|${row['hsn_sac']}|${row['gst_percent']}';
      grouped.putIfAbsent(key, () {
        return {
          'item_name': row['item_name'],
          'hsn_sac': row['hsn_sac'],
          'gst_percent': row['gst_percent'],
          'qty': 0,
          'gross': 0.0,
          'discount': 0.0,
          'taxable': 0.0,
          'cgst': 0.0,
          'sgst': 0.0,
          'gst_amount': 0.0,
          'final_amount': 0.0,
        };
      });

      final Map<String, dynamic> target = grouped[key]!;
      target['qty'] = _toInt(target['qty']) + _toInt(row['qty']);
      for (final String field in [
        'gross',
        'discount',
        'taxable',
        'cgst',
        'sgst',
        'gst_amount',
        'final_amount',
      ]) {
        target[field] = _toDouble(target[field]) + _toDouble(row[field]);
      }
    }

    _summaryRows = grouped.values.toList()
      ..sort((a, b) => a['item_name'].toString().compareTo(b['item_name'].toString()));
  }

  List<String> get _branches {
    final List<String> values = _tickets
        .map((ticket) => (ticket['branch_code'] ?? '').toString().trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['ALL', ...values];
  }

  List<String> get _items {
    final Set<String> values = {};
    for (final Map<String, dynamic> ticket in _tickets) {
      final dynamic rawItems = ticket['ticket_items'];
      if (rawItems is List) {
        for (final dynamic raw in rawItems) {
          if (raw is Map) {
            final String name = (raw['item_name_snapshot'] ?? '').toString().trim();
            if (name.isNotEmpty) values.add(name);
          }
        }
      }
    }
    final List<String> list = values.toList()..sort();
    return ['ALL', ...list];
  }

  List<String> get _payments {
    final List<String> values = _tickets
        .map(_paymentText)
        .where((value) => value != '-')
        .toSet()
        .toList()
      ..sort();
    return ['ALL', ...values];
  }

  int get _totalTickets => _itemRows.map((row) => row['ticket_no']).toSet().length;
  int get _totalQty => _itemRows.fold(0, (sum, row) => sum + _toInt(row['qty']));
  double _sum(String field) => _itemRows.fold(0, (sum, row) => sum + _toDouble(row[field]));

  Future<void> _pickDate({required bool from}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: from ? _fromDate : _toDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _fromDate = picked;
        if (_fromDate.isAfter(_toDate)) _toDate = picked;
      } else {
        _toDate = picked;
        if (_toDate.isBefore(_fromDate)) _fromDate = picked;
      }
    });
  }

  Future<Uint8List> _buildPdf() async {
    final pw.Document document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('GST Item Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('${_displayDate(_fromDate)} to ${_displayDate(_toDate)} | Branch: $_selectedBranch | Payment: $_selectedPayment', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (_) => [
          pw.Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pdfBox('Tickets', '$_totalTickets'),
              _pdfBox('Qty', '$_totalQty'),
              _pdfBox('Gross', 'Rs. ${_number(_sum('gross'))}'),
              _pdfBox('Discount', 'Rs. ${_number(_sum('discount'))}'),
              _pdfBox('Taxable', 'Rs. ${_number(_sum('taxable'))}'),
              _pdfBox('CGST', 'Rs. ${_number(_sum('cgst'))}'),
              _pdfBox('SGST', 'Rs. ${_number(_sum('sgst'))}'),
              _pdfBox('GST', 'Rs. ${_number(_sum('gst_amount'))}'),
              _pdfBox('Final', 'Rs. ${_number(_sum('final_amount'))}'),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'HSN/SAC', 'GST %', 'Qty', 'Gross', 'Discount', 'Taxable', 'CGST', 'SGST', 'GST', 'Final'],
            data: _summaryRows.map((row) => [
              row['item_name'].toString(),
              row['hsn_sac'].toString(),
              _number(row['gst_percent']),
              row['qty'].toString(),
              _number(row['gross']),
              _number(row['discount']),
              _number(row['taxable']),
              _number(row['cgst']),
              _number(row['sgst']),
              _number(row['gst_amount']),
              _number(row['final_amount']),
            ]).toList(),
            headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _pdfBox(String title, String value) => pw.Container(
        width: 88,
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 7)),
            pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  Future<void> _exportPdf() async {
    if (_summaryRows.isEmpty) {
      _message('Export ke liye data nahi hai.', error: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final Uint8List bytes = await _buildPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'gst_item_report_${_dateOnly(_fromDate)}_${_dateOnly(_toDate)}.pdf',
      );
    } catch (error) {
      _message('PDF export error: $error', error: true);
    }
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _printPdf() async {
    if (_summaryRows.isEmpty) {
      _message('Print ke liye data nahi hai.', error: true);
      return;
    }
    final Uint8List bytes = await _buildPdf();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _exportExcel() async {
    if (_summaryRows.isEmpty) {
      _message('Excel export ke liye data nahi hai.', error: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final ex.Excel workbook = ex.Excel.createExcel();
      final ex.Sheet sheet = workbook['GST Item Report'];
      workbook.delete('Sheet1');
      sheet.appendRow([
        ex.TextCellValue('Item'),
        ex.TextCellValue('HSN/SAC'),
        ex.TextCellValue('GST %'),
        ex.TextCellValue('Qty'),
        ex.TextCellValue('Gross'),
        ex.TextCellValue('Discount'),
        ex.TextCellValue('Taxable'),
        ex.TextCellValue('CGST'),
        ex.TextCellValue('SGST'),
        ex.TextCellValue('GST'),
        ex.TextCellValue('Final'),
      ]);
      for (final Map<String, dynamic> row in _summaryRows) {
        sheet.appendRow([
          ex.TextCellValue(row['item_name'].toString()),
          ex.TextCellValue(row['hsn_sac'].toString()),
          ex.DoubleCellValue(_toDouble(row['gst_percent'])),
          ex.IntCellValue(_toInt(row['qty'])),
          ex.DoubleCellValue(_toDouble(row['gross'])),
          ex.DoubleCellValue(_toDouble(row['discount'])),
          ex.DoubleCellValue(_toDouble(row['taxable'])),
          ex.DoubleCellValue(_toDouble(row['cgst'])),
          ex.DoubleCellValue(_toDouble(row['sgst'])),
          ex.DoubleCellValue(_toDouble(row['gst_amount'])),
          ex.DoubleCellValue(_toDouble(row['final_amount'])),
        ]);
      }
      final List<int>? bytes = workbook.save();
      if (bytes == null) throw Exception('Excel generate nahi hui.');
      await FileSaver.instance.saveFile(
        name: 'gst_item_report_${_dateOnly(_fromDate)}_${_dateOnly(_toDate)}',
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      _message('Excel report download ho gayi.');
    } catch (error) {
      _message('Excel export error: $error', error: true);
    }
    if (mounted) setState(() => _exporting = false);
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) => Container(
        width: 150,
        height: 82,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 17), const SizedBox(width: 5), Expanded(child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))]),
            const Spacer(),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _dropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) => SizedBox(
        width: 165,
        child: DropdownButtonFormField<String>(
          initialValue: items.contains(value) ? value : items.first,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item == 'ALL' ? 'All' : item, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      );

  Widget _buildFilters() => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(onPressed: () => _pickDate(from: true), icon: const Icon(Icons.calendar_month), label: Text('From ${_displayDate(_fromDate)}')),
              OutlinedButton.icon(onPressed: () => _pickDate(from: false), icon: const Icon(Icons.event_available), label: Text('To ${_displayDate(_toDate)}')),
              _dropdown('Branch', _selectedBranch, _branches, (value) => setState(() => _selectedBranch = value ?? 'ALL')),
              _dropdown('Item', _selectedItem, _items, (value) => setState(() => _selectedItem = value ?? 'ALL')),
              _dropdown('Payment', _selectedPayment, _payments, (value) => setState(() => _selectedPayment = value ?? 'ALL')),
              SizedBox(
                width: 230,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(labelText: 'Search ticket / item / HSN', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                  onChanged: (value) => _searchText = value,
                  onSubmitted: (_) => setState(_buildRows),
                ),
              ),
              FilledButton.icon(onPressed: () => setState(_buildRows), icon: const Icon(Icons.filter_alt), label: const Text('Apply')),
              OutlinedButton.icon(onPressed: _loadReport, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
              OutlinedButton.icon(onPressed: _exporting ? null : _exportExcel, icon: const Icon(Icons.table_view), label: const Text('Excel')),
              OutlinedButton.icon(onPressed: _exporting ? null : _exportPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('A4 PDF')),
              OutlinedButton.icon(onPressed: _printPdf, icon: const Icon(Icons.print), label: const Text('Print A4')),
            ],
          ),
        ),
      );

  Widget _buildTable() {
    if (_summaryRows.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('No GST item data found')));
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Item')),
            DataColumn(label: Text('HSN/SAC')),
            DataColumn(label: Text('GST %'), numeric: true),
            DataColumn(label: Text('Qty'), numeric: true),
            DataColumn(label: Text('Gross'), numeric: true),
            DataColumn(label: Text('Discount'), numeric: true),
            DataColumn(label: Text('Taxable'), numeric: true),
            DataColumn(label: Text('CGST'), numeric: true),
            DataColumn(label: Text('SGST'), numeric: true),
            DataColumn(label: Text('GST'), numeric: true),
            DataColumn(label: Text('Final'), numeric: true),
          ],
          rows: _summaryRows.map((row) => DataRow(cells: [
            DataCell(Text(row['item_name'].toString())),
            DataCell(Text(row['hsn_sac'].toString())),
            DataCell(Text(_number(row['gst_percent']))),
            DataCell(Text(row['qty'].toString())),
            DataCell(Text(_money(row['gross']))),
            DataCell(Text(_money(row['discount']))),
            DataCell(Text(_money(row['taxable']))),
            DataCell(Text(_money(row['cgst']))),
            DataCell(Text(_money(row['sgst']))),
            DataCell(Text(_money(row['gst_amount']))),
            DataCell(Text(_money(row['final_amount']))),
          ])).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GST Item Report')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('GST report error: $_error'))
              : RefreshIndicator(
                  onRefresh: _loadReport,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _summaryCard('Tickets', '$_totalTickets', Icons.confirmation_number, Colors.blue.shade50),
                        _summaryCard('Item Qty', '$_totalQty', Icons.inventory_2, Colors.indigo.shade50),
                        _summaryCard('Gross', _money(_sum('gross')), Icons.account_balance_wallet, Colors.blueGrey.shade50),
                        _summaryCard('Discount', _money(_sum('discount')), Icons.discount, Colors.orange.shade50),
                        _summaryCard('Taxable', _money(_sum('taxable')), Icons.receipt_long, Colors.teal.shade50),
                        _summaryCard('CGST', _money(_sum('cgst')), Icons.percent, Colors.green.shade50),
                        _summaryCard('SGST', _money(_sum('sgst')), Icons.percent, Colors.lightGreen.shade50),
                        _summaryCard('Total GST', _money(_sum('gst_amount')), Icons.account_balance, Colors.purple.shade50),
                        _summaryCard('Final', _money(_sum('final_amount')), Icons.payments, Colors.green.shade50),
                      ]),
                      const SizedBox(height: 12),
                      _buildFilters(),
                      const SizedBox(height: 12),
                      _buildTable(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
