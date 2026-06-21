import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.Document> generateTicketPdf(Map<String, dynamic> ticket) async {
  final doc = pw.Document();

  final settings =
      Map<String, dynamic>.from(ticket['branch_settings'] ?? {});

  final branchCode = (ticket['branch_code'] ?? '').toString();
  final branchName = (settings['branch_name'] ?? branchCode).toString();
  final companyName = (settings['company_name'] ?? '').toString();
  final gstNo = (settings['gst_no'] ?? settings['gst_number'] ?? '').toString();
  final address = (settings['address'] ?? '').toString();
  final phone = (settings['phone'] ?? '').toString();
  final terms = (settings['terms_conditions'] ?? '').toString();
  final footer = (settings['ticket_footer'] ?? 'Thank you for visiting').toString();
  final parkingCopy = settings['parking_copy'] == true;

  final pageFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    180 * PdfPageFormat.mm,
    marginAll: 5 * PdfPageFormat.mm,
  );

  String money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return 'Rs. ${n.toStringAsFixed(0)}';
  }

  DateTime dt() {
  final raw = (ticket['ticket_date'] ?? ticket['created_at'] ?? '').toString();

  if (raw.isEmpty) {
    return DateTime.now();
  }

  return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
}

  String dateText() {
    final d = dt();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  String timeText() {
    final d = dt();
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  pw.Widget mainSlip() {
    final ticketNo = (ticket['ticket_no'] ?? '').toString();
    final payment = (ticket['payment_mode'] ?? ticket['payment_method'] ?? '').toString();

    final items = (ticket['ticket_items'] is List)
        ? List<Map<String, dynamic>>.from(ticket['ticket_items'] as List)
        : <Map<String, dynamic>>[];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Text(
            branchName.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (companyName.isNotEmpty)
          pw.Center(child: pw.Text(companyName, textAlign: pw.TextAlign.center)),
        if (gstNo.isNotEmpty)
          pw.Center(child: pw.Text('GSTIN: $gstNo')),
        if (address.isNotEmpty)
          pw.Center(child: pw.Text(address, textAlign: pw.TextAlign.center)),
        if (phone.isNotEmpty)
          pw.Center(child: pw.Text('Phone: $phone')),
        pw.SizedBox(height: 6),

        pw.Text('Customer: $payment'),
        pw.Text('Bill No: $ticketNo'),
        pw.Text('Date: ${dateText()}   Time: ${timeText()}'),
        pw.Divider(),

        pw.Row(children: [
          pw.SizedBox(width: 22, child: pw.Text('S.N.')),
          pw.Expanded(child: pw.Text('Description')),
          pw.SizedBox(width: 35, child: pw.Text('Rate')),
          pw.SizedBox(width: 25, child: pw.Text('Qty')),
          pw.SizedBox(width: 40, child: pw.Text('Amt')),
        ]),
        pw.Divider(),

        ...items.asMap().entries.map((e) {
          final i = e.key + 1;
          final it = e.value;
          final name = (it['item_name_snapshot'] ?? it['item_name'] ?? '').toString();
          final qty = (it['qty'] ?? 0).toString();
          final rate = money(it['unit_price_snapshot']);
          final line = money(it['line_total']);

          return pw.Row(children: [
            pw.SizedBox(width: 22, child: pw.Text('$i')),
            pw.Expanded(child: pw.Text(name)),
            pw.SizedBox(width: 35, child: pw.Text(rate.replaceAll('Rs. ', ''))),
            pw.SizedBox(width: 25, child: pw.Text(qty)),
            pw.SizedBox(width: 40, child: pw.Text(line.replaceAll('Rs. ', ''))),
          ]);
        }),

        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Sub Total'), pw.Text(money(ticket['subtotal']))],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Discount'), pw.Text(money(ticket['discount_amount']))],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Gross Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(money(ticket['final_amount']),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),

        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('GST Included')),
        pw.Center(child: pw.Text(footer)),

        if (terms.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(terms, style: const pw.TextStyle(fontSize: 8)),
        ],
      ],
    );
  }

  pw.Widget parkingSlip() {
    return pw.Center(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'PARKING',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Ticket No: ${ticket['ticket_no'] ?? ''}'),
          pw.Text('Date: ${dateText()}'),
          pw.Text('Time: ${timeText()}'),
        ],
      ),
    );
  }

  doc.addPage(pw.Page(pageFormat: pageFormat, build: (_) => mainSlip()));

  if (parkingCopy) {
    doc.addPage(pw.Page(pageFormat: pageFormat, build: (_) => parkingSlip()));
  }

  return doc;
}