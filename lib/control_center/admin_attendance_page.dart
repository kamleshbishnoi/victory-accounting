import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAttendancePage extends StatefulWidget {
  const AdminAttendancePage({super.key});

  @override
  State<AdminAttendancePage> createState() =>
      _AdminAttendancePageState();
}

class _AdminAttendancePageState
    extends State<AdminAttendancePage> {
  final supabase = Supabase.instance.client;

  List data = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future load() async {
    final res = await supabase.from('attendance').select();
    setState(() => data = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Attendance")),
      body: ListView.builder(
        itemCount: data.length,
        itemBuilder: (c, i) {
          final a = data[i];
          return ListTile(
            title: Text(a['staff_name'] ?? ''),
            subtitle: Text(a['date'] ?? ''),
            trailing: Text(a['status'] ?? ''),
          );
        },
      ),
    );
  }
}