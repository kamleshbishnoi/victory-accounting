import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.Document> generateTicketPdf(Map<String, dynamic> ticket) async {
  final doc = pw.Document();

  final settings = Map<String, dynamic>.from(ticket['branch_settings'] ?? {});

  final branchCode = (ticket['branch_code'] ?? '').toString();
  final branchName = (settings['branch_name'] ?? branchCode).toString();
  final companyName = (settings['company_name'] ?? '').toString();
  final gstNo = (settings['gst_no'] ?? settings['gst_number'] ?? '').toString();
  final address = (settings['address'] ?? '').toString();
  final phone = (settings['phone'] ?? '').toString();
  final terms = (settings['terms_conditions'] ?? '').toString();
  final footer = (settings['ticket_footer'] ?? 'Thank you for visiting')
      .toString();
  final parkingCopy = settings['parking_copy'] == true;
  print('PDF SETTINGS IN PRINT = $settings');

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
    final rawCreated = (ticket['created_at'] ?? '').toString();

    if (rawCreated.isNotEmpty) {
      return DateTime.parse(rawCreated).toLocal();
    }

    return DateTime.now();
  }

  String dateText() {
    final d = dt();
    return '${d.day.toString().padLeft(2, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.year}';
  }

  String timeText() {
    final d = dt();

    int h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'PM' : 'AM';

    if (h > 12) h -= 12;
    if (h == 0) h = 12;

    return '$h:$m $ap';
  }


final isMayNat =
    branchCode.trim().toUpperCase() == 'MAY' ||
    branchCode.trim().toUpperCase() == 'NAT';

final thermalFont = pw.Font.courier();
final thermalBold = pw.Font.courierBold();

pw.TextStyle thermalText(double size) => pw.TextStyle(
      font: thermalFont,
      fontSize: size,
    );

pw.TextStyle thermalBoldText(double size) => pw.TextStyle(
      font: thermalBold,
      fontSize: size,
      fontWeight: pw.FontWeight.bold,
    );

String cleanCompanyHeading() {
  final company = companyName.trim();
  final branch = branchName.trim();

  // Agar company_name me already "(MAYALOK)" ya "(NATHDWARA)"
  // likha hua hai to dobara brackets nahi lagayega.
  if (company.toUpperCase().contains('(${branch.toUpperCase()})')) {
    return company;
  }

  if (company.isEmpty) return branch;
  if (branch.isEmpty) return company;

  return '$company (${branch.toUpperCase()})';
}

  pw.Widget mayNatSlip() {
    final branch = (ticket['branch_code'] ?? '').toString().trim().toUpperCase();
    final branchName = (settings['branch_name'] ?? (branch == 'MAY' ? 'Mayalok' : 'Nathdwara')).toString();
    final companyName = (settings['company_name'] ?? branchName).toString();
    final gstNo = (settings['gst_no'] ?? settings['gst_number'] ?? '').toString();
    final address = (settings['address'] ?? '').toString();
    final phone = (settings['phone'] ?? '').toString();

    String pick(List<dynamic> values) {
      for (final v in values) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
      return '';
    }

    double n(dynamic v) => v is num ? v.toDouble() : (double.tryParse((v ?? '').toString()) ?? 0);

    final guest = pick([ticket['guest_name'], ticket['customer_name'], ticket['name']]);
    final mobile = pick([ticket['mobile'], ticket['customer_mobile'], ticket['phone']]);
    final ticketNo = pick([ticket['ticket_no'], ticket['invoice_no']]);
    final createdBy = pick([ticket['created_by_name'], ticket['created_by'], ticket['username'], ticket['user_name']]);

    final items = (ticket['ticket_items'] is List)
        ? List<Map<String, dynamic>>.from(ticket['ticket_items'] as List)
        : <Map<String, dynamic>>[];

    final ticketName = items
        .map((it) => pick([it['item_name_snapshot'], it['item_name'], it['name']]))
        .where((e) => e.isNotEmpty)
        .join(' + ');

    final gross = n(ticket['final_amount'] ?? ticket['subtotal'] ?? ticket['total_amount']);
    final gstPercent = n(settings['gst_percent'] ?? 18);
    final taxable = gstPercent > 0 ? gross / (1 + gstPercent / 100) : gross;
    final totalGst = gross - taxable;
    final cgst = totalGst / 2;
    final sgst = totalGst / 2;

    const small = pw.TextStyle(fontSize: 8.5);
    pw.TextStyle bold([double size = 9]) =>
        pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            '$companyName (${branchName.toUpperCase()})',
            textAlign: pw.TextAlign.center,
            style: bold(10.5),
          ),
        ),
        if (gstNo.isNotEmpty)
          pw.Center(child: pw.Text('GSTIN No : $gstNo', style: small)),
        if (address.isNotEmpty)
          pw.Center(child: pw.Text(address, textAlign: pw.TextAlign.center, style: small)),
        if (phone.isNotEmpty)
          pw.Center(child: pw.Text('Phone : $phone', style: small)),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'TAX / RETAIL INVOICE',
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Guest      : $guest', style: small),
        pw.Text('Mobile     : $mobile', style: small),
        pw.Text('Invoice No.: $ticketNo', style: small),
        pw.Text('Date       : ${dateText()} ${timeText()}', style: small),
        pw.Text('Ticket     : $ticketName', style: small),
        pw.SizedBox(height: 7),
        pw.Center(
          child: pw.Text(
            'PARTICULARS',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          children: [
            pw.Expanded(flex: 2, child: pw.Text('QTY', style: bold(8.5))),
            pw.Expanded(flex: 3, child: pw.Text('Rate', textAlign: pw.TextAlign.center, style: bold(8.5))),
            pw.Expanded(flex: 3, child: pw.Text('Total', textAlign: pw.TextAlign.right, style: bold(8.5))),
          ],
        ),
        pw.Divider(height: 5),
        ...items.map((it) {
          final qty = n(it['qty']);
          final rate = n(it['unit_price_snapshot'] ?? it['unit_price'] ?? it['rate']);
          final total = n(it['line_total'] ?? (qty * rate));
          return pw.Row(
            children: [
              pw.Expanded(flex: 2, child: pw.Text(money(qty).replaceAll('Rs. ', ''), style: small)),
              pw.Expanded(flex: 3, child: pw.Text(money(rate).replaceAll('Rs. ', ''), textAlign: pw.TextAlign.center, style: small)),
              pw.Expanded(flex: 3, child: pw.Text(money(total).replaceAll('Rs. ', ''), textAlign: pw.TextAlign.right, style: small)),
            ],
          );
        }),
        pw.Divider(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Gross Total', style: small), pw.Text(money(gross).replaceAll('Rs. ', ''), style: small)],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Net Payable (Rounded Off)', style: bold(8.5)), pw.Text(money(gross).replaceAll('Rs. ', ''), style: bold(8.5))],
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'GST RECEIPT SUMMARY',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          children: [
            pw.Expanded(child: pw.Text('HSN', style: bold(7.5))),
            pw.Expanded(child: pw.Text('GST %', style: bold(7.5))),
            pw.Expanded(child: pw.Text('Taxable', style: bold(7.5))),
            pw.Expanded(child: pw.Text('Central', style: bold(7.5))),
            pw.Expanded(child: pw.Text('State', style: bold(7.5))),
          ],
        ),
        pw.Divider(height: 4),
        pw.Row(
          children: [
            pw.Expanded(child: pw.Text((settings['hsn_code'] ?? '999693').toString(), style: const pw.TextStyle(fontSize: 7.5))),
            pw.Expanded(child: pw.Text(gstPercent.toStringAsFixed(0), style: const pw.TextStyle(fontSize: 7.5))),
            pw.Expanded(child: pw.Text(taxable.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 7.5))),
            pw.Expanded(child: pw.Text(cgst.toStringAsFixed(3), style: const pw.TextStyle(fontSize: 7.5))),
            pw.Expanded(child: pw.Text(sgst.toStringAsFixed(3), style: const pw.TextStyle(fontSize: 7.5))),
          ],
        ),
        pw.Divider(height: 6),
        pw.Text(
          (settings['terms_conditions'] ?? '').toString().trim().isNotEmpty
              ? settings['terms_conditions'].toString()
              : '1. Please bring a print or soft copy of your ticket.\n2. We are not responsible for lost or misused tickets.',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 8),
        if (createdBy.isNotEmpty)
          pw.Center(child: pw.Text('Created By : $createdBy', style: small)),
        pw.Center(child: pw.Text('Printed On : ${dateText()} ${timeText()}', style: small)),
      ],
    );
  }

  pw.Widget standardSlip() {
    final settings = (ticket['branch_settings'] is Map)
        ? Map<String, dynamic>.from(ticket['branch_settings'])
        : <String, dynamic>{};

    final branch = (ticket['branch_code'] ?? '').toString();

    final branchName = (settings['branch_name'] ?? branch).toString();

    final companyName = (settings['company_name'] ?? '').toString();

    final gstNo = (settings['gst_number'] ?? '').toString();

    final address = (settings['address'] ?? '').toString();

    final phone = (settings['phone'] ?? '').toString();

    final terms = (settings['terms_conditions'] ?? '').toString();

    final footer = (settings['ticket_footer'] ?? '').toString();

    final ticketNo = (ticket['ticket_no'] ?? '').toString();
    final payment = (ticket['payment_mode'] ?? ticket['payment_method'] ?? '')
        .toString();

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
          pw.Center(
            child: pw.Text(companyName, textAlign: pw.TextAlign.center),
          ),
        if (gstNo.isNotEmpty) pw.Center(child: pw.Text('GSTIN: $gstNo')),
        if (address.isNotEmpty)
          pw.Center(child: pw.Text(address, textAlign: pw.TextAlign.center)),
        if (phone.isNotEmpty) pw.Center(child: pw.Text('Phone: $phone')),
        pw.SizedBox(height: 6),

        pw.Text('Customer: $payment'),
        pw.Text('Bill No: $ticketNo'),
        pw.Text('Date: ${dateText()}   Time: ${timeText()}'),
        pw.Divider(),

        pw.Row(
          children: [
            pw.SizedBox(width: 22, child: pw.Text('Sr')),
            pw.Expanded(child: pw.Text('Description')),
            pw.SizedBox(width: 35, child: pw.Text('Rate')),
            pw.SizedBox(width: 25, child: pw.Text('Qty')),
            pw.SizedBox(width: 40, child: pw.Text('Amt')),
          ],
        ),
        pw.Divider(),

        ...items.asMap().entries.map((e) {
          final i = e.key + 1;
          final it = e.value;
          final name = (it['item_name_snapshot'] ?? it['item_name'] ?? '')
              .toString();
          final qty = (it['qty'] ?? 0).toString();
          final rate = money(it['unit_price_snapshot']);
          final line = money(it['line_total']);

          return pw.Row(
            children: [
              pw.SizedBox(width: 22, child: pw.Text('$i')),
              pw.Expanded(child: pw.Text(name)),
              pw.SizedBox(
                width: 35,
                child: pw.Text(rate.replaceAll('Rs. ', '')),
              ),
              pw.SizedBox(width: 25, child: pw.Text(qty)),
              pw.SizedBox(
                width: 40,
                child: pw.Text(line.replaceAll('Rs. ', '')),
              ),
            ],
          );
        }),

        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Sub Total'), pw.Text(money(ticket['subtotal']))],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Discount'),
            pw.Text(money(ticket['discount_amount'])),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Gross Total',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              money(ticket['final_amount']),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),

        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('GST Included')),

        if (terms.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Terms & Conditions',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
          pw.Text(terms, style: const pw.TextStyle(fontSize: 8)),
        ],

        if (footer.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(footer, style: const pw.TextStyle(fontSize: 9)),
          ),
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

  final useMayNatFormat = branchCode == 'MAY' || branchCode == 'NAT';

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (_) => useMayNatFormat ? mayNatSlip() : standardSlip(),
    ),
  );

  // Main ticket PDF only.
  // Parking is printed as a separate print job from ticket_create_page.dart.
  return doc;
}

Future<pw.Document> generateParkingPdf(Map<String, dynamic> ticket) async {
  final doc = pw.Document();

  final settings = Map<String, dynamic>.from(ticket['branch_settings'] ?? {});
  final branchCode = (ticket['branch_code'] ?? '').toString().trim().toUpperCase();

  // MAY / NAT never print parking, even if the DB flag is true by mistake.
  if (branchCode == 'MAY' || branchCode == 'NAT') {
    return doc;
  }

  final parkingCopy = settings['parking_copy'] == true;
  if (!parkingCopy) {
    return doc;
  }

  final pageFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    90 * PdfPageFormat.mm,
    marginAll: 5 * PdfPageFormat.mm,
  );

  DateTime dt() {
    final rawCreated = (ticket['created_at'] ?? '').toString();
    if (rawCreated.isNotEmpty) {
      try {
        return DateTime.parse(rawCreated).toLocal();
      } catch (_) {}
    }
    return DateTime.now();
  }

  String dateText() {
    final d = dt();
    return '${d.day.toString().padLeft(2, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.year}';
  }

  String timeText() {
    final d = dt();
    int h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'PM' : 'AM';
    if (h > 12) h -= 12;
    if (h == 0) h = 12;
    return '$h:$m $ap';
  }

  final branchName = (settings['branch_name'] ?? branchCode).toString();
  final ticketNo = (ticket['ticket_no'] ?? '').toString();

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (_) => pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (branchName.isNotEmpty)
              pw.Text(
                branchName.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            pw.SizedBox(height: 6),
            pw.Text(
              'PARKING',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Ticket No: $ticketNo'),
            pw.Text('Date: ${dateText()}'),
            pw.Text('Time: ${timeText()}'),
          ],
        ),
      ),
    ),
  );

  return doc;
}

