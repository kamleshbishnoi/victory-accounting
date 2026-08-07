import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalaryPage extends StatefulWidget {
  final String branch;

  const SalaryPage({super.key, required this.branch});

  @override
  State<SalaryPage> createState() => _SalaryPageState();
}

class _SalaryPageState extends State<SalaryPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  DateTime selectedMonth = DateTime.now();
  bool loading = true;

  String? _resolvedBranchId;

  List<Map<String, dynamic>> salaryData = [];

  double totalNetPayable = 0;
  double totalAdvance = 0;
  double totalPaid = 0;
  double totalRemaining = 0;

  String fmtMonth(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}";
  }

  String fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  double toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String money(dynamic v) => '₹${toDouble(v).toStringAsFixed(0)}';

  String _staffName(Map<String, dynamic> row) {
    final a = (row['name'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    final b = (row['staff_name'] ?? '').toString().trim();
    if (b.isNotEmpty) return b;
    return '';
  }

  Future<void> _resolveBranchId() async {
    final byCode = await supabase
        .from('branches')
        .select('id, code, name')
        .eq('code', widget.branch)
        .maybeSingle();

    if (byCode != null) {
      _resolvedBranchId = (byCode['id'] ?? '').toString();
      return;
    }

    final byName = await supabase
        .from('branches')
        .select('id, code, name')
        .eq('name', widget.branch)
        .maybeSingle();

    if (byName != null) {
      _resolvedBranchId = (byName['id'] ?? '').toString();
    }
  }

  @override
  void initState() {
    super.initState();
    loadSalary();
  }

  Future<void> loadSalary() async {
    setState(() => loading = true);

    final start = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final end = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);

    try {
      await _resolveBranchId();

      if (_resolvedBranchId == null || _resolvedBranchId!.isEmpty) {
        setState(() {
          salaryData = [];
          totalNetPayable = 0;
          totalAdvance = 0;
          totalPaid = 0;
          totalRemaining = 0;
          loading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Branch not found')));
        }
        return;
      }

      final staff = await supabase
          .from('staff')
          .select()
          .eq('branch_id', _resolvedBranchId)
          .order('name', ascending: true);

      final attendance = await supabase
          .from('attendance')
          .select()
          .eq('branch_code', widget.branch)
          .gte('att_date', fmtDate(start))
          .lte('att_date', fmtDate(end));

      final transactions = await supabase
          .from('transactions')
          .select()
          .eq('branch_code', widget.branch)
          .gte('tx_date', fmtDate(start))
          .lte('tx_date', fmtDate(end));

      final Map<String, Map<String, dynamic>> result = {};

      for (final s in staff) {
        final name = _staffName(s);
        if (name.isEmpty) continue;

        result[name.trim().toLowerCase()] = {
          'staff_id': (s['id'] ?? '').toString(),
          'staff_name': name,
          'salary': toDouble(s['salary']),
          'present_days': 0.0,
          'paid_off_days': 0.0,
          'late_count': 0,
          'advance': 0.0,
          'paid': 0.0,
          'net_salary': 0.0,
          'remaining': 0.0,
        };
      }

      for (final a in attendance) {
        final name = (a['staff_name'] ?? '').toString().trim().toLowerCase();
        if (!result.containsKey(name)) continue;

        final fraction = toDouble(a['day_fraction']);
        final status = (a['status'] ?? '').toString();
        final isLate = a['late_mark'] == true;

        result[name]!['present_days'] =
            toDouble(result[name]!['present_days']) + fraction;

        if (status == 'Paid Off') {
          result[name]!['paid_off_days'] =
              toDouble(result[name]!['paid_off_days']) + 1;
        }

        if (isLate) {
          result[name]!['late_count'] =
              ((result[name]!['late_count'] ?? 0) as int) + 1;
        }
      }

      for (final tx in transactions) {
        final category = (tx['category'] ?? '').toString().trim();
        final amount = toDouble(tx['amount']);
        final staffName =
            (tx['staff_name'] ?? tx['person_name'] ?? tx['person'] ?? '')
                .toString()
                .trim()
                .toLowerCase();

        if (staffName.isEmpty || !result.containsKey(staffName)) continue;

        if (category == 'Salary Advance') {
          result[staffName]!['advance'] =
              toDouble(result[staffName]!['advance']) + amount;
        }

        if (category == 'Salary Paid') {
          result[staffName]!['paid'] =
              toDouble(result[staffName]!['paid']) + amount;
        }
      }

      final List<Map<String, dynamic>> finalList = [];
      final int totalDays = end.day;

      double sumNet = 0;
      double sumAdvance = 0;
      double sumPaid = 0;
      double sumRemaining = 0;

      result.forEach((_, value) {
        final monthlySalary = toDouble(value['salary']);
        final presentDays = toDouble(value['present_days']);
        final lateCount = (value['late_count'] ?? 0) as int;
        final advance = toDouble(value['advance']);
        final paid = toDouble(value['paid']);

        final perDay = totalDays == 0 ? 0 : (monthlySalary / totalDays);

        // 3 late = 1 day deduction
        final latePenaltyDays = lateCount ~/ 3;
        final payableDays = (presentDays - latePenaltyDays).clamp(0, 31);

        final netSalary = perDay * payableDays;
        final remaining = netSalary - advance - paid;

        final row = {
          ...value,
          'month': fmtMonth(selectedMonth),
          'total_days': totalDays,
          'per_day_salary': perDay,
          'late_penalty_days': latePenaltyDays,
          'payable_days': payableDays,
          'net_salary': netSalary,
          'remaining': remaining,
        };

        sumNet += netSalary;
        sumAdvance += advance;
        sumPaid += paid;
        sumRemaining += remaining;

        finalList.add(row);
      });

      finalList.sort(
        (a, b) => (a['staff_name'] ?? '').toString().compareTo(
          (b['staff_name'] ?? '').toString(),
        ),
      );

      setState(() {
        salaryData = finalList;
        totalNetPayable = sumNet;
        totalAdvance = sumAdvance;
        totalPaid = sumPaid;
        totalRemaining = sumRemaining;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Salary load error: $e')));
      }
    }
  }

  Future<void> pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      setState(() => selectedMonth = picked);
      await loadSalary();
    }
  }

  Widget topBox(String title, String value) {
    return Container(
      width: 135,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget buildRow(Map<String, dynamic> e) {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text((e['staff_name'] ?? '').toString())),
          Expanded(child: Text(money(e['salary']))),
          Expanded(child: Text(toDouble(e['payable_days']).toStringAsFixed(2))),
          Expanded(child: Text('${e['late_count'] ?? 0}')),
          Expanded(child: Text(money(e['net_salary']))),
          Expanded(child: Text(money(e['remaining']))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Salary • ${widget.branch}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: pickMonth,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: loadSalary),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      topBox('Month', fmtMonth(selectedMonth)),
                      topBox('Branch', widget.branch),
                      topBox('Staff', '${salaryData.length}'),
                      topBox('Net Payable', money(totalNetPayable)),
                      topBox('Advance', money(totalAdvance)),
                      topBox('Paid', money(totalPaid)),
                      topBox('Remaining', money(totalRemaining)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: const [
                      Expanded(flex: 3, child: Text("Name")),
                      Expanded(child: Text("Salary")),
                      Expanded(child: Text("Days")),
                      Expanded(child: Text("Late")),
                      Expanded(child: Text("Net")),
                      Expanded(child: Text("Remain")),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: salaryData.isEmpty
                        ? const Center(child: Text('No salary data found'))
                        : ListView.builder(
                            itemCount: salaryData.length,
                            itemBuilder: (c, i) => buildRow(salaryData[i]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
