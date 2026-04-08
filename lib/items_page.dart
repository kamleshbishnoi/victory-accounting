import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ItemsPage extends StatefulWidget {
  final String branch;
  const ItemsPage({super.key, required this.branch});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  String? branchId;
  String? branchCode;
  String? branchName;

  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _load();
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

    final patterns = <String>{
      '%$nameGuessLoose%',
      '%${nameGuessLoose.replaceAll(' ', '')}%',
    }.toList();

    for (final p in patterns) {
      final list = await supabase
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

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final input = widget.branch.trim();

      if (_norm(input) == 'ALL' || input.isEmpty) {
        branchId = null;
        branchCode = 'ALL';
        branchName = 'ALL';
        items = [];
        _toast('ALL mode me items page use nahi hoga. Branch select karo.');
        return;
      }

      final b = await _findBranchByCodeOrName(input);

      if (b == null) {
        branchId = null;
        branchCode = null;
        branchName = null;
        items = [];
        _toast('Branch not found: $input');
        return;
      }

      branchId = (b['id'] ?? '').toString();
      branchCode = (b['code'] ?? '').toString().toUpperCase().trim();
      branchName = (b['name'] ?? '').toString();

      final list = await supabase
          .from('items')
          .select('id, code, name, price, is_active, branch_id, created_at')
          .eq('branch_id', branchId)
          .order('code', ascending: true);

      items = List<Map<String, dynamic>>.from(list);
    } catch (e) {
      _toast('Load error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _isDuplicateCode({
    required String code,
    String? ignoreItemId,
  }) async {
    if (branchId == null) return false;

    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return false;

    final data = await supabase
        .from('items')
        .select('id')
        .eq('branch_id', branchId)
        .eq('code', cleanCode);

    final rows = List<Map<String, dynamic>>.from(data);

    if (ignoreItemId == null) return rows.isNotEmpty;

    return rows.any((r) => (r['id'] ?? '').toString() != ignoreItemId);
  }

  Future<String> _suggestNextCode() async {
    if (items.isEmpty) return '1';

    int maxNum = 0;
    for (final it in items) {
      final c = (it['code'] ?? '').toString().trim();
      final n = int.tryParse(c);
      if (n != null && n > maxNum) maxNum = n;
    }

    if (maxNum == 0) return '${items.length + 1}';
    return '${maxNum + 1}';
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    if (branchId == null || branchCode == null) return;

    final codeCtl = TextEditingController(
      text: existing?['code']?.toString() ?? await _suggestNextCode(),
    );
    final nameCtl = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );
    final priceCtl = TextEditingController(
      text: (existing?['price'] ?? 0).toString(),
    );

    bool isActive =
        existing?['is_active'] == null ? true : (existing?['is_active'] as bool);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            existing == null
                ? 'Add Item • $branchCode'
                : 'Edit Item • $branchCode',
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtl,
                  decoration: const InputDecoration(
                    labelText: 'Item Code',
                    border: OutlineInputBorder(),
                    hintText: '1, 2, 3, 101...',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: isActive,
                  onChanged: (v) => setD(() => isActive = v),
                  title: const Text('Active'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeCtl.text.trim();
                final name = nameCtl.text.trim();
                final price = double.tryParse(priceCtl.text.trim()) ?? 0;

                if (code.isEmpty) {
                  _toast('Item code required');
                  return;
                }
                if (name.isEmpty) {
                  _toast('Name required');
                  return;
                }
                if (price <= 0) {
                  _toast('Price 0 se zyada hona chahiye');
                  return;
                }

                try {
                  final duplicate = await _isDuplicateCode(
                    code: code,
                    ignoreItemId: existing?['id']?.toString(),
                  );

                  if (duplicate) {
                    _toast('Same branch me same code already hai');
                    return;
                  }

                  if (existing == null) {
                    await supabase.from('items').insert({
                      'branch_id': branchId,
                      'code': code,
                      'name': name,
                      'price': price,
                      'is_active': isActive,
                    });
                  } else {
                    await supabase
                        .from('items')
                        .update({
                          'code': code,
                          'name': name,
                          'price': price,
                          'is_active': isActive,
                        })
                        .eq('id', existing['id'])
                        .eq('branch_id', branchId);
                  }

                  if (mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  _toast('Save error: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> it) async {
    try {
      await supabase
          .from('items')
          .delete()
          .eq('id', it['id'])
          .eq('branch_id', branchId);
      await _load();
    } catch (e) {
      _toast('Delete error: $e');
    }
  }

  Widget _itemCard(Map<String, dynamic> it) {
    final code = (it['code'] ?? '').toString();
    final name = (it['name'] ?? '').toString();
    final price = (it['price'] ?? 0).toString();
    final active = it['is_active'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (code.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  code,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('₹$price • ${active ? "Active" : "Inactive"}'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _addOrEdit(existing: it),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _delete(it),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (branchCode == null) ? widget.branch : branchCode!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ticket Items • $title'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: branchId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : branchId == null
              ? const Center(child: Text('Branch not configured'))
              : items.isEmpty
                  ? const Center(
                      child: Text('No items yet. + दबाकर item add करो.'),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (_, i) => _itemCard(items[i]),
                          ),
                        ),
                      ],
                    ),
    );
  }
}