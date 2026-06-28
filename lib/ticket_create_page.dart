import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ticket_printing.dart';

class TicketCreatePage extends StatefulWidget {
  final String username;
  final String branch;

  const TicketCreatePage({
    required this.username,
    required this.branch,
    super.key,
  });

  @override
  State<TicketCreatePage> createState() => _TicketCreatePageState();
}

class _TicketCreatePageState extends State<TicketCreatePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;

  String? branchCode;
  String? branchId;

  List<Map<String, dynamic>> availableItems = [];
  final List<_Line> rows = [];

  String discountType = 'amount';
  String paymentMode = 'Cash';

  final TextEditingController _discountCtl = TextEditingController(text: '0');
  final FocusNode _saveFocus = FocusNode();

  String? _previewTicketNo;

  @override
  void initState() {
    super.initState();
    rows.add(_Line());
    _init(resetForm: true);
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.dispose();
    }
    _discountCtl.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _resetFormOnly() {
    for (final r in rows) {
      r.dispose();
    }
    rows.clear();
    rows.add(_Line());
    discountType = 'amount';
    paymentMode = 'Cash';
    _discountCtl.text = '0';
  }

  String _norm(String s) => s.trim().toUpperCase();

  String _normNameLoose(String s) {
    var x = s.trim();
    x = x.replaceAll('_', ' ');
    x = x.replaceAll('-', ' ');
    x = x.replaceAll(RegExp(r'\s+'), ' ');
    return x.trim();
  }

  Future<Map<String, dynamic>?> _findBranchByCodeOrName(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final codeGuess = _norm(raw);
    final nameGuessLoose = _normNameLoose(raw);

    final byCode = await _supabase
        .from('branches')
        .select('id, code, name')
        .eq('code', codeGuess)
        .maybeSingle();
    if (byCode != null) return Map<String, dynamic>.from(byCode);

    final byNameExact = await _supabase
        .from('branches')
        .select('id, code, name')
        .eq('name', nameGuessLoose)
        .maybeSingle();
    if (byNameExact != null) return Map<String, dynamic>.from(byNameExact);

    final patterns = <String>{
      '%$nameGuessLoose%',
      '%${nameGuessLoose.replaceAll(' ', '')}%',
    }.toList();

    for (final p in patterns) {
      final list = await _supabase
          .from('branches')
          .select('id, code, name')
          .ilike('name', p)
          .limit(1);

      if (list is List && list.isNotEmpty) {
        return Map<String, dynamic>.from(list.first);
      }
    }

    return null;
  }

  Future<void> _init({bool resetForm = false}) async {
    setState(() => _loading = true);

    try {
      final input = widget.branch.trim();

      if (resetForm) _resetFormOnly();

      if (_norm(input) == 'ALL' || input.isEmpty) {
        branchId = null;
        branchCode = 'ALL';
        availableItems = [];
        _previewTicketNo = null;
        return;
      }

      final branchRow = await _findBranchByCodeOrName(input);

      if (branchRow == null) {
        branchId = null;
        branchCode = input;
        availableItems = [];
        _previewTicketNo = null;
        _toast('Branch not found: "$input"');
        return;
      }

      branchId = (branchRow['id'] ?? '').toString();
      branchCode = (branchRow['code'] ?? '').toString().toUpperCase().trim();

      final items = await _supabase
          .from('items')
          .select('id, code, name, price, branch_id, is_active')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .order('code', ascending: true);

      availableItems = List<Map<String, dynamic>>.from(items);
      _previewTicketNo =
          await _generateNextTicketNo(branchCode!, DateTime.now());
    } catch (e) {
      _toast('Init error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      await Future.delayed(const Duration(milliseconds: 120));
      if (mounted && rows.isNotEmpty) {
        FocusScope.of(context).requestFocus(rows.first.codeFocus);
      }
    }
  }

  bool get _canUseItems =>
      !_loading && branchId != null && availableItems.isNotEmpty;

  bool get _hasValidSelection {
    if (branchId == null || branchCode == null || branchCode == 'ALL') {
      return false;
    }

    final selectedRows = rows.where((r) => r.selectedItemId != null).toList();
    if (selectedRows.isEmpty) return false;

    for (final r in selectedRows) {
      final q = r.qty;
      if (q == null || q < 1) return false;
    }
    return true;
  }

  double get subtotal => rows.fold(0.0, (sum, r) => sum + (r.lineTotal ?? 0.0));

  double get discountValue =>
      double.tryParse(_discountCtl.text.trim()) ?? 0.0;

  double get discountAmount {
    if (discountType == 'percent') {
      final v = subtotal * (discountValue / 100.0);
      return v < 0 ? 0 : v;
    }
    return discountValue < 0 ? 0 : discountValue;
  }

  double get finalAmount {
    final v = subtotal - discountAmount;
    return v < 0 ? 0 : v;
  }

  void _addRow() {
    setState(() => rows.add(_Line()));
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(rows.last.codeFocus);
    });
  }

  void _removeRow(int i) {
    setState(() {
      if (rows.length > 1) {
        rows[i].dispose();
        rows.removeAt(i);
      }
    });
  }

  String _ymd(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y$m$day';
  }

  Future<String> _generateNextTicketNo(
    String branchCodeValue,
    DateTime now,
  ) async {
    final ymd = _ymd(now);
    final prefix = '${branchCodeValue.toUpperCase()}-$ymd-';

    final data = await _supabase
        .from('tickets')
        .select('ticket_no')
        .ilike('ticket_no', '$prefix%')
        .order('ticket_no', ascending: false)
        .limit(1);

    int nextNumber = 1;

    if (data.isNotEmpty) {
      final lastTicketNo = (data.first['ticket_no'] ?? '').toString();
      final parts = lastTicketNo.split('-');
      if (parts.length >= 3) {
        final lastSeq = int.tryParse(parts.last) ?? 0;
        nextNumber = lastSeq + 1;
      }
    }

    return '$prefix${nextNumber.toString().padLeft(4, '0')}';
  }

  Future<String> _createUniqueTicketNo(
    String branchCodeValue,
    DateTime now,
  ) async {
    for (int i = 0; i < 5; i++) {
      final ticketNo = await _generateNextTicketNo(branchCodeValue, now);

      final exists = await _supabase
          .from('tickets')
          .select('id')
          .eq('ticket_no', ticketNo)
          .limit(1);

      if (exists.isEmpty) return ticketNo;

      await Future.delayed(const Duration(milliseconds: 150));
    }

    throw Exception('Unable to generate unique ticket number');
  }

  void _applySelectedItemToRow(_Line row, Map<String, dynamic> sel) {
    row.selectedItemId = (sel['id'] ?? '').toString();
    row.itemNameSnapshot = (sel['name'] ?? '').toString();
    row.unitPriceSnapshot = (sel['price'] is num)
        ? (sel['price'] as num).toDouble()
        : (double.tryParse(sel['price'].toString()) ?? 0.0);
    row.codeCtl.text = (sel['code'] ?? '').toString();
    row.qtyError = null;

    if (row.qtyCtl.text.trim().isEmpty || row.qtyCtl.text.trim() == '0') {
      row.qtyCtl.text = '1';
    }
    row.qty = int.tryParse(row.qtyCtl.text.trim()) ?? 1;
  }

  void _selectItemByCode(_Line row, String code) {
    if (!_canUseItems) return;

    final clean = code.trim();
    if (clean.isEmpty) return;

    Map<String, dynamic>? found;
    for (final it in availableItems) {
      final itemCode = (it['code'] ?? '').toString().trim();
      if (itemCode == clean) {
        found = it;
        break;
      }
    }

    if (found == null) {
      setState(() {
        row.selectedItemId = null;
        row.itemNameSnapshot = null;
        row.unitPriceSnapshot = null;
      });
      _toast('Is branch me ye item code nahi mila');
      return;
    }

    setState(() {
      _applySelectedItemToRow(row, found!);
    });

    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(row.qtyFocus);
      row.qtyCtl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: row.qtyCtl.text.length,
      );
    });
  }

  Future<void> _onSaveAndPrint() async {
    if (branchId == null || branchCode == null || branchCode == 'ALL') {
      _toast('Branch select karo (Home page se).');
      return;
    }

    bool ok = true;
    for (final r in rows) {
      if (r.selectedItemId != null) {
        final q = r.qty;
        if (q == null || q < 1) {
          ok = false;
          r.qtyError = 'Qty required (>=1)';
        } else {
          r.qtyError = null;
        }
      } else {
        r.qtyError = null;
      }
    }

    if (!ok) {
      setState(() {});
      _toast('Qty 0 ya blank nahi ho sakti');
      return;
    }

    if (!_hasValidSelection) {
      _toast('Item select karo aur Qty daalo');
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final ticketNo = await _createUniqueTicketNo(branchCode!, now);

      final ticketData = {
        'branch_id': branchId,
        'branch_code': branchCode,
        'ticket_no': ticketNo,
        'ticket_date': now.toIso8601String(),
        'created_at': now.toUtc().toIso8601String(),
        'staff_username': widget.username,
        'payment_method': paymentMode,
        'payment_mode': paymentMode,
        'subtotal': subtotal,
        'discount_type': discountType,
        'discount_value': discountValue,
        'discount_amount': discountAmount,
        'final_amount': finalAmount,
        'gst_rate': 18,
        'gst_included': true,
      };

      final insertedTicket =
          await _supabase.from('tickets').insert(ticketData).select().single();

      final ticketId = (insertedTicket['id'] ?? '').toString();

      final itemsToInsert = rows
          .where((r) => r.selectedItemId != null && (r.qty ?? 0) > 0)
          .map((r) => {
                'ticket_id': ticketId,
                'item_id': r.selectedItemId,
                'item_name_snapshot': r.itemNameSnapshot,
                'unit_price_snapshot': r.unitPriceSnapshot,
                'qty': r.qty,
                'line_total': r.lineTotal,
              })
          .toList();

      if (itemsToInsert.isNotEmpty) {
        await _supabase.from('ticket_items').insert(itemsToInsert);
      }

      final fullTicket = await _supabase
          .from('tickets')
          .select('*, ticket_items(*)')
          .eq('id', ticketId)
          .single();

      try {
        await _supabase.rpc(
          'mark_ticket_printed',
          params: {'p_ticket_id': ticketId},
        );
      } catch (_) {}

final settingsRows = await _supabase
    .from('branch_settings')
    .select('*');

print('ALL SETTINGS = $settingsRows');

final branchSettings = (settingsRows as List)
    .firstWhere(
      (r) => (r['branch_code'] ?? '').toString().trim().toUpperCase() ==
          branchCode!.trim().toUpperCase(),
      orElse: () => {},
    );

print('PDF Branch Code = ${branchCode!.trim().toUpperCase()}');
print('PDF Branch Settings = $branchSettings');

fullTicket['branch_settings'] = branchSettings ?? {};


fullTicket['created_at'] = insertedTicket['created_at'];
fullTicket['ticket_date'] = insertedTicket['created_at'];

final pdfDoc = await generateTicketPdf(
  Map<String, dynamic>.from(fullTicket),
);
      await Printing.layoutPdf(onLayout: (_) async => pdfDoc.save());

      _toast('Ticket created: $ticketNo');

      _resetFormOnly();
      rows.first.qtyCtl.text = '1';
      rows.first.qty = 1;
      _previewTicketNo =
          await _generateNextTicketNo(branchCode!, DateTime.now());

      if (mounted) {
        setState(() => _saving = false);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          FocusScope.of(context).requestFocus(rows.first.codeFocus);
        });
      }
      return;
    } on PostgrestException catch (e) {
      _toast('DB Error: ${e.message}');
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted && _saving) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _boxDec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  Widget _headerBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'Ticket No: ${_previewTicketNo ?? "Loading..."}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Branch: ${branchCode ?? widget.branch}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Date/Time: ${DateTime.now().toString().split(".").first}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineCard(_Line row, int i, bool canUse) {
    final itemText = row.itemNameSnapshot ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: row.codeCtl,
                  focusNode: row.codeFocus,
                  enabled: canUse && !_saving,
                  decoration: _boxDec('Item Code', hint: 'Code'),
                  onChanged: (value) {
                    if (value.trim().isNotEmpty) {
                      _selectItemByCode(row, value);
                    }
                  },
                  onFieldSubmitted: (value) {
                    _selectItemByCode(row, value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Container(
                  height: 46,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    itemText.isEmpty ? 'Item Name' : itemText,
                    style: TextStyle(
                      fontSize: 13,
                      color: itemText.isEmpty
                          ? Colors.grey.shade600
                          : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: row.qtyCtl,
                  focusNode: row.qtyFocus,
                  enabled: canUse && !_saving && row.selectedItemId != null,
                  decoration: _boxDec('Qty'),
                  keyboardType: TextInputType.number,
                  onTap: () {
                    row.qtyCtl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: row.qtyCtl.text.length,
                    );
                  },
                  onChanged: (v) {
                    setState(() {
                      row.qty = int.tryParse(v.trim());
                      final q = row.qty;
                      row.qtyError = (q == null || q < 1) ? 'Qty > 0' : null;
                    });
                  },
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_saveFocus);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Container(
                  height: 46,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '₹${(row.unitPriceSnapshot ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Container(
                  height: 46,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '₹${(row.lineTotal ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : () => _removeRow(i),
              ),
            ],
          ),
          if (row.qtyError != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                row.qtyError!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomSummary() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: paymentMode,
            decoration: const InputDecoration(
              labelText: 'Payment Type',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'Cash', child: Text('Cash')),
              DropdownMenuItem(value: 'UPI', child: Text('UPI')),
              DropdownMenuItem(value: 'Card', child: Text('Card')),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => paymentMode = v ?? 'Cash'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: discountType,
            decoration: const InputDecoration(
              labelText: 'Discount Type',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'amount', child: Text('Amount (₹)')),
              DropdownMenuItem(value: 'percent', child: Text('Percent (%)')),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => discountType = v ?? 'amount'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: TextFormField(
            controller: _discountCtl,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Value',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Subtotal: ₹${subtotal.toStringAsFixed(2)}'),
              Text('Discount: ₹${discountAmount.toStringAsFixed(2)}'),
              const Text('GST Inc. 18%'),
              const SizedBox(height: 4),
              Text(
                'Final: ₹${finalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canUse = _canUseItems;

    return Scaffold(
      appBar: AppBar(
        title: Text('Create Ticket • ${branchCode ?? widget.branch}'),
        actions: [
          IconButton(
            tooltip: 'Reload Items',
            icon: const Icon(Icons.refresh),
            onPressed: _saving ? null : () => _init(resetForm: true),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerBox(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) => _buildLineCard(rows[i], i, canUse),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: (canUse && !_saving) ? _addRow : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Item'),
                  ),
                  const SizedBox(height: 8),
                  _bottomSummary(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      focusNode: _saveFocus,
                      onPressed: (_saving || !_hasValidSelection)
                          ? null
                          : _onSaveAndPrint,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save & Print'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Line {
  String? selectedItemId;
  String? itemNameSnapshot;
  double? unitPriceSnapshot;

  final TextEditingController codeCtl = TextEditingController();
  final TextEditingController qtyCtl = TextEditingController(text: '1');

  final FocusNode codeFocus = FocusNode();
  final FocusNode qtyFocus = FocusNode();

  int? qty = 1;
  String? qtyError;

  double? get lineTotal {
    final q = qty ?? 0;
    return (unitPriceSnapshot ?? 0.0) * q;
  }

  void dispose() {
    codeCtl.dispose();
    qtyCtl.dispose();
    codeFocus.dispose();
    qtyFocus.dispose();
  }
}