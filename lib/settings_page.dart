import 'package:flutter/material.dart';
import 'storage.dart';
import 'pages/commission_settings_page.dart';

class SettingsPage extends StatelessWidget {
  final String username;
  final String branch;

  const SettingsPage({
    super.key,
    required this.username,
    required this.branch,
  });

  Future<bool> _confirm(BuildContext context, String msg) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirm'),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _toast(BuildContext context, String msg) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings • $branch')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Welcome $username\nBranch: $branch',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Clear Transactions'),
                      subtitle: const Text('Delete all transactions for this branch'),
                      onTap: () async {
                        final ok = await _confirm(context, 'Clear all transactions for "$branch"?');
                        if (!ok) return;
                        await Storage.clearTransactions(branch);
                        if (!context.mounted) return;
                        await _toast(context, 'Transactions cleared');
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Clear Staff'),
                      subtitle: const Text('Delete all staff for this branch'),
                      onTap: () async {
                        final ok = await _confirm(context, 'Clear all staff for "$branch"?');
                        if (!ok) return;
                        await Storage.clearStaff(branch);
                        if (!context.mounted) return;
                        await _toast(context, 'Staff cleared');
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
  leading: const Icon(Icons.percent),
  title: const Text('Commission Settings'),
  subtitle: const Text('Default rate, branch-wise commission %'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommissionSettingsPage(
          branchCode: branch,
          branchName: branch,
        ),
      ),
    );
  },
),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Clear Attendance'),
                      subtitle: const Text('Delete all attendance for this branch'),
                      onTap: () async {
                        final ok = await _confirm(context, 'Clear all attendance for "$branch"?');
                        if (!ok) return;
                        await Storage.clearAttendance(branch);
                        if (!context.mounted) return;
                        await _toast(context, 'Attendance cleared');
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.delete_forever),
                      title: const Text('Clear ALL data'),
                      subtitle: const Text('Transactions + Staff + Attendance'),
                      onTap: () async {
                        final ok = await _confirm(context, 'Clear ALL data for "$branch"?');
                        if (!ok) return;
                        await Storage.clearAllForBranch(branch);
                        if (!context.mounted) return;
                        await _toast(context, 'All data cleared');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}