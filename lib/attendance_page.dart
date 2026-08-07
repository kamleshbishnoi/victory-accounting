import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendancePage extends StatefulWidget {
  final String username;
  final String branch;

  const AttendancePage({
    super.key,
    required this.username,
    required this.branch,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  DateTime _selectedDate = DateTime.now();

  String? _resolvedBranchId;

  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtTimeString(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return '--:--';
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }

  int _parseTimeToMinutes(String? time) {
    if (time == null || time.trim().isEmpty) return 0;
    final parts = time.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  String _timeOfDayToString(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  int _workedMinutesFromStrings(String? inTime, String? outTime) {
    if (inTime == null || outTime == null) return 0;
    final inMin = _parseTimeToMinutes(inTime);
    final outMin = _parseTimeToMinutes(outTime);
    final diff = outMin - inMin;
    return diff < 0 ? 0 : diff;
  }

  String _readAnyString(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = (row[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  int _readAnyInt(Map<String, dynamic> row, List<String> keys, int fallback) {
    for (final k in keys) {
      final v = row[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      final parsed = int.tryParse((v ?? '').toString());
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  double _readAnyDouble(
    Map<String, dynamic> row,
    List<String> keys,
    double fallback,
  ) {
    for (final k in keys) {
      final v = row[k];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      final parsed = double.tryParse((v ?? '').toString());
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  String _staffName(Map<String, dynamic> row) {
    return _readAnyString(row, [
      'name',
      'staff_name',
      'full_name',
      'employee_name',
      'staff',
    ]);
  }

  String _staffMobile(Map<String, dynamic> row) {
    return _readAnyString(row, ['mobile', 'phone', 'mobile_no']);
  }

  String _staffRole(Map<String, dynamic> row) {
    return _readAnyString(row, ['role', 'designation']);
  }

  String _staffShiftStart(Map<String, dynamic> row) {
    final v = _readAnyString(row, [
      'shift_start_time',
      'shift_in',
      'in_time_rule',
    ]);
    return v.isEmpty ? '09:00' : _fmtTimeString(v);
  }

  String _staffShiftEnd(Map<String, dynamic> row) {
    final v = _readAnyString(row, [
      'shift_end_time',
      'shift_out',
      'out_time_rule',
    ]);
    return v.isEmpty ? '18:30' : _fmtTimeString(v);
  }

  String _staffId(Map<String, dynamic> row) {
    return (row['id'] ?? row['staff_id'] ?? '').toString();
  }

  Future<void> _resolveBranchId() async {
    final byCode = await _supabase
        .from('branches')
        .select('id, code, name')
        .eq('code', widget.branch)
        .maybeSingle();

    if (byCode != null) {
      _resolvedBranchId = (byCode['id'] ?? '').toString();
      return;
    }

    final byName = await _supabase
        .from('branches')
        .select('id, code, name')
        .eq('name', widget.branch)
        .maybeSingle();

    if (byName != null) {
      _resolvedBranchId = (byName['id'] ?? '').toString();
    }
  }

  Map<String, dynamic> _calcStatus({
    required String shiftStart,
    required String? inTime,
    required String? outTime,
    required int graceMinutes,
    required bool paidOff,
  }) {
    if (paidOff) {
      return {
        'status': 'Paid Off',
        'late_mark': false,
        'worked_minutes': 0,
        'day_fraction': 1.0,
      };
    }

    if (inTime == null ||
        inTime.isEmpty ||
        outTime == null ||
        outTime.isEmpty) {
      return {
        'status': 'Absent',
        'late_mark': false,
        'worked_minutes': 0,
        'day_fraction': 0.0,
      };
    }

    final worked = _workedMinutesFromStrings(inTime, outTime);
    final shiftStartMin = _parseTimeToMinutes(shiftStart);
    final inMin = _parseTimeToMinutes(inTime);
    final isLate = inMin > (shiftStartMin + graceMinutes);

    String status = 'Present';
    double dayFraction = 1.0;

    if (worked >= 510) {
      status = isLate ? 'Late' : 'Present';
      dayFraction = 1.0;
    } else if (worked >= 405) {
      status = '3/4 Day';
      dayFraction = 0.75;
    } else if (worked >= 270) {
      status = 'Half Day';
      dayFraction = 0.50;
    } else if (worked >= 135) {
      status = '1/4 Day';
      dayFraction = 0.25;
    } else {
      status = 'Absent';
      dayFraction = 0.0;
    }

    return {
      'status': status,
      'late_mark': isLate,
      'worked_minutes': worked,
      'day_fraction': dayFraction,
    };
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    try {
      await _resolveBranchId();

      if (_resolvedBranchId == null || _resolvedBranchId!.isEmpty) {
        _staff = [];
        _attendance = [];
        _rows = [];
        _msg('Branch not found');
      } else {
        final dateStr = _fmtDate(_selectedDate);

        final staffData = await _supabase
            .from('staff')
            .select()
            .eq('branch_id', _resolvedBranchId);

        final attData = await _supabase
            .from('attendance')
            .select()
            .eq('branch_code', widget.branch)
            .eq('att_date', dateStr);

        _staff = List<Map<String, dynamic>>.from(staffData);
        _attendance = List<Map<String, dynamic>>.from(attData);

        final Map<String, Map<String, dynamic>> attMap = {};
        for (final a in _attendance) {
          final name = (a['staff_name'] ?? '').toString().trim().toLowerCase();
          if (name.isNotEmpty) {
            attMap[name] = a;
          }
        }

        _rows = _staff.map((s) {
          final staffName = _staffName(s);
          final existing = attMap[staffName.trim().toLowerCase()];

          return {
            'staff_id': _staffId(s),
            'staff_name': staffName,
            'mobile': _staffMobile(s),
            'role': _staffRole(s),
            'salary': s['salary'],
            'shift_start_time': _staffShiftStart(s),
            'shift_end_time': _staffShiftEnd(s),
            'grace_minutes': _readAnyInt(s, ['grace_minutes'], 10),
            'paid_off_per_month': _readAnyInt(s, ['paid_off_per_month'], 2),
            'attendance_id': existing == null ? null : existing['id'],
            'in_time': existing == null
                ? null
                : _fmtTimeString(existing['in_time']),
            'out_time': existing == null
                ? null
                : _fmtTimeString(existing['out_time']),
            'status': existing == null
                ? 'Pending'
                : (existing['status'] ?? 'Pending').toString(),
            'late_mark': existing == null
                ? false
                : (existing['late_mark'] == true),
            'worked_minutes': existing == null
                ? 0
                : _readAnyInt(existing, ['worked_minutes'], 0),
            'day_fraction': existing == null
                ? 0.0
                : _readAnyDouble(existing, ['day_fraction'], 0.0),
            'remarks': existing == null
                ? ''
                : (existing['remarks'] ?? '').toString(),
          };
        }).toList();
      }
    } catch (e) {
      _msg('Load error: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadAll();
  }

  Future<String?> _pickTimeString(String? current) async {
    TimeOfDay initial = const TimeOfDay(hour: 9, minute: 0);

    if (current != null && current.isNotEmpty && current.contains(':')) {
      final parts = current.split(':');
      if (parts.length >= 2) {
        initial = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked == null) return null;
    return _timeOfDayToString(picked);
  }

  Future<int> _paidOffCountForMonth(Map<String, dynamic> row) async {
    final monthStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final monthEnd = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);

    final data = await _supabase
        .from('attendance')
        .select('id, status')
        .eq('branch_code', widget.branch)
        .eq('staff_name', row['staff_name'])
        .gte('att_date', _fmtDate(monthStart))
        .lte('att_date', _fmtDate(monthEnd))
        .eq('status', 'Paid Off');

    int count = 0;
    for (final e in data) {
      final id = (e['id'] ?? '').toString();
      final currentId = (row['attendance_id'] ?? '').toString();
      if (currentId.isNotEmpty && id == currentId) continue;
      count++;
    }
    return count;
  }

  Future<void> _openEditDialog(Map<String, dynamic> row) async {
    String? inTime = (row['in_time'] ?? '').toString().isEmpty
        ? null
        : row['in_time'].toString();

    String? outTime = (row['out_time'] ?? '').toString().isEmpty
        ? null
        : row['out_time'].toString();

    bool paidOff = (row['status'] ?? '') == 'Paid Off';
    final remarksCtl = TextEditingController(
      text: (row['remarks'] ?? '').toString(),
    );

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) {
          final calc = _calcStatus(
            shiftStart: (row['shift_start_time'] ?? '09:00').toString(),
            inTime: inTime,
            outTime: outTime,
            graceMinutes: (row['grace_minutes'] ?? 10) as int,
            paidOff: paidOff,
          );

          return AlertDialog(
            title: Text('Attendance • ${row['staff_name']}'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shift: ${row['shift_start_time']} - ${row['shift_end_time']}',
                    ),
                    const SizedBox(height: 6),
                    Text('Grace: ${row['grace_minutes']} min'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickTimeString(inTime);
                              if (picked == null) return;
                              setD(() => inTime = picked.substring(0, 5));
                            },
                            icon: const Icon(Icons.login),
                            label: Text('In: ${inTime ?? '--:--'}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickTimeString(outTime);
                              if (picked == null) return;
                              setD(() => outTime = picked.substring(0, 5));
                            },
                            icon: const Icon(Icons.logout),
                            label: Text('Out: ${outTime ?? '--:--'}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: paidOff,
                      onChanged: (v) => setD(() => paidOff = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Paid Off'),
                      subtitle: const Text('Month me sirf 2 paid off allowed'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: remarksCtl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Remarks',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('Status', calc['status'].toString()),
                        _chip('Late', calc['late_mark'] == true ? 'Yes' : 'No'),
                        _chip('Worked', '${calc['worked_minutes']} min'),
                        _chip('Day', calc['day_fraction'].toString()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final dateStr = _fmtDate(_selectedDate);

                    final finalCalc = _calcStatus(
                      shiftStart: (row['shift_start_time'] ?? '09:00')
                          .toString(),
                      inTime: inTime,
                      outTime: outTime,
                      graceMinutes: (row['grace_minutes'] ?? 10) as int,
                      paidOff: paidOff,
                    );

                    String finalStatus = finalCalc['status'].toString();
                    bool finalLate = finalCalc['late_mark'] == true;
                    int finalWorked = finalCalc['worked_minutes'] as int;
                    double finalFraction = (finalCalc['day_fraction'] as num)
                        .toDouble();

                    if (paidOff) {
                      final usedPaidOff = await _paidOffCountForMonth(row);
                      if (usedPaidOff >= 2) {
                        finalStatus = 'Absent';
                        finalLate = false;
                        finalWorked = 0;
                        finalFraction = 0.0;
                        _msg(
                          '2 paid off already use ho chuke hain. Ye Absent save hoga.',
                        );
                      }
                    }

                    final payload = {
                      'staff_id': row['staff_id'],
                      'staff_name': row['staff_name'],
                      'branch_code': widget.branch,
                      'att_date': dateStr,
                      'in_time': inTime,
                      'out_time': outTime,
                      'status': finalStatus,
                      'late_mark': finalLate,
                      'worked_minutes': finalWorked,
                      'day_fraction': finalFraction,
                      'remarks': remarksCtl.text.trim(),
                    };

                    final existing = await _supabase
                        .from('attendance')
                        .select('id')
                        .eq('staff_name', row['staff_name'])
                        .eq('att_date', dateStr)
                        .eq('branch_code', widget.branch)
                        .maybeSingle();

                    if (existing != null) {
                      await _supabase
                          .from('attendance')
                          .update(payload)
                          .eq('id', existing['id']);
                    } else {
                      await _supabase.from('attendance').insert(payload);
                    }

                    if (!mounted) return;
                    Navigator.pop(context);
                    await _loadAll();
                    _msg('Attendance saved');
                  } catch (e) {
                    _msg('Save error: $e');
                  }
                },
                child: const Text('Save / Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '$title: $value',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Present':
        return Colors.green.shade50;
      case 'Late':
        return Colors.orange.shade50;
      case 'Half Day':
        return Colors.amber.shade50;
      case '3/4 Day':
        return Colors.blue.shade50;
      case '1/4 Day':
        return Colors.deepOrange.shade50;
      case 'Paid Off':
        return Colors.teal.shade50;
      case 'Absent':
        return Colors.red.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Absent':
        return Icons.cancel_outlined;
      case 'Late':
        return Icons.access_time;
      case 'Half Day':
        return Icons.timelapse;
      case '3/4 Day':
        return Icons.more_time;
      case '1/4 Day':
        return Icons.hourglass_bottom;
      case 'Paid Off':
        return Icons.beach_access;
      case 'Present':
        return Icons.check_circle_outline;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Widget _topCard() {
    return Card(
      elevation: 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.person)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome ${widget.username}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Branch: ${widget.branch}'),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.date_range),
              label: Text(_fmtDate(_selectedDate)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBar() {
    final total = _rows.length;
    final done = _rows
        .where((e) => (e['status'] ?? 'Pending') != 'Pending')
        .length;
    final pending = total - done;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _chip('Total Staff', '$total'),
          _chip('Done', '$done'),
          _chip('Pending', '$pending'),
          _chip('Paid Off Limit', '2/month'),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Staff Name',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('Shift', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Status',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'In Time',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Out Time',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text('Late', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 1,
            child: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _attendanceTable() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rows.isEmpty) {
      return const Center(child: Text('No staff found for this branch'));
    }

    return Column(
      children: [
        _summaryBar(),
        _tableHeader(),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final e = _rows[i];
              final status = (e['status'] ?? 'Pending').toString();

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Icon(_statusIcon(status), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (e['staff_name'] ?? '').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${e['shift_start_time']} - ${e['shift_end_time']}',
                      ),
                    ),
                    Expanded(flex: 2, child: Text(status)),
                    Expanded(
                      flex: 2,
                      child: Text((e['in_time'] ?? '--:--').toString()),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text((e['out_time'] ?? '--:--').toString()),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text((e['late_mark'] == true) ? 'Yes' : 'No'),
                    ),
                    Expanded(
                      flex: 1,
                      child: IconButton(
                        tooltip: 'Edit',
                        onPressed: () => _openEditDialog(e),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance • ${widget.branch}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _topCard(),
            const SizedBox(height: 12),
            Expanded(child: _attendanceTable()),
          ],
        ),
      ),
    );
  }
}
