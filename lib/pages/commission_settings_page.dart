import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommissionSettingsPage extends StatefulWidget {
  final String branchCode;
  final String branchName;

  const CommissionSettingsPage({
    super.key,
    required this.branchCode,
    required this.branchName,
  });

  @override
  State<CommissionSettingsPage> createState() => _CommissionSettingsPageState();
}

class _CommissionSettingsPageState extends State<CommissionSettingsPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;

  final _labelController = TextEditingController();
  final _percentController = TextEditingController();

  List<Map<String, dynamic>> _rates = [];

  String get _branchCode => widget.branchCode.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _percentController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmt(dynamic v) => _toDouble(v).toStringAsFixed(2);

  Future<void> _loadRates() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('commission_rate_settings')
          .select()
          .eq('branch_code', _branchCode)
          .order('commission_percent', ascending: true);

      _rates = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _msg('Rates load error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addRate() async {
    final label = _labelController.text.trim();
    final percent = double.tryParse(_percentController.text.trim());

    if (label.isEmpty) {
      _msg('Rate label dalo');
      return;
    }
    if (percent == null) {
      _msg('Valid percent dalo');
      return;
    }

    setState(() => _saving = true);

    try {
      await supabase.from('commission_rate_settings').insert({
        'branch_code': _branchCode,
        'rate_label': label,
        'commission_percent': percent,
        'is_primary': false,
      });

      _labelController.clear();
      _percentController.clear();

      _msg('Rate added');
      await _loadRates();
    } catch (e) {
      _msg('Add rate error: $e');
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _setPrimary(String id) async {
    try {
      await supabase
          .from('commission_rate_settings')
          .update({'is_primary': false})
          .eq('branch_code', _branchCode);

      await supabase
          .from('commission_rate_settings')
          .update({'is_primary': true})
          .eq('id', id);

      _msg('Default rate updated');
      await _loadRates();
    } catch (e) {
      _msg('Primary set error: $e');
    }
  }

  Future<void> _deleteRate(String id) async {
    try {
      await supabase
          .from('commission_rate_settings')
          .delete()
          .eq('id', id);

      _msg('Rate deleted');
      await _loadRates();
    } catch (e) {
      _msg('Delete error: $e');
    }
  }

  void _msg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Widget _buildAddCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: const [
                Icon(Icons.settings),
                SizedBox(width: 8),
                Text(
                  'Add Commission Rate',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'Rate Label',
                      hintText: 'Example: 10 Percent',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _percentController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Commission %',
                      hintText: 'Example: 10',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _addRate,
                  icon: const Icon(Icons.add),
                  label: Text(_saving ? 'Saving...' : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateCard(Map<String, dynamic> rate) {
    final isPrimary = (rate['is_primary'] ?? false) == true;

    return Card(
      child: ListTile(
        title: Text(
          '${rate['rate_label'] ?? '-'}  •  ${_fmt(rate['commission_percent'])} %',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          isPrimary ? 'Default / Primary Rate' : 'Normal Rate',
          style: TextStyle(
            color: isPrimary ? Colors.green : Colors.grey.shade700,
            fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            if (!isPrimary)
              ElevatedButton(
                onPressed: () => _setPrimary(rate['id'].toString()),
                child: const Text('Set Default'),
              ),
            if (!isPrimary)
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _deleteRate(rate['id'].toString()),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Commission Settings • ${widget.branchName} ($_branchCode)'),
        actions: [
          IconButton(
            onPressed: _loadRates,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Colors.grey.shade100,
              child: ListTile(
                leading: const Icon(Icons.account_tree),
                title: Text('Branch: ${widget.branchName}'),
                subtitle: Text('Code: $_branchCode'),
              ),
            ),
            const SizedBox(height: 12),
            _buildAddCard(),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rates.isEmpty
                      ? const Center(child: Text('No commission rates found'))
                      : ListView.separated(
                          itemCount: _rates.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            return _buildRateCard(_rates[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}