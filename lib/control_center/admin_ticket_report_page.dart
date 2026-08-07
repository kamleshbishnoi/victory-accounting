import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminTicketReportPage extends StatefulWidget {
  const AdminTicketReportPage({super.key});

  @override
  State<AdminTicketReportPage> createState() => _AdminTicketReportPageState();
}

class _AdminTicketReportPageState extends State<AdminTicketReportPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _ticketSearchController = TextEditingController();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _allTickets = [];
  List<Map<String, dynamic>> _filteredTickets = [];

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  String _selectedBranch = 'ALL';
  String _selectedPayment = 'ALL';
  String _selectedAgent = 'ALL';
  String _selectedCommissionStatus = 'ALL';

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  @override
  void dispose() {
    _ticketSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await supabase
          .from('tickets')
          .select('''
            id,
            ticket_no,
            created_at,
            ticket_date,
            branch_code,
            payment_mode,
            payment_method,
            subtotal,
            discount_amount,
            discount,
            final_amount,
            agent_id,
            commission_percent,
            commission_amount,
            commission_paid,
            staff_username,
            ticket_items(
              id,
              qty,
              item_name_snapshot,
              unit_price_snapshot,
              line_total
            ),
            agents(
              id,
              agent_code,
              agent_name
            )
          ''')
          .order('created_at', ascending: false)
          .limit(2000);

      final loaded = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;

      setState(() {
        _allTickets = loaded;
        _loading = false;
      });

      _applyFilters();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    final searchText = _ticketSearchController.text.trim().toLowerCase();

    final from = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);

    final to = DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);

    final filtered = _allTickets.where((ticket) {
      final ticketDate = _ticketFilterDate(ticket);

      if (ticketDate == null) return false;
      if (ticketDate.isBefore(from) || ticketDate.isAfter(to)) {
        return false;
      }

      final branch = (ticket['branch_code'] ?? '').toString().trim();

      if (_selectedBranch != 'ALL' && branch != _selectedBranch) {
        return false;
      }

      final payment = _paymentText(ticket).toUpperCase();

      if (_selectedPayment != 'ALL' && payment != _selectedPayment) {
        return false;
      }

      final agentCode = _agentIdText(ticket);

      if (_selectedAgent != 'ALL' && agentCode != _selectedAgent) {
        return false;
      }

      final commissionPaid = (ticket['commission_paid'] ?? false) == true;

      if (_selectedCommissionStatus == 'PAID' && !commissionPaid) {
        return false;
      }

      if (_selectedCommissionStatus == 'PENDING' && commissionPaid) {
        return false;
      }

      if (searchText.isNotEmpty) {
        final ticketNo = (ticket['ticket_no'] ?? '').toString().toLowerCase();

        if (!ticketNo.contains(searchText)) {
          return false;
        }
      }

      return true;
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredTickets = filtered;
    });
  }

  void _showToday() {
    final now = DateTime.now();

    setState(() {
      _fromDate = now;
      _toDate = now;
      _selectedBranch = 'ALL';
      _selectedPayment = 'ALL';
      _selectedAgent = 'ALL';
      _selectedCommissionStatus = 'ALL';
      _ticketSearchController.clear();
    });

    _applyFilters();
  }

  void _clearFilters() {
    final now = DateTime.now();

    setState(() {
      _fromDate = DateTime(now.year, now.month, 1);
      _toDate = now;
      _selectedBranch = 'ALL';
      _selectedPayment = 'ALL';
      _selectedAgent = 'ALL';
      _selectedCommissionStatus = 'ALL';
      _ticketSearchController.clear();
    });

    _applyFilters();
  }

  Future<void> _selectDate({required bool isFromDate}) async {
    final initialDate = isFromDate ? _fromDate : _toDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isFromDate) {
        _fromDate = picked;

        if (_fromDate.isAfter(_toDate)) {
          _toDate = picked;
        }
      } else {
        _toDate = picked;

        if (_toDate.isBefore(_fromDate)) {
          _fromDate = picked;
        }
      }
    });

    _applyFilters();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  String _exportFileName(String extension) {
    final from = DateFormat('yyyyMMdd').format(_fromDate);
    final to = DateFormat('yyyyMMdd').format(_toDate);
    return 'ticket_report_${from}_$to.$extension';
  }

  String _itemsPlainText(Map<String, dynamic> ticket) {
    final items = _getItems(ticket);

    if (items.isEmpty) return '-';

    return items
        .map((item) {
          final name = (item['item_name_snapshot'] ?? 'Item').toString();
          final qty = _toInt(item['qty']);
          final rate = _toDouble(item['unit_price_snapshot']);
          final total = _toDouble(item['line_total']);
          return '$name x$qty @${_number(rate)} = ${_number(total)}';
        })
        .join(' | ');
  }

  Future<void> _exportExcel() async {
    if (_filteredTickets.isEmpty) {
      _showMessage('Export ke liye koi ticket nahi hai.', error: true);
      return;
    }

    try {
      final workbook = ex.Excel.createExcel();
      final sheet = workbook['Ticket Report'];
      workbook.delete('Sheet1');

      final titleStyle = ex.CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: ex.HorizontalAlign.Center,
      );

      final headerStyle = ex.CellStyle(
        bold: true,
        backgroundColorHex: ex.ExcelColor.fromHexString('#1F4E78'),
        horizontalAlign: ex.HorizontalAlign.Center,
        verticalAlign: ex.VerticalAlign.Center,
        textWrapping: ex.TextWrapping.WrapText,
      );

      final summaryStyle = ex.CellStyle(
        bold: true,
        fontColorHex: ex.ExcelColor.fromHexString('#FFFFFF'),
      );

      sheet.merge(
        ex.CellIndex.indexByString('A1'),
        ex.CellIndex.indexByString('Q1'),
      );
      final titleCell = sheet.cell(ex.CellIndex.indexByString('A1'));
      titleCell.value = ex.TextCellValue('Admin Ticket Report');
      titleCell.cellStyle = titleStyle;

      sheet.appendRow([
        ex.TextCellValue('From Date'),
        ex.TextCellValue(_dateButtonText(_fromDate)),
        ex.TextCellValue('To Date'),
        ex.TextCellValue(_dateButtonText(_toDate)),
        ex.TextCellValue('Branch'),
        ex.TextCellValue(_selectedBranch),
        ex.TextCellValue('Payment'),
        ex.TextCellValue(_selectedPayment),
        ex.TextCellValue('Agent'),
        ex.TextCellValue(_selectedAgent),
      ]);

      sheet.appendRow([
        ex.TextCellValue('Total Tickets'),
        ex.IntCellValue(_filteredTickets.length),
        ex.TextCellValue('Total Visitors'),
        ex.IntCellValue(_totalVisitors),
        ex.TextCellValue('Gross Sale'),
        ex.DoubleCellValue(_grossSale),
        ex.TextCellValue('Discount'),
        ex.DoubleCellValue(_totalDiscount),
        ex.TextCellValue('Net Sale'),
        ex.DoubleCellValue(_netSale),
      ]);

      sheet.appendRow([
        ex.TextCellValue('Cash'),
        ex.DoubleCellValue(_paymentTotal('CASH')),
        ex.TextCellValue('UPI'),
        ex.DoubleCellValue(_paymentTotal('UPI')),
        ex.TextCellValue('Card'),
        ex.DoubleCellValue(_paymentTotal('CARD')),
        ex.TextCellValue('Commission'),
        ex.DoubleCellValue(_totalCommission),
        ex.TextCellValue('Commission Paid'),
        ex.DoubleCellValue(_paidCommission),
        ex.TextCellValue('Commission Due'),
        ex.DoubleCellValue(_dueCommission),
      ]);

      for (var column = 0; column < 12; column++) {
        sheet
                .cell(
                  ex.CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: 2,
                  ),
                )
                .cellStyle =
            summaryStyle;
        sheet
                .cell(
                  ex.CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: 3,
                  ),
                )
                .cellStyle =
            summaryStyle;
      }

      sheet.appendRow([ex.TextCellValue('')]);

      final headers = <String>[
        'Sr No',
        'Ticket No',
        'Date-Time',
        'Branch',
        'Payment',
        'Visitors',
        'Items',
        'Gross',
        'Discount',
        'Net',
        'Agent Code',
        'Agent Name',
        'Commission %',
        'Commission Amount',
        'Commission Status',
        'Staff',
        'Ticket ID',
      ];

      sheet.appendRow(
        headers.map<ex.CellValue>((value) => ex.TextCellValue(value)).toList(),
      );

      final headerRowIndex = sheet.maxRows - 1;
      for (var column = 0; column < headers.length; column++) {
        sheet
                .cell(
                  ex.CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: headerRowIndex,
                  ),
                )
                .cellStyle =
            headerStyle;
      }

      for (var index = 0; index < _filteredTickets.length; index++) {
        final ticket = _filteredTickets[index];
        final paid = (ticket['commission_paid'] ?? false) == true;

        sheet.appendRow([
          ex.IntCellValue(index + 1),
          ex.TextCellValue((ticket['ticket_no'] ?? '-').toString()),
          ex.TextCellValue(_dateTimeText(ticket)),
          ex.TextCellValue((ticket['branch_code'] ?? '-').toString()),
          ex.TextCellValue(_paymentText(ticket)),
          ex.IntCellValue(_visitorCount(ticket)),
          ex.TextCellValue(_itemsPlainText(ticket)),
          ex.DoubleCellValue(_toDouble(ticket['subtotal'])),
          ex.DoubleCellValue(_discountAmount(ticket)),
          ex.DoubleCellValue(_toDouble(ticket['final_amount'])),
          ex.TextCellValue(_agentIdText(ticket)),
          ex.TextCellValue(_agentNameText(ticket)),
          ex.DoubleCellValue(_toDouble(ticket['commission_percent'])),
          ex.DoubleCellValue(_toDouble(ticket['commission_amount'])),
          ex.TextCellValue(paid ? 'Paid' : 'Pending'),
          ex.TextCellValue((ticket['staff_username'] ?? '-').toString()),
          ex.TextCellValue((ticket['id'] ?? '').toString()),
        ]);
      }

      final widths = <double>[
        8,
        23,
        20,
        12,
        12,
        10,
        55,
        13,
        13,
        13,
        15,
        22,
        14,
        18,
        18,
        16,
        24,
      ];
      for (var index = 0; index < widths.length; index++) {
        sheet.setColumnWidth(index, widths[index]);
      }

      final bytes = workbook.save();
      if (bytes == null) {
        throw Exception('Excel file generate nahi hui.');
      }

      await FileSaver.instance.saveFile(
        name: _exportFileName('xlsx').replaceAll('.xlsx', ''),
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      _showMessage('Excel file download ho gayi.');
    } catch (e) {
      _showMessage('Excel export error: $e', error: true);
    }
  }

  Future<Uint8List> _buildPdfBytes() async {
    final document = pw.Document();

    final rows = _filteredTickets.asMap().entries.map((entry) {
      final ticket = entry.value;
      final paid = (ticket['commission_paid'] ?? false) == true;

      return <String>[
        '${entry.key + 1}',
        (ticket['ticket_no'] ?? '-').toString(),
        _dateTimeText(ticket),
        (ticket['branch_code'] ?? '-').toString(),
        _paymentText(ticket),
        '${_visitorCount(ticket)}',
        _itemsPlainText(ticket),
        _number(_discountAmount(ticket)),
        _number(_toDouble(ticket['final_amount'])),
        _agentIdText(ticket),
        _number(_toDouble(ticket['commission_amount'])),
        paid ? 'Paid' : 'Pending',
        (ticket['staff_username'] ?? '-').toString(),
      ];
    }).toList();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Admin Ticket Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Date: ${_dateButtonText(_fromDate)} to ${_dateButtonText(_toDate)}'
              '   |   Branch: $_selectedBranch'
              '   |   Payment: $_selectedPayment'
              '   |   Agent: $_selectedAgent',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (context) => [
          pw.Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pdfSummaryBox('Tickets', '${_filteredTickets.length}'),
              _pdfSummaryBox('Visitors', '$_totalVisitors'),
              _pdfSummaryBox('Gross', 'Rs. ${_number(_grossSale)}'),
              _pdfSummaryBox('Discount', 'Rs. ${_number(_totalDiscount)}'),
              _pdfSummaryBox('Net', 'Rs. ${_number(_netSale)}'),
              _pdfSummaryBox('Cash', 'Rs. ${_number(_paymentTotal('CASH'))}'),
              _pdfSummaryBox('UPI', 'Rs. ${_number(_paymentTotal('UPI'))}'),
              _pdfSummaryBox('Card', 'Rs. ${_number(_paymentTotal('CARD'))}'),
              _pdfSummaryBox('Comm.', 'Rs. ${_number(_totalCommission)}'),
              _pdfSummaryBox('Comm. Paid', 'Rs. ${_number(_paidCommission)}'),
              _pdfSummaryBox('Comm. Due', 'Rs. ${_number(_dueCommission)}'),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'Ticket No',
              'Date-Time',
              'Branch',
              'Payment',
              'Visitor',
              'Items',
              'Disc.',
              'Net',
              'Agent',
              'Comm.',
              'Status',
              'Staff',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(3),
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
            columnWidths: {
              0: const pw.FixedColumnWidth(18),
              1: const pw.FixedColumnWidth(78),
              2: const pw.FixedColumnWidth(72),
              3: const pw.FixedColumnWidth(38),
              4: const pw.FixedColumnWidth(42),
              5: const pw.FixedColumnWidth(34),
              6: const pw.FlexColumnWidth(3.2),
              7: const pw.FixedColumnWidth(40),
              8: const pw.FixedColumnWidth(42),
              9: const pw.FixedColumnWidth(48),
              10: const pw.FixedColumnWidth(42),
              11: const pw.FixedColumnWidth(42),
              12: const pw.FixedColumnWidth(48),
            },
          ),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _pdfSummaryBox(String title, String value) {
    return pw.Container(
      width: 92,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    if (_filteredTickets.isEmpty) {
      _showMessage('Export ke liye koi ticket nahi hai.', error: true);
      return;
    }

    try {
      final bytes = await _buildPdfBytes();
      await FileSaver.instance.saveFile(
        name: _exportFileName('pdf').replaceAll('.pdf', ''),
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
      _showMessage('PDF file download ho gayi.');
    } catch (e) {
      _showMessage('PDF export error: $e', error: true);
    }
  }

  Future<void> _printPdf() async {
    if (_filteredTickets.isEmpty) {
      _showMessage('Print ke liye koi ticket nahi hai.', error: true);
      return;
    }

    try {
      final bytes = await _buildPdfBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      _showMessage('Print error: $e', error: true);
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value.toString()) ?? 0;
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    return DateTime.tryParse(value.toString())?.toLocal();
  }

  DateTime? _ticketFilterDate(Map<String, dynamic> ticket) {
    final ticketDate = _parseDate(ticket['ticket_date']);

    if (ticketDate != null) {
      return ticketDate;
    }

    return _parseDate(ticket['created_at']);
  }

  String _dateTimeText(Map<String, dynamic> ticket) {
    final createdAt = _parseDate(ticket['created_at']);

    if (createdAt != null) {
      return DateFormat('dd/MM/yy hh:mm a').format(createdAt);
    }

    final ticketDate = _parseDate(ticket['ticket_date']);

    if (ticketDate != null) {
      return DateFormat('dd/MM/yy').format(ticketDate);
    }

    return '-';
  }

  String _dateButtonText(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _paymentText(Map<String, dynamic> ticket) {
    final paymentMethod = (ticket['payment_method'] ?? '').toString().trim();

    if (paymentMethod.isNotEmpty) {
      return paymentMethod.toUpperCase();
    }

    final paymentMode = (ticket['payment_mode'] ?? '').toString().trim();

    return paymentMode.isEmpty ? '-' : paymentMode.toUpperCase();
  }

  String _money(dynamic value) {
    final amount = _toDouble(value);
    return _currencyFormat.format(amount);
  }

  String _number(dynamic value) {
    final number = _toDouble(value);

    if (number == number.roundToDouble()) {
      return number.toStringAsFixed(0);
    }

    return number.toStringAsFixed(2);
  }

  List<Map<String, dynamic>> _getItems(Map<String, dynamic> ticket) {
    final rawItems = ticket['ticket_items'];

    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic>? _getAgent(Map<String, dynamic> ticket) {
    final rawAgent = ticket['agents'];

    if (rawAgent is Map) {
      return Map<String, dynamic>.from(rawAgent);
    }

    if (rawAgent is List && rawAgent.isNotEmpty) {
      final first = rawAgent.first;

      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
    }

    return null;
  }

  String _agentIdText(Map<String, dynamic> ticket) {
    final agent = _getAgent(ticket);

    final agentCode = (agent?['agent_code'] ?? '').toString().trim();

    if (agentCode.isNotEmpty) {
      return agentCode;
    }

    final agentId = (ticket['agent_id'] ?? '').toString().trim();

    if (agentId.isEmpty) {
      return '-';
    }

    if (agentId.length > 8) {
      return agentId.substring(0, 8);
    }

    return agentId;
  }

  String _agentNameText(Map<String, dynamic> ticket) {
    final agent = _getAgent(ticket);

    return (agent?['agent_name'] ?? '').toString().trim();
  }

  double _discountAmount(Map<String, dynamic> ticket) {
    final discountAmount = _toDouble(ticket['discount_amount']);

    if (discountAmount != 0) {
      return discountAmount;
    }

    return _toDouble(ticket['discount']);
  }

  int _visitorCount(Map<String, dynamic> ticket) {
    final items = _getItems(ticket);

    return items.fold<int>(0, (total, item) => total + _toInt(item['qty']));
  }

  List<String> get _branches {
    final values =
        _allTickets
            .map((ticket) => (ticket['branch_code'] ?? '').toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return ['ALL', ...values];
  }

  List<String> get _payments {
    final values =
        _allTickets
            .map(_paymentText)
            .where((value) => value.isNotEmpty && value != '-')
            .toSet()
            .toList()
          ..sort();

    return ['ALL', ...values];
  }

  List<String> get _agents {
    final values =
        _allTickets
            .map(_agentIdText)
            .where((value) => value.isNotEmpty && value != '-')
            .toSet()
            .toList()
          ..sort();

    return ['ALL', ...values];
  }

  double get _grossSale {
    return _filteredTickets.fold<double>(
      0,
      (total, ticket) => total + _toDouble(ticket['subtotal']),
    );
  }

  double get _totalDiscount {
    return _filteredTickets.fold<double>(
      0,
      (total, ticket) => total + _discountAmount(ticket),
    );
  }

  double get _netSale {
    return _filteredTickets.fold<double>(
      0,
      (total, ticket) => total + _toDouble(ticket['final_amount']),
    );
  }

  int get _totalVisitors {
    return _filteredTickets.fold<int>(
      0,
      (total, ticket) => total + _visitorCount(ticket),
    );
  }

  double _paymentTotal(String paymentName) {
    return _filteredTickets.fold<double>(0, (total, ticket) {
      final payment = _paymentText(ticket).toUpperCase();

      if (payment == paymentName.toUpperCase()) {
        return total + _toDouble(ticket['final_amount']);
      }

      return total;
    });
  }

  double get _totalCommission {
    return _filteredTickets.fold<double>(
      0,
      (total, ticket) => total + _toDouble(ticket['commission_amount']),
    );
  }

  double get _paidCommission {
    return _filteredTickets.fold<double>(0, (total, ticket) {
      final paid = (ticket['commission_paid'] ?? false) == true;

      if (paid) {
        return total + _toDouble(ticket['commission_amount']);
      }

      return total;
    });
  }

  double get _dueCommission {
    return _totalCommission - _paidCommission;
  }

  Widget _buildFilterCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 950;

            final controls = <Widget>[
              _dateFilterButton(
                label: 'From Date',
                date: _fromDate,
                onTap: () => _selectDate(isFromDate: true),
              ),
              _dateFilterButton(
                label: 'To Date',
                date: _toDate,
                onTap: () => _selectDate(isFromDate: false),
              ),
              _dropdownFilter(
                label: 'Branch',
                value: _selectedBranch,
                items: _branches,
                onChanged: (value) {
                  setState(() {
                    _selectedBranch = value ?? 'ALL';
                  });
                  _applyFilters();
                },
              ),
              _dropdownFilter(
                label: 'Payment',
                value: _selectedPayment,
                items: _payments,
                onChanged: (value) {
                  setState(() {
                    _selectedPayment = value ?? 'ALL';
                  });
                  _applyFilters();
                },
              ),
              _dropdownFilter(
                label: 'Agent',
                value: _selectedAgent,
                items: _agents,
                onChanged: (value) {
                  setState(() {
                    _selectedAgent = value ?? 'ALL';
                  });
                  _applyFilters();
                },
              ),
              _dropdownFilter(
                label: 'Commission',
                value: _selectedCommissionStatus,
                items: const ['ALL', 'PAID', 'PENDING'],
                onChanged: (value) {
                  setState(() {
                    _selectedCommissionStatus = value ?? 'ALL';
                  });
                  _applyFilters();
                },
              ),
              SizedBox(
                width: isWide ? 220 : double.infinity,
                child: TextField(
                  controller: _ticketSearchController,
                  onChanged: (_) => _applyFilters(),
                  decoration: const InputDecoration(
                    labelText: 'Ticket No.',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: 10, runSpacing: 10, children: controls),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _applyFilters,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Apply Filter'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showToday,
                      icon: const Icon(Icons.today),
                      label: const Text('Today'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loadTickets,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exportExcel,
                      icon: const Icon(Icons.table_view),
                      label: const Text('Export Excel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Export PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _printPdf,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dateFilterButton({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 170,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.calendar_month),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: Text(_dateButtonText(date)),
        ),
      ),
    );
  }

  Widget _dropdownFilter({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;

    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String>(
        value: safeValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSummarySection() {
    final cards = [
      _SummaryData(
        title: 'Total Tickets',
        value: _filteredTickets.length.toString(),
        icon: Icons.confirmation_number_outlined,
      ),
      _SummaryData(
        title: 'Total Visitors',
        value: _totalVisitors.toString(),
        icon: Icons.groups_outlined,
      ),
      _SummaryData(
        title: 'Gross Sale',
        value: _money(_grossSale),
        icon: Icons.account_balance_wallet_outlined,
      ),
      _SummaryData(
        title: 'Discount',
        value: _money(_totalDiscount),
        icon: Icons.discount_outlined,
      ),
      _SummaryData(
        title: 'Net Sale',
        value: _money(_netSale),
        icon: Icons.payments_outlined,
      ),
      _SummaryData(
        title: 'Cash',
        value: _money(_paymentTotal('CASH')),
        icon: Icons.money_outlined,
      ),
      _SummaryData(
        title: 'UPI',
        value: _money(_paymentTotal('UPI')),
        icon: Icons.qr_code_2,
      ),
      _SummaryData(
        title: 'Card',
        value: _money(_paymentTotal('CARD')),
        icon: Icons.credit_card,
      ),
      _SummaryData(
        title: 'Commission',
        value: _money(_totalCommission),
        icon: Icons.percent,
      ),
      _SummaryData(
        title: 'Comm. Paid',
        value: _money(_paidCommission),
        icon: Icons.check_circle_outline,
      ),
      _SummaryData(
        title: 'Comm. Due',
        value: _money(_dueCommission),
        icon: Icons.pending_actions,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          int columns = 2;

          if (constraints.maxWidth >= 1200) {
            columns = 6;
          } else if (constraints.maxWidth >= 850) {
            columns = 4;
          } else if (constraints.maxWidth >= 600) {
            columns = 3;
          }

          const spacing = 8.0;
          final cardWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: cards
                .map(
                  (data) =>
                      SizedBox(width: cardWidth, child: _summaryCard(data)),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _summaryCard(_SummaryData data) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(
              data.icon,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsLine(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Text(
        'Items: -',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }

    final parts = items.map((item) {
      final name = (item['item_name_snapshot'] ?? 'Item').toString();

      final qty = _toInt(item['qty']);
      final rate = _money(item['unit_price_snapshot']);
      final amount = _money(item['line_total']);

      return '$name ×$qty @$rate = $amount';
    }).toList();

    return Text(
      parts.join('  |  '),
      style: const TextStyle(
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTicketBox(Map<String, dynamic> ticket) {
    final ticketNo = (ticket['ticket_no'] ?? '-').toString();

    final branch = (ticket['branch_code'] ?? '-').toString();

    final finalAmount = _toDouble(ticket['final_amount']);
    final discount = _discountAmount(ticket);

    final commissionPercent = _toDouble(ticket['commission_percent']);

    final commissionAmount = _toDouble(ticket['commission_amount']);

    final commissionPaid = (ticket['commission_paid'] ?? false) == true;

    final staff = (ticket['staff_username'] ?? '-').toString();

    final payment = _paymentText(ticket);
    final dateTime = _dateTimeText(ticket);
    final agentId = _agentIdText(ticket);
    final agentName = _agentNameText(ticket);
    final items = _getItems(ticket);
    final visitors = _visitorCount(ticket);

    final agentText = agentName.isEmpty ? agentId : '$agentId ($agentName)';

    final firstLine =
        '$ticketNo  |  $dateTime  |  $branch  |  $payment  |  '
        'Agent: $agentText  |  Comm: ${_number(commissionPercent)}% '
        '= ${_money(commissionAmount)}  |  '
        '${commissionPaid ? 'Paid' : 'Pending'}  |  '
        'Disc: ${_money(discount)}  |  '
        'Net: ${_money(finalAmount)}  |  Staff: $staff';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            firstLine,
            style: const TextStyle(
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildItemsLine(items)),
              const SizedBox(width: 12),
              Text(
                'Visitors: $visitors',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsList() {
    if (_filteredTickets.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: Text(
              'Is filter me koi ticket nahi mila.',
              style: TextStyle(fontSize: 15),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        return _buildTicketBox(_filteredTickets[index]);
      }, childCount: _filteredTickets.length),
    );
  }

  Widget _buildReport() {
    return RefreshIndicator(
      onRefresh: _loadTickets,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildFilterCard()),
          SliverToBoxAdapter(child: _buildSummarySection()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ticket Details (${_filteredTickets.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _isSameDay(_fromDate, _toDate)
                        ? _dateButtonText(_fromDate)
                        : '${_dateButtonText(_fromDate)} - '
                              '${_dateButtonText(_toDate)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          _buildTicketsList(),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Colors.red),
            const SizedBox(height: 10),
            const Text(
              'Ticket report load nahi hua',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadTickets,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Ticket Report'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadTickets,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildReport(),
    );
  }
}

class _SummaryData {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryData({
    required this.title,
    required this.value,
    required this.icon,
  });
}
