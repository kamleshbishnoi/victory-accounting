import 'package:flutter/material.dart';
import 'storage.dart';

class BranchesPage extends StatelessWidget {
  const BranchesPage({super.key});

  static const List<String> branches = <String>[
  'vcc',
  'udaipur',
  'jaipur',
  'mount abu',
  'jaisalmer',
  'illusion',
  'mayalok',
  'nathdwara',
];

  String _label(String b) {
    if (b.toLowerCase() == 'vcc') return 'Victory Control Center';
    return b;
  }

  Future<void> _select(BuildContext context, String branch) async {
    await Storage.setSelectedBranch(branch);
    if (!context.mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branches')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: branches.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final b = branches[index];
          return ListTile(
            title: Text(_label(b)),
            subtitle: Text(
              'ID: ${b.toLowerCase() == 'vcc' ? 'VCC' : 'B$index'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _select(context, b),
          );
        },
      ),
    );
  }
}
