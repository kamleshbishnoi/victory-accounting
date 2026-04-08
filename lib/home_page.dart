import 'package:flutter/material.dart';

import 'attendance_page.dart';
import 'branches_page.dart';
import 'login_page.dart';
import 'ticket_report_page.dart';
import 'reports_page.dart';
import 'salary_page.dart';
import 'settings_page.dart';
import 'staff_page.dart';
import 'storage.dart';
import 'ticket_create_page.dart';
import 'transactions_page.dart';
import 'items_page.dart';

import 'pages/agents_page.dart';
import 'pages/agent_master_page.dart';
import 'pages/commission_page.dart';
import 'pages/commission_settings_page.dart';
import 'pages/agent_commission_report_page.dart';

import 'control_center/victory_control_center_page.dart';
import 'control_center/admin_transactions_page.dart';
import 'control_center/admin_commission_monitor_page.dart';
import 'control_center/admin_staff_page.dart';
import 'control_center/admin_salary_page.dart';
import 'control_center/admin_attendance_page.dart';
import 'control_center/admin_ticket_report_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatefulWidget {
  final String username;
  final String branch;

  const HomePage({
    required this.username,
    required this.branch,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late String _branch;
  bool _loadingBranch = true;
  bool _isAdminUser = false;

  bool get _isControlCenterMode => _branch == 'ALL';

  String _normalizeBranch(String b) {
    final s = b.trim().toUpperCase();
    if (s == 'JAIPUR' || s == 'JAI') return 'JPR';
    if (s == 'UDAIPUR' || s == 'UD') return 'UDR';
    if (s == 'ABU' || s == 'MOUNT ABU') return 'ABU';
    if (s == 'JAISALMER' || s == 'JSL') return 'JSL';
    if (s == 'ILLUSION' || s == 'ILL') return 'ILL';
    if (s == 'ALL' || s == 'VCC' || s == 'VICTORY CONTROL CENTER') return 'ALL';
    return s;
  }

  @override
void initState() {
  super.initState();
  _branch = _normalizeBranch(widget.branch);
  _initUserBranch();
}

Future<void> _initUserBranch() async {
  try {
    final row = await _supabase
        .from('staff_users')
        .select('role, branch_code')
        .eq('username', widget.username.trim().toLowerCase())
        .single();

    final role = (row['role'] ?? '').toString().toUpperCase();
    final branchCode = (row['branch_code'] ?? '').toString().toUpperCase();

    _isAdminUser = role == 'ADMIN';
    _branch = _isAdminUser ? 'ALL' : _normalizeBranch(branchCode);

    await Storage.setSelectedBranch(_branch);
  } catch (e) {
    _isAdminUser = false;
    _branch = _normalizeBranch(widget.branch);
  }

  if (mounted) {
    setState(() => _loadingBranch = false);
  }
}

  Future<void> _reloadBranch() async {
  if (!_isAdminUser) return;

  final selected = await Storage.getSelectedBranch();
  if (!mounted) return;
  setState(() => _branch = _normalizeBranch(selected));
}

  Future<void> _openBranchesAndReload() async {
  if (!_isAdminUser) {
    _toast('Aap sirf apni branch access kar sakte ho.');
    return;
  }

  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => const BranchesPage()),
  );
  if (!mounted) return;

  if (result == true) {
    await _reloadBranch();
  }
}

Future<void> _logout() async {
  await Storage.setSelectedBranch('ALL');
  if (!mounted) return;

  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (_) => const LoginPage()),
  );
}

  Future<void> _backToControlCenter() async {
  if (!_isAdminUser) return;

  await Storage.setSelectedBranch('ALL');
  if (!mounted) return;
  setState(() => _branch = 'ALL');
}

  bool _isNavigating = false;

void _go(Widget page) {
  if (_isNavigating) return;

  _isNavigating = true;

  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => page),
  ).then((_) {
    _isNavigating = false;
  });
}

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  List<_DashItem> get _dashboardItems {
  if (_isControlCenterMode) {
    return <_DashItem>[
      _DashItem(
        title: 'Victory Control Center',
        icon: Icons.account_balance,
        onTap: () => _go(
          VictoryControlCenterPage(username: widget.username),
        ),
      ),
      _DashItem(
        title: 'Transactions Monitor',
        icon: Icons.receipt_long,
        onTap: () => _go(
          AdminTransactionsPage(username: widget.username),
        ),
      ),
      _DashItem(
        title: 'Commission Monitor',
        icon: Icons.account_balance_wallet,
        onTap: () => _go(
          AdminCommissionMonitorPage(username: widget.username),
        ),
      ),
      _DashItem(
        title: 'Ticket Report Monitor',
        icon: Icons.list_alt,
        onTap: () => _go(
          AdminTicketReportPage(),
        ),
      ),
      _DashItem(
        title: 'Attendance Monitor',
        icon: Icons.fact_check,
        onTap: () => _go(
          AdminAttendancePage(),
        ),
      ),
      _DashItem(
        title: 'Staff Monitor',
        icon: Icons.people,
        onTap: () => _go(
          AdminStaffPage(),
        ),
      ),
      _DashItem(
        title: 'Salary Monitor',
        icon: Icons.currency_rupee,
        onTap: () => _go(
          AdminSalaryPage(),
        ),
      ),
      _DashItem(
        title: 'Reports',
        icon: Icons.bar_chart,
        onTap: () => _go(
          ReportsPage(
            username: widget.username,
            branch: _branch,
          ),
        ),
      ),
      _DashItem(
        title: 'Settings',
        icon: Icons.settings,
        onTap: () => _go(
          SettingsPage(
            username: widget.username,
            branch: _branch,
          ),
        ),
      ),
    ];
  }

  return <_DashItem>[
    _DashItem(
      title: 'Ticket',
      icon: Icons.confirmation_number,
      onTap: () => _go(
        TicketCreatePage(
          username: widget.username,
          branch: _branch,
        ),
      ),
    ),
    _DashItem(
      title: 'Ticket Items',
      icon: Icons.inventory_2,
      onTap: () => _go(ItemsPage(branch: _branch)),
    ),
    _DashItem(
      title: 'Transactions',
      icon: Icons.receipt_long,
      onTap: () => _go(
        TransactionsPage(
          username: widget.username,
          branch: _branch,
        ),
      ),
    ),
    _DashItem(
      title: 'Reports',
      icon: Icons.bar_chart,
      onTap: () => _go(
        ReportsPage(
          username: widget.username,
          branch: _branch,
        ),
      ),
    ),
    _DashItem(
      title: 'Ticket Report (Admin)',
      icon: Icons.list_alt,
      onTap: () => _go(
        TicketReportPage(
          username: widget.username,
          branch: _branch,
        ),
      ),
    ),
    _DashItem(
      title: 'Attendance',
      icon: Icons.fact_check,
      onTap: () => _go(
        AttendancePage(
          username: widget.username,
          branch: _branch,
        ),
      ),
    ),
    _DashItem(
      title: 'Staff',
      icon: Icons.people,
      onTap: () => _go(
        StaffPage(
          username: widget.username,
          branch: _branch,
        ),
      ),
    ),
    _DashItem(
  title: 'Salary',
  icon: Icons.currency_rupee,
  onTap: () => _go(
    SalaryPage(
      branch: _branch,
    ),
  ),
),
    _DashItem(
      title: 'Agents',
      icon: Icons.groups,
      onTap: () => _go(
        AgentsPage(branchCode: _branch),
      ),
    ),
    _DashItem(
      title: 'Agent Master',
      icon: Icons.person_add_alt_1,
      onTap: () => _go(
        AgentMasterPage(branchCode: _branch),
      ),
    ),
    _DashItem(
      title: 'Commission',
      icon: Icons.account_balance_wallet,
      onTap: () => _go(
        CommissionPage(
          branchCode: _branch,
          branchName: _branch,
        ),
      ),
    ),
    _DashItem(
      title: 'Agent Comm. Report',
      icon: Icons.assessment,
      onTap: () => _go(
        AgentCommissionReportPage(
          branchCode: _branch,
          branchName: _branch,
        ),
      ),
    ),
    _DashItem(
      title: 'Settings',
      icon: Icons.settings,
      onTap: () => _go(
        SettingsPage(
          username: widget.username,
          branch: _branch,
        ),
      ),
    ),
  ];
}

  @override
  Widget build(BuildContext context) {
    if (_loadingBranch) {
  return const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );
}
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isControlCenterMode
              ? 'Victory • Control Center'
              : 'Victory • $_branch',
        ),
        leading: (_isAdminUser && !_isControlCenterMode)
    ? IconButton(
        tooltip: 'Back to Control Center',
        icon: const Icon(Icons.arrow_back),
        onPressed: _backToControlCenter,
      )
    : null,
        actions: [
          if (_isAdminUser)
  IconButton(
    tooltip: 'Switch Branch',
    icon: const Icon(Icons.account_tree),
    onPressed: _openBranchesAndReload,
  ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text('Welcome ${widget.username}'),
                subtitle: Text(
                  _isControlCenterMode
                      ? 'System Overview'
                      : 'Branch: $_branch',
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.15,
              ),
              itemCount: _dashboardItems.length,
              itemBuilder: (context, index) {
                final item = _dashboardItems[index];
                return _DashboardCard(
                  icon: item.icon,
                  title: item.title,
                  onTap: item.onTap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DashItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  _DashItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}