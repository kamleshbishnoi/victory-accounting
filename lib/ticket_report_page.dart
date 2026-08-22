import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TicketReportPage extends StatefulWidget {
  final String branch;
  final String username;

  const TicketReportPage({
    super.key,
    required this.branch,
    required this.username,
  });

  @override
  State<TicketReportPage> createState() => _TicketReportPageState();
}

class _TicketReportPageState extends State<TicketReportPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  String? branchId;
  String? branchCode;
  String? branchName;

  late DateTime _from;
  late DateTime _to;
  String _payment = 'ALL'; // ALL / Cash / UPI / Card

  static const int pageSize = 20;
  int page = 0;
  bool hasNext = false;

  List<Map<String, dynamic>> rows = [];

  bool get _isAdmin => widget.username.trim().toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _to = _from;
    _init();
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  String _norm(String s) => s.trim().toUpperCase();

  String _normNameLoose(String s) {
    var x = s.trim();
    x = x.replaceAll('_', ' ');
    x = x.replaceAll('-', ' ');
    x = x.replaceAll(RegExp(r'\s+'), ' ');
    return x;
  }

  Future<Map<String, dynamic>?> _findBranchByCodeOrName(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final codeGuess = _norm(raw);
    final nameGuessLoose = _normNameLoose(raw);

    final byCode = await supabase
        .from('branches')
        .select('id, code, name')
        .eq('code', codeGuess)
        .maybeSingle();
    if (byCode != null) return Map<String, dynamic>.from(byCode);

    final byNameExact = await supabase
        .from('branches')
        .select('id, code, name')
        .eq('name', nameGuessLoose)
        .maybeSingle();
    if (byNameExact != null) return Map<String, dynamic>.from(byNameExact);

    final list = await supabase
        .from('branches')
        .select('id, code, name')
        .ilike('name', '%$nameGuessLoose%')
        .limit(1);

    if (list is List && list.isNotEmpty) {
      return Map<String, dynamic>.from(list.first);
    }
    return null;
  }

  DateTime _startLocal(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endLocalExclusive(DateTime d) =>
      DateTime(d.year, d.month, d.day).add(const Duration(days: 1));

  Future<void> _init() async {
    setState(() => loading = true);
    try {
      final input = widget.branch.trim();

      if (_norm(input) == 'ALL' || input.isEmpty) {
        branchId = null;
        branchCode = 'ALL';
        branchName = 'ALL';
        rows = [];
        hasNext = false;
        _toast(
          'ALL mode me ticket report branch-wise nahi hoti. Branch select karo.',
        );
        return;
      }

      final b = await _findBranchByCodeOrName(input);
      if (b == null) {
        branchId = null;
        rows = [];
        hasNext = false;
        _toast('Branch not found: $input');
        return;
      }

      branchId = (b['id'] ?? '').toString();
      branchCode = (b['code'] ?? '').toString().toUpperCase().trim();
      branchName = (b['name'] ?? '').toString();

      page = 0;
      await _load();
    } catch (e) {
      _toast('Init error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      if (branchId == null) {
        rows = [];
        hasNext = false;
        return;
      }

      final from = _startLocal(_from).toUtc().toIso8601String();
      final toEx = _endLocalExclusive(_to).toUtc().toIso8601String();

      final offset = page * pageSize;

      // ✅ RPC call (expected to return List of rows)
      final data = await supabase.rpc(
        'get_ticket_report',
        params: {
          'p_branch_id': branchId,
          'p_from': from,
          'p_to': toEx,
          'p_payment': _payment,
          'p_offset': offset,
          'p_limit': pageSize + 1, // extra 1 for next page
        },
      );

      final list = List<Map<String, dynamic>>.from(data as List);

      hasNext = list.length > pageSize;
      if (hasNext) list.removeLast();

      rows = list;
    } catch (e) {
      _toast('Load error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2100, 1, 1),
    );
    if (picked == null) return;

    setState(() {
      _from = picked;
      if (_to.isBefore(_from)) _to = _from;
      page = 0;
    });
    await _load();
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2100, 1, 1),
    );
    if (picked == null) return;

    setState(() {
      _to = picked;
      if (_to.isBefore(_from)) _from = _to;
      page = 0;
    });
    await _load();
  }

  String _formatDt(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  double _sumFinal() {
    double s = 0;
    for (final t in rows) {
      final v = t['final_amount'];
      if (v is num) {
        s += v.toDouble();
      } else {
        s += double.tryParse(v?.toString() ?? '0') ?? 0;
      }
    }
    return s;
  }

  Future<void> _exportCsv() async {
    if (rows.isEmpty) {
      _toast('No data to export');
      return;
    }

    final buf = StringBuffer();
    buf.writeln(
      'ticket_no,created_at,payment_mode,subtotal,discount_amount,final_amount,staff,items',
    );

    for (final t in rows) {
      final ticketNo = (t['ticket_no'] ?? '').toString().replaceAll(',', ' ');
      final createdAt = _formatDt(
        (t['created_at'] ?? '').toString(),
      ).replaceAll(',', ' ');
      final payment = (t['payment_mode'] ?? '').toString().replaceAll(',', ' ');
      final subtotal = (t['subtotal'] ?? 0).toString();
      final discount = (t['discount_amount'] ?? 0).toString();
      final finalAmt = (t['final_amount'] ?? 0).toString();
      final staff = (t['staff_username'] ?? '').toString().replaceAll(',', ' ');
      final items = (t['items'] ?? '').toString().replaceAll(',', ' ');

      buf.writeln(
        '$ticketNo,$createdAt,$payment,$subtotal,$discount,$finalAmt,$staff,"$items"',
      );
    }

    final csv = buf.toString();

    try {
      final dir = await getDownloadsDirectory();
      final downloads = dir ?? await getApplicationDocumentsDirectory();
      final fileName =
          'ticket_report_${branchCode}_${_from.year}${_from.month}${_from.day}_to_${_to.year}${_to.month}${_to.day}.csv';
      final file = File('${downloads.path}/$fileName');
      await file.writeAsString(csv);

      await Clipboard.setData(ClipboardData(text: file.path));
      _toast('CSV saved: $fileName (Path copied)');
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: csv));
      _toast('CSV clipboard me copy ho gaya. Save fail: $e');
    }
  }

  Future<void> _editPayment(Map<String, dynamic> ticket) async {
    final ticketNo = (ticket['ticket_no'] ?? '').toString();
    String selected = (ticket['payment_mode'] ?? ticket['payment_method'] ?? 'Pending')
        .toString();

    const allowed = ['Cash', 'UPI', 'Card', 'Pending'];
    if (!allowed.contains(selected)) selected = 'Pending';

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Payment Mode • $ticketNo'),
          content: DropdownButtonFormField<String>(
            value: selected,
            decoration: const InputDecoration(
              labelText: 'Payment Mode',
              border: OutlineInputBorder(),
            ),
            items: allowed
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(e),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setD(() => selected = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await supabase
          .from('tickets')
          .update({
            'payment_mode': result,
            'payment_method': result,
          })
          .eq('ticket_no', ticketNo)
          .eq('branch_code', branchCode!);

      await _load();
      _toast('Payment updated: $ticketNo → $result');
    } catch (e) {
      _toast('Payment update error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (branchCode == null) ? widget.branch : '$branchCode';

    return Scaffold(
      appBar: AppBar(
        title: Text('Ticket Report • $title'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: (loading || !_isAdmin) ? null : _exportCsv,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : branchId == null
          ? const Center(child: Text('Branch not configured'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Branch: $branchName ($branchCode)'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.date_range),
                                label: Text(
                                  'From: ${_from.year}-${_from.month}-${_from.day}',
                                ),
                                onPressed: _pickFrom,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.date_range),
                                label: Text(
                                  'To: ${_to.year}-${_to.month}-${_to.day}',
                                ),
                                onPressed: _pickTo,
                              ),
                              DropdownButton<String>(
                                value: _payment,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'ALL',
                                    child: Text('Payment: ALL'),
                                  ),
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
                                    value: 'Pending',
                                    child: Text('Pending'),
                                  ),
                                ],
                                onChanged: (v) async {
                                  setState(() {
                                    _payment = v ?? 'ALL';
                                    page = 0;
                                  });
                                  await _load();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Showing: ${rows.length} tickets | Page: ${page + 1} | Total (this page): ₹${_sumFinal().toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ✅ ONE-LINE ROWS
                Expanded(
                  child: rows.isEmpty
                      ? const Center(child: Text('No tickets found'))
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final t = rows[i];

                            final ticketNo = (t['ticket_no'] ?? '').toString();
                            final createdAt = _formatDt(
                              (t['created_at'] ?? '').toString(),
                            );
                            final payment = (t['payment_mode'] ?? '')
                                .toString();
                            final finalAmt = (t['final_amount'] ?? 0)
                                .toString();
                            final discount = (t['discount_amount'] ?? 0)
                                .toString();
                            final staff = (t['staff_username'] ?? '')
                                .toString();
                            final itemsText = (t['items'] ?? '').toString();

                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$createdAt | $ticketNo | $payment | ₹$finalAmt | Disc ₹$discount | $itemsText | $staff',
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => _editPayment(t),
                                    icon: const Icon(Icons.payments_outlined, size: 18),
                                    label: const Text('Edit Payment'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: (page == 0 || loading)
                            ? null
                            : () async {
                                setState(() => page--);
                                await _load();
                              },
                        child: const Text('Prev'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: (!hasNext || loading)
                            ? null
                            : () async {
                                setState(() => page++);
                                await _load();
                              },
                        child: const Text('Next'),
                      ),
                      const Spacer(),
                      Text('Page ${page + 1}'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
