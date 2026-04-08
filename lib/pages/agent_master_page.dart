import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgentMasterPage extends StatefulWidget {
  final String branchCode;

  const AgentMasterPage({
    super.key,
    required this.branchCode,
  });

  @override
  State<AgentMasterPage> createState() => _AgentMasterPageState();
}

class _AgentMasterPageState extends State<AgentMasterPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _agents = [];

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('agents')
          .select()
          .eq('branch_code', widget.branchCode)
          .order('agent_name', ascending: true);

      _agents = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _showMsg('Agents load error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _nextAgentCode() {
    if (_agents.isEmpty) return 'AG001';

    int maxNo = 0;
    for (final a in _agents) {
      final code = (a['agent_code'] ?? '').toString().trim().toUpperCase();
      final match = RegExp(r'AG(\d+)').firstMatch(code);
      if (match != null) {
        final n = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (n > maxNo) maxNo = n;
      }
    }
    return 'AG${(maxNo + 1).toString().padLeft(3, '0')}';
  }

  Future<void> _openAgentForm({Map<String, dynamic>? agent}) async {
    final isEdit = agent != null;

    final nameCtrl =
        TextEditingController(text: (agent?['agent_name'] ?? '').toString());
    final mobileCtrl =
        TextEditingController(text: (agent?['mobile'] ?? '').toString());
    final phoneCtrl =
        TextEditingController(text: (agent?['phone'] ?? '').toString());
    final codeCtrl = TextEditingController(
      text: isEdit
          ? (agent?['agent_code'] ?? '').toString()
          : _nextAgentCode(),
    );

    bool active = (agent?['active'] ?? true) == true;
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Agent' : 'Add Agent'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Agent Name *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Agent Code *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mobileCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active'),
                        value: active,
                        onChanged: (v) => setLocal(() => active = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final code = codeCtrl.text.trim().toUpperCase();
                          final mobile = mobileCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();

                          if (name.isEmpty) {
                            _showMsg('Agent name required');
                            return;
                          }
                          if (code.isEmpty) {
                            _showMsg('Agent code required');
                            return;
                          }

                          setLocal(() => saving = true);

                          try {
                            final payload = {
                              'agent_name': name,
                              'agent_code': code,
                              'mobile': mobile.isEmpty ? null : mobile,
                              'phone': phone.isEmpty ? null : phone,
                              'active': active,
                              'branch_code': widget.branchCode,
                            };

                            if (isEdit) {
                              await supabase
                                  .from('agents')
                                  .update(payload)
                                  .eq('id', agent['id']);
                              _showMsg('Agent updated');
                            } else {
                              await supabase.from('agents').insert(payload);
                              _showMsg('Agent added');
                            }

                            if (mounted) Navigator.pop(ctx);
                            await _loadAgents();
                          } catch (e) {
                            _showMsg('Save error: $e');
                            setLocal(() => saving = false);
                          }
                        },
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> agent) async {
    try {
      final current = (agent['active'] ?? true) == true;
      await supabase
          .from('agents')
          .update({'active': !current}).eq('id', agent['id']);
      _showMsg(!current ? 'Agent activated' : 'Agent deactivated');
      await _loadAgents();
    } catch (e) {
      _showMsg('Status update error: $e');
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Widget _buildTopCard() {
    final total = _agents.length;
    final activeCount =
        _agents.where((e) => (e['active'] ?? true) == true).length;
    final inactiveCount = total - activeCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            Text(
              'Branch: ${widget.branchCode}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'Total Agents: $total',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'Active: $activeCount',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'Inactive: $inactiveCount',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_agents.isEmpty) {
      return const Center(
        child: Text('No agents found'),
      );
    }

    return ListView.separated(
      itemCount: _agents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final a = _agents[index];
        final name = (a['agent_name'] ?? '').toString();
        final code = (a['agent_code'] ?? '').toString();
        final mobile = (a['mobile'] ?? a['phone'] ?? '').toString();
        final active = (a['active'] ?? true) == true;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'A',
              ),
            ),
            title: Text('$name (${code.isEmpty ? "-" : code})'),
            subtitle: Text(
              'Mobile: ${mobile.isEmpty ? "-" : mobile}\nStatus: ${active ? "Active" : "Inactive"}',
            ),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 8,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => _openAgentForm(agent: a),
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: active ? 'Deactivate' : 'Activate',
                  onPressed: () => _toggleActive(a),
                  icon: Icon(
                    active ? Icons.toggle_on : Icons.toggle_off,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Master'),
        actions: [
          IconButton(
            onPressed: _loadAgents,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAgentForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Agent'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopCard(),
            const SizedBox(height: 12),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }
}