import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qcenkyzayjimdunqpktv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFjZW5reXpheWppbWR1bnFwa3R2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MTM1OTEsImV4cCI6MjA4ODE4OTU5MX0.tazt8Vn0BPGnCxI0Po2WCKTkJ0EzHMhJxJT3nvGRkaw',
  );

  runApp(const VictoryApp());
}

class VictoryApp extends StatelessWidget {
  const VictoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Victory Accounting',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const LoginPage(),
    );
  }
}