import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgentsPage extends StatefulWidget {
  final String branchCode;

  const AgentsPage({
    super.key,
    required this.branchCode,
  });

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _agents = [];
  String _search = '';

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

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  List<Map<String, dynamic>> get _filteredAgents {
    if (_search.trim().isEmpty) return _agents;

    final q = _search.trim().toLowerCase();
    return _agents.where((a) {
      final name = (a['agent_name'] ?? '').toString().toLowerCase();
      final code = (a['agent_code'] ?? '').toString().toLowerCase();
      final mobile = (a['mobile'] ?? a['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || mobile.contains(q);
    }).toList();
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

  Widget _buildSearchBox() {
    return TextField(
      decoration: const InputDecoration(
        labelText: 'Search agent',
        hintText: 'Name / Code / Mobile',
        prefixIcon: Icon(Icons.search),
        border: OutlineInputBorder(),
      ),
      onChanged: (v) {
        setState(() => _search = v);
      },
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final rows = _filteredAgents;

    if (rows.isEmpty) {
      return const Center(
        child: Text('No agents found'),
      );
    }

    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final a = rows[index];
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
            title: Text(name.isEmpty ? '-' : name),
            subtitle: Text(
              'Code: ${code.isEmpty ? "-" : code}\nMobile: ${mobile.isEmpty ? "-" : mobile}\nStatus: ${active ? "Active" : "Inactive"}',
            ),
            isThreeLine: true,
            trailing: Icon(
              active ? Icons.check_circle : Icons.cancel,
              color: active ? Colors.green : Colors.red,
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
        title: Text('Agents • ${widget.branchCode}'),
        actions: [
          IconButton(
            onPressed: _loadAgents,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopCard(),
            const SizedBox(height: 12),
            _buildSearchBox(),
            const SizedBox(height: 12),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }
}