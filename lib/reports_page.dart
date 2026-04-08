import 'package:flutter/material.dart';
import 'storage.dart';

class ReportsPage extends StatefulWidget {
  final String username;
  final String branch;

  const ReportsPage({
    super.key,
    required this.username,
    required this.branch,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List<Map<String, dynamic>> tx = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Storage.readTransactions(widget.branch);
    if (!mounted) return;
    setState(() => tx = list);
  }

  double _sumIncome(List<Map<String, dynamic>> list) {
    double s = 0;
    for (final t in list) {
      if ((t['type'] as String?) == 'Income') {
        s += ((t['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    return s;
  }

  double _sumExpense(List<Map<String, dynamic>> list) {
    double s = 0;
    for (final t in list) {
      if ((t['type'] as String?) == 'Expense') {
        s += ((t['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    return s;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  DateTime _parseDate(String iso) => DateTime.tryParse(iso) ?? DateTime.now();

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayList = tx.where((t) => _isSameDay(_parseDate(t['date'] as String? ?? ''), today)).toList();
    final monthList = tx.where((t) => _isSameMonth(_parseDate(t['date'] as String? ?? ''), today)).toList();

    final totalIncome = _sumIncome(tx);
    final totalExpense = _sumExpense(tx);
    final net = totalIncome - totalExpense;

    final todayIncome = _sumIncome(todayList);
    final todayExpense = _sumExpense(todayList);
    final monthIncome = _sumIncome(monthList);
    final monthExpense = _sumExpense(monthList);

    // last 7 days totals
    final last7 = <DateTime>[];
    for (int i = 0; i < 7; i++) {
      last7.add(DateTime(today.year, today.month, today.day).subtract(Duration(days: i)));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Reports • ${widget.branch}')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Welcome ${widget.username}\nBranch: ${widget.branch}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard(title: 'Today Income', value: todayIncome)),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(title: 'Today Expense', value: todayExpense)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _StatCard(title: 'Month Income', value: monthIncome)),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(title: 'Month Expense', value: monthExpense)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _StatCard(title: 'Total Income', value: totalIncome)),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(title: 'Total Expense', value: totalExpense)),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(title: 'Net', value: net)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                elevation: 1,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: last7.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final day = last7[index];
                    final dayTx = tx.where((t) => _isSameDay(_parseDate(t['date'] as String? ?? ''), day)).toList();
                    final inc = _sumIncome(dayTx);
                    final exp = _sumExpense(dayTx);
                    final netDay = inc - exp;

                    return ListTile(
                      title: Text('Day: ${_fmt(day)}'),
                      subtitle: Text('Income: ${inc.toStringAsFixed(2)} • Expense: ${exp.toStringAsFixed(2)}'),
                      trailing: Text(
                        netDay.toStringAsFixed(2),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: netDay >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final double value;

  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 6),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}