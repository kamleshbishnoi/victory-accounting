import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.Document> generateTicketPdf(Map<String, dynamic> ticket) async {
  final doc = pw.Document();

  // 80mm thermal common size
  final pageFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    200 * PdfPageFormat.mm,
    marginAll: 6 * PdfPageFormat.mm,
  );

  pw.Widget slip(String copyName) {
    final branch = (ticket['branch_code'] ?? '').toString();
    final ticketNo = (ticket['ticket_no'] ?? '').toString();
    final createdAt = (ticket['created_at'] ?? '').toString();
    final payment = (ticket['payment_mode'] ?? '').toString();

    final subtotal = (ticket['subtotal'] ?? 0).toString();
    final discountAmount = (ticket['discount_amount'] ?? 0).toString();
    final finalAmount = (ticket['final_amount'] ?? 0).toString();

    final items = (ticket['ticket_items'] is List)
        ? List<Map<String, dynamic>>.from(ticket['ticket_items'] as List)
        : <Map<String, dynamic>>[];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Text(
            'VICTORY',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(child: pw.Text('Ticket Slip ($copyName)')),
        pw.SizedBox(height: 6),

        pw.Text('Branch: $branch'),
        pw.Text('Ticket No: $ticketNo'),
        pw.Text('Time: $createdAt'),
        pw.Text('Payment: $payment'),
        pw.Divider(),

        pw.Text('Items:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),

        ...items.map((it) {
          final name = (it['item_name_snapshot'] ?? it['item_name'] ?? '').toString();
          final qty = (it['qty'] ?? 0).toString();
          final rate = (it['unit_price_snapshot'] ?? 0).toString();
          final line = (it['line_total'] ?? 0).toString();
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(child: pw.Text('$name x$qty')),
                pw.Text('₹$line'),
              ],
            ),
          );
        }),

        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Subtotal'), pw.Text('₹$subtotal')],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('Discount'), pw.Text('₹$discountAmount')],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Final', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('₹$finalAmount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('GST Included')),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('THANK YOU')),
      ],
    );
  }

  // Two slips in one print (Customer + Office)
  doc.addPage(pw.Page(pageFormat: pageFormat, build: (_) => slip('Customer Copy')));
  doc.addPage(pw.Page(pageFormat: pageFormat, build: (_) => slip('Office Copy')));

  return doc;
}