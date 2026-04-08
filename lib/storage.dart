import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static const String keySelectedBranch = 'selected_branch';

  static String keyTransactions(String branch) => 'transactions_$branch';
  static String keyStaff(String branch) => 'staff_$branch';
  static String keyAttendance(String branch) => 'attendance_$branch';

  // Branch
  static Future<String> getSelectedBranch() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(keySelectedBranch) ?? 'ALL';
  }

  static Future<void> setSelectedBranch(String branch) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(keySelectedBranch, branch);
  }

  static Future<void> clearSelectedBranch() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(keySelectedBranch);
  }

  // ---------- Transactions ----------
  static Future<List<Map<String, dynamic>>> readTransactions(String branch) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(keyTransactions(branch));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> saveTransactions(String branch, List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(keyTransactions(branch), jsonEncode(list));
  }

  static Future<void> addTransaction(String branch, Map<String, dynamic> item) async {
    final list = await readTransactions(branch);
    list.insert(0, item);
    await saveTransactions(branch, list);
  }

  static Future<void> clearTransactions(String branch) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(keyTransactions(branch));
  }

  // ---------- Staff ----------
  static Future<List<Map<String, dynamic>>> readStaff(String branch) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(keyStaff(branch));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> saveStaff(String branch, List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(keyStaff(branch), jsonEncode(list));
  }

  static Future<void> addStaff(String branch, Map<String, dynamic> item) async {
    final list = await readStaff(branch);
    list.insert(0, item);
    await saveStaff(branch, list);
  }

  static Future<void> clearStaff(String branch) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(keyStaff(branch));
  }

  // ---------- Attendance ----------
  static Future<List<Map<String, dynamic>>> readAttendance(String branch) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(keyAttendance(branch));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> saveAttendance(String branch, List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(keyAttendance(branch), jsonEncode(list));
  }

  static Future<void> addAttendance(String branch, Map<String, dynamic> item) async {
    final list = await readAttendance(branch);
    list.insert(0, item);
    await saveAttendance(branch, list);
  }

  static Future<void> clearAttendance(String branch) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(keyAttendance(branch));
  }

  // Clear ALL data for branch
  static Future<void> clearAllForBranch(String branch) async {
    await clearTransactions(branch);
    await clearStaff(branch);
    await clearAttendance(branch);
  }
}