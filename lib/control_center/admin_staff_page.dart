import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminStaffPage extends StatefulWidget {
  const AdminStaffPage({super.key});

  @override
  State<AdminStaffPage> createState() => _AdminStaffPageState();
}

class _AdminStaffPageState extends State<AdminStaffPage> {
  final supabase = Supabase.instance.client;
  List data = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future load() async {
    final res = await supabase.from('staff').select();
    setState(() {
      data = res;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Staff")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: data.length,
              itemBuilder: (c, i) {
                final s = data[i];
                return Card(
                  child: ListTile(
                    title: Text(s['name'] ?? ''),
                    subtitle: Text("Salary: ₹${s['salary'] ?? 0}"),
                  ),
                );
              },
            ),
    );
  }
}