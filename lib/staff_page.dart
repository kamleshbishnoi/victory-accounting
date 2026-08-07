import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffPage extends StatefulWidget {
  final String username;
  final String branch;

  const StaffPage({super.key, required this.username, required this.branch});

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _mobileCtl = TextEditingController();
  final TextEditingController _roleCtl = TextEditingController();
  final TextEditingController _salaryCtl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _resolvedBranchId;
  List<Map<String, dynamic>> _staff = [];

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _mobileCtl.dispose();
    _roleCtl.dispose();
    _salaryCtl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _staffName(Map<String, dynamic> row) {
    final a = (row['name'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;

    final b = (row['staff_name'] ?? '').toString().trim();
    if (b.isNotEmpty) return b;

    return '';
  }

  Future<void> _resolveBranchId() async {
    final byCode = await _supabase
        .from('branches')
        .select('id, code, name')
        .eq('code', widget.branch)
        .maybeSingle();

    if (byCode != null) {
      _resolvedBranchId = (byCode['id'] ?? '').toString();
      return;
    }

    final byName = await _supabase
        .from('branches')
        .select('id, code, name')
        .eq('name', widget.branch)
        .maybeSingle();

    if (byName != null) {
      _resolvedBranchId = (byName['id'] ?? '').toString();
    }
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);

    try {
      await _resolveBranchId();

      if (_resolvedBranchId == null || _resolvedBranchId!.isEmpty) {
        _staff = [];
        _toast('Branch not found');
      } else {
        final data = await _supabase
            .from('staff')
            .select()
            .eq('branch_id', _resolvedBranchId)
            .order('name', ascending: true);

        _staff = List<Map<String, dynamic>>.from(data);
      }
    } catch (e) {
      _toast('Load error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addStaff() async {
    final name = _nameCtl.text.trim();
    final mobile = _mobileCtl.text.trim();
    final role = _roleCtl.text.trim();
    final salary = double.tryParse(_salaryCtl.text.trim()) ?? 0;

    if (name.isEmpty) {
      _toast('Name required');
      return;
    }

    setState(() => _saving = true);

    try {
      await _resolveBranchId();

      if (_resolvedBranchId == null || _resolvedBranchId!.isEmpty) {
        _toast('Branch not found');
        return;
      }

      await _supabase.from('staff').insert({
        'name': name,
        'staff_name': name,
        'mobile': mobile,
        'role': role,
        'salary': salary,
        'branch_id': _resolvedBranchId,
      });

      _nameCtl.clear();
      _mobileCtl.clear();
      _roleCtl.clear();
      _salaryCtl.clear();

      await _loadStaff();
      _toast('Staff added');
    } catch (e) {
      _toast('Save error: $e');
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _editStaff(Map<String, dynamic> row) async {
    final nameCtl = TextEditingController(text: _staffName(row));
    final mobileCtl = TextEditingController(
      text: (row['mobile'] ?? '').toString(),
    );
    final roleCtl = TextEditingController(text: (row['role'] ?? '').toString());
    final salaryCtl = TextEditingController(
      text: _toDouble(row['salary']).toStringAsFixed(0),
    );

    await showDialog(
      context: context,
      builder: (context) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setD) {
            return AlertDialog(
              title: const Text('Edit Staff'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobileCtl,
                      decoration: const InputDecoration(
                        labelText: 'Mobile',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: roleCtl,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: salaryCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Salary',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final newName = nameCtl.text.trim();
                          final newMobile = mobileCtl.text.trim();
                          final newRole = roleCtl.text.trim();
                          final newSalary =
                              double.tryParse(salaryCtl.text.trim()) ?? 0;

                          if (newName.isEmpty) {
                            _toast('Name required');
                            return;
                          }

                          setD(() => saving = true);

                          try {
                            await _supabase
                                .from('staff')
                                .update({
                                  'name': newName,
                                  'staff_name': newName,
                                  'mobile': newMobile,
                                  'role': newRole,
                                  'salary': newSalary,
                                })
                                .eq('id', row['id']);

                            if (mounted) Navigator.pop(context);
                            await _loadStaff();
                            _toast('Staff updated');
                          } catch (e) {
                            _toast('Update error: $e');
                          } finally {
                            if (mounted) {
                              setD(() => saving = false);
                            }
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtl.dispose();
    mobileCtl.dispose();
    roleCtl.dispose();
    salaryCtl.dispose();
  }

  Future<void> _deleteStaff(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff'),
        content: Text('Delete ${_staffName(row)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _supabase.from('staff').delete().eq('id', row['id']);
      await _loadStaff();
      _toast('Staff deleted');
    } catch (e) {
      _toast('Delete error: $e');
    }
  }

  Widget _headerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.person)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome ${widget.username}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Branch: ${widget.branch}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _mobileCtl,
                    decoration: const InputDecoration(
                      labelText: 'Mobile',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roleCtl,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _salaryCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Salary',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _addStaff,
                icon: const Icon(Icons.add),
                label: Text(_saving ? 'Saving...' : 'Add Staff'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _staffCard(Map<String, dynamic> row) {
    final name = _staffName(row);
    final role = (row['role'] ?? '-').toString();
    final mobile = (row['mobile'] ?? '-').toString();
    final salary = _toDouble(row['salary']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Role: $role • Mobile: $mobile'),
        ),
        trailing: SizedBox(
          width: 180,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '₹${salary.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Edit',
                onPressed: () => _editStaff(row),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _deleteStaff(row),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listCard() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_staff.isEmpty) {
      return const Center(child: Text('No staff found'));
    }

    return ListView.builder(
      itemCount: _staff.length,
      itemBuilder: (context, index) => _staffCard(_staff[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Staff • ${widget.branch}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadStaff,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _headerCard(),
            _formCard(),
            const SizedBox(height: 10),
            Expanded(child: _listCard()),
          ],
        ),
      ),
    );
  }
}
