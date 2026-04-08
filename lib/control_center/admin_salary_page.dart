import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSalaryPage extends StatefulWidget {
  const AdminSalaryPage({super.key});

  @override
  State<AdminSalaryPage> createState() => _AdminSalaryPageState();
}

class _AdminSalaryPageState extends State<AdminSalaryPage> {
  final supabase = Supabase.instance.client;

  double totalSalary = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future load() async {
    final res = await supabase.from('salary').select();

    double sum = 0;
    for (var r in res) {
      sum += (r['amount'] ?? 0);
    }

    setState(() {
      totalSalary = sum.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Salary")),
      body: Center(
        child: Text(
          "Total Salary Paid: ₹$totalSalary",
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}