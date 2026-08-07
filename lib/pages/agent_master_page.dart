import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgentMasterPage extends StatefulWidget {
  final String branchCode;

  const AgentMasterPage({super.key, required this.branchCode});

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
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final agents = await supabase
          .from('agents')
          .select()
          .eq('branch_code', widget.branchCode)
          .order('agent_name', ascending: true);

      final fpData = await supabase
          .from('agent_fingerprints')
          .select('agent_id, active')
          .eq('branch_code', widget.branchCode)
          .eq('active', true);

      final fpAgentIds = List<Map<String, dynamic>>.from(
        fpData,
      ).map((e) => e['agent_id'].toString()).toSet();

      final loadedAgents = List<Map<String, dynamic>>.from(agents);

      for (final agent in loadedAgents) {
        agent['finger_registered'] = fpAgentIds.contains(
          agent['id'].toString(),
        );
      }

      _agents = loadedAgents;
    } catch (e) {
      _showMsg('Agents load error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _nextAgentCode() {
    if (_agents.isEmpty) return 'AG001';

    int maxNo = 0;

    for (final agent in _agents) {
      final code = (agent['agent_code'] ?? '').toString().trim().toUpperCase();

      final match = RegExp(r'AG(\d+)').firstMatch(code);

      if (match != null) {
        final number = int.tryParse(match.group(1) ?? '0') ?? 0;

        if (number > maxNo) {
          maxNo = number;
        }
      }
    }

    return 'AG${(maxNo + 1).toString().padLeft(3, '0')}';
  }

  Future<void> _openAgentForm({Map<String, dynamic>? agent}) async {
    final isEdit = agent != null;

    final nameCtrl = TextEditingController(
      text: (agent?['agent_name'] ?? '').toString(),
    );

    final mobileCtrl = TextEditingController(
      text: (agent?['mobile'] ?? '').toString(),
    );

    final phoneCtrl = TextEditingController(
      text: (agent?['phone'] ?? '').toString(),
    );

    final codeCtrl = TextEditingController(
      text: isEdit ? (agent?['agent_code'] ?? '').toString() : _nextAgentCode(),
    );

    bool active = (agent?['active'] ?? true) == true;
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
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
                        onChanged: saving
                            ? null
                            : (value) {
                                setLocalState(() {
                                  active = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.fingerprint),
                                SizedBox(width: 8),
                                Text(
                                  'Fingerprint',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              !isEdit
                                  ? 'Status: Save agent first'
                                  : (agent?['finger_registered'] ?? false) == true
                                      ? 'Status: Registered'
                                      : 'Status: Not Registered',
                              style: TextStyle(
                                color: !isEdit
                                    ? Colors.orange.shade800
                                    : (agent?['finger_registered'] ?? false) == true
                                        ? Colors.green.shade800
                                        : Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!isEdit) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Pehle agent Save karo. Save ke baad Edit Agent me fingerprint enrollment enable hoga.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: !isEdit
                                    ? null
                                    : () {
                                        _showMsg(
                                          'Agent saved hai. Mantra fingerprint enrollment integration ke liye ready.',
                                        );
                                      },
                                icon: const Icon(Icons.fingerprint),
                                label: Text(
                                  !isEdit
                                      ? 'Save Agent First'
                                      : (agent?['finger_registered'] ?? false) == true
                                          ? 'Re-Enroll Fingerprint'
                                          : 'Enroll Fingerprint',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                        },
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

                          setLocalState(() {
                            saving = true;
                          });

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

                            if (mounted && Navigator.canPop(dialogContext)) {
                              Navigator.pop(dialogContext);
                            }

                            await _loadAgents();
                          } catch (e) {
                            _showMsg('Save error: $e');

                            setLocalState(() {
                              saving = false;
                            });
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

    nameCtrl.dispose();
    mobileCtrl.dispose();
    phoneCtrl.dispose();
    codeCtrl.dispose();
  }

  Future<void> _toggleActive(Map<String, dynamic> agent) async {
    try {
      final current = (agent['active'] ?? true) == true;

      await supabase
          .from('agents')
          .update({'active': !current})
          .eq('id', agent['id']);

      _showMsg(!current ? 'Agent activated' : 'Agent deactivated');

      await _loadAgents();
    } catch (e) {
      _showMsg('Status update error: $e');
    }
  }

  void _showMsg(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTopCard() {
    final total = _agents.length;

    final activeCount = _agents
        .where((agent) => (agent['active'] ?? true) == true)
        .length;

    final inactiveCount = total - activeCount;

    final fingerprintCount = _agents
        .where((agent) => (agent['finger_registered'] ?? false) == true)
        .length;

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
            Text(
              'Fingerprints: $fingerprintCount',
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
      return const Center(child: Text('No agents found'));
    }

    return ListView.separated(
      itemCount: _agents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final agent = _agents[index];

        final name = (agent['agent_name'] ?? '').toString();

        final code = (agent['agent_code'] ?? '').toString();

        final mobile = (agent['mobile'] ?? agent['phone'] ?? '').toString();

        final active = (agent['active'] ?? true) == true;

        final fingerRegistered = (agent['finger_registered'] ?? false) == true;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'A'),
            ),
            title: Text('$name (${code.isEmpty ? "-" : code})'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Mobile: ${mobile.isEmpty ? "-" : mobile}\n'
                'Status: ${active ? "Active" : "Inactive"}\n'
                'Fingerprint: ${fingerRegistered ? "Registered" : "Not Registered"}',
              ),
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                  message: fingerRegistered
                      ? 'Fingerprint Registered'
                      : 'Fingerprint Not Registered',
                  child: Icon(
                    fingerRegistered
                        ? Icons.fingerprint
                        : Icons.fingerprint_outlined,
                    color: fingerRegistered ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () {
                    _openAgentForm(agent: agent);
                  },
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: active ? 'Deactivate' : 'Activate',
                  onPressed: () {
                    _toggleActive(agent);
                  },
                  icon: Icon(
                    active ? Icons.toggle_on : Icons.toggle_off,
                    size: 30,
                    color: active ? Colors.green : Colors.grey,
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
            tooltip: 'Refresh',
            onPressed: _loadAgents,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _openAgentForm();
        },
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
