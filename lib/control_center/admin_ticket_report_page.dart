import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminTicketReportPage extends StatefulWidget {
  const AdminTicketReportPage({super.key});

  @override
  State<AdminTicketReportPage> createState() =>
      _AdminTicketReportPageState();
}

class _AdminTicketReportPageState
    extends State<AdminTicketReportPage> {
  final supabase = Supabase.instance.client;

  List data = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future load() async {
    final res = await supabase.from('tickets').select();
    setState(() => data = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ticket Report")),
      body: ListView.builder(
        itemCount: data.length,
        itemBuilder: (c, i) {
          final t = data[i];
          return Card(
            child: ListTile(
              title: Text("₹${t['final_amount']}"),
              subtitle: Text(t['branch_code'] ?? ''),
            ),
          );
        },
      ),
    );
  }
}