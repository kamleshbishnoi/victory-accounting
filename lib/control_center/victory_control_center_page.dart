import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_transactions_page.dart';
import 'admin_commission_monitor_page.dart';
import 'admin_ticket_report_page.dart';
import 'admin_attendance_page.dart';
import 'admin_staff_page.dart';
import 'admin_salary_page.dart';

class VictoryControlCenterPage extends StatefulWidget {
  final String username;

  const VictoryControlCenterPage({
    super.key,
    required this.username,
  });

  @override
  State<VictoryControlCenterPage> createState() =>
      _VictoryControlCenterPageState();
}

class _VictoryControlCenterPageState extends State<VictoryControlCenterPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _loading = true;

  double _totalSale = 0;
  double _cashSale = 0;
  double _upiSale = 0;
  double _cardSale = 0;
  double _expense = 0;
  double _commission = 0;
  double _salaryAdvance = 0;
  double _cashInHand = 0;

  List<Map<String, dynamic>> _branchSummary = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmt(dynamic v) => _toDouble(v).toStringAsFixed(2);

  String _today() => DateTime.now().toIso8601String().split('T').first;

  Future<void> _loadDashboard() async {
    setState(() => _loading = true);

    try {
      final today = _today();

      final tickets = await supabase
          .from('tickets')
          .select('branch_code, final_amount, payment_method')
          .eq('ticket_date', today);

      final transactions = await supabase
          .from('transactions')
          .select('branch_code, category, amount')
          .eq('tx_date', today);

      final closings = await supabase
          .from('cash_day_closing')
          .select('branch_code, actual_closing_balance, closing_date');

      _totalSale = 0;
      _cashSale = 0;
      _upiSale = 0;
      _cardSale = 0;
      _expense = 0;
      _commission = 0;
      _salaryAdvance = 0;
      _cashInHand = 0;

      final Map<String, Map<String, double>> branchMap = {};

      void ensureBranch(String branch) {
        branchMap.putIfAbsent(branch, () {
          return {
            'sale': 0,
            'cash': 0,
            'upi': 0,
            'card': 0,
            'expense': 0,
            'commission': 0,
            'salary_advance': 0,
            'cash_in_hand': 0,
          };
        });
      }

      for (final t in tickets) {
        final branch = (t['branch_code'] ?? '-').toString().toUpperCase();
        final amount = _toDouble(t['final_amount']);
        final payment = (t['payment_method'] ?? '').toString().toUpperCase();

        ensureBranch(branch);

        _totalSale += amount;
        branchMap[branch]!['sale'] = branchMap[branch]!['sale']! + amount;

        if (payment == 'CASH') {
          _cashSale += amount;
          branchMap[branch]!['cash'] = branchMap[branch]!['cash']! + amount;
        } else if (payment == 'UPI') {
          _upiSale += amount;
          branchMap[branch]!['upi'] = branchMap[branch]!['upi']! + amount;
        } else if (payment == 'CARD') {
          _cardSale += amount;
          branchMap[branch]!['card'] = branchMap[branch]!['card']! + amount;
        }
      }

      for (final tx in transactions) {
        final branch = (tx['branch_code'] ?? '-').toString().toUpperCase();
        final category = (tx['category'] ?? '').toString();
        final amount = _toDouble(tx['amount']);

        ensureBranch(branch);

        if (category == 'Expense' ||
            category == 'Other Cash Out' ||
            category == 'Vendor Payment' ||
            category == 'Refund') {
          _expense += amount;
          branchMap[branch]!['expense'] =
              branchMap[branch]!['expense']! + amount;
        }

        if (category == 'Commission Paid') {
          _commission += amount;
          branchMap[branch]!['commission'] =
              branchMap[branch]!['commission']! + amount;
        }

        if (category == 'Salary Advance') {
          _salaryAdvance += amount;
          branchMap[branch]!['salary_advance'] =
              branchMap[branch]!['salary_advance']! + amount;
        }
      }

      for (final c in closings) {
        final branch = (c['branch_code'] ?? '-').toString().toUpperCase();
        final amount = _toDouble(c['actual_closing_balance']);
        final closingDate = (c['closing_date'] ?? '').toString();

        if (!closingDate.startsWith(today)) continue;

        ensureBranch(branch);

        branchMap[branch]!['cash_in_hand'] = amount;
      }

      _cashInHand = 0;
      for (final e in branchMap.entries) {
        _cashInHand += e.value['cash_in_hand'] ?? 0;
      }

      _branchSummary = branchMap.entries.map((e) {
        return {
          'branch': e.key,
          'sale': e.value['sale'] ?? 0,
          'cash': e.value['cash'] ?? 0,
          'upi': e.value['upi'] ?? 0,
          'card': e.value['card'] ?? 0,
          'expense': e.value['expense'] ?? 0,
          'commission': e.value['commission'] ?? 0,
          'salary_advance': e.value['salary_advance'] ?? 0,
          'cash_in_hand': e.value['cash_in_hand'] ?? 0,
        };
      }).toList()
        ..sort(
          (a, b) => a['branch'].toString().compareTo(b['branch'].toString()),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dashboard load error: $e')),
      );
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _go(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Widget _heroHeader(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateText =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            color: theme.colorScheme.primary.withOpacity(0.18),
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.account_balance,
              color: Colors.white,
              size: 34,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Victory • Control Center',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'System Overview • Welcome ${widget.username}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Date: $dateText',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(
    String title,
    String value, {
    required IconData icon,
    Color? bg,
    Color? iconColor,
  }) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor ?? Colors.black87),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopKpis() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _kpiCard(
          'Today Sale',
          '₹${_fmt(_totalSale)}',
          icon: Icons.bar_chart,
          bg: Colors.blue.shade50,
          iconColor: Colors.blue.shade800,
        ),
        _kpiCard(
          'Cash',
          '₹${_fmt(_cashSale)}',
          icon: Icons.payments,
          bg: Colors.green.shade50,
          iconColor: Colors.green.shade800,
        ),
        _kpiCard(
          'UPI',
          '₹${_fmt(_upiSale)}',
          icon: Icons.qr_code_scanner,
          bg: Colors.indigo.shade50,
          iconColor: Colors.indigo.shade800,
        ),
        _kpiCard(
          'Card',
          '₹${_fmt(_cardSale)}',
          icon: Icons.credit_card,
          bg: Colors.deepPurple.shade50,
          iconColor: Colors.deepPurple.shade800,
        ),
        _kpiCard(
          'Expense',
          '₹${_fmt(_expense)}',
          icon: Icons.trending_down,
          bg: Colors.orange.shade50,
          iconColor: Colors.orange.shade800,
        ),
        _kpiCard(
          'Commission',
          '₹${_fmt(_commission)}',
          icon: Icons.account_balance_wallet,
          bg: Colors.purple.shade50,
          iconColor: Colors.purple.shade800,
        ),
        _kpiCard(
          'Salary Adv.',
          '₹${_fmt(_salaryAdvance)}',
          icon: Icons.currency_rupee,
          bg: Colors.teal.shade50,
          iconColor: Colors.teal.shade800,
        ),
        _kpiCard(
          'Cash In Hand',
          '₹${_fmt(_cashInHand)}',
          icon: Icons.savings,
          bg: Colors.lightGreen.shade50,
          iconColor: Colors.lightGreen.shade800,
        ),
      ],
    );
  }

  Widget _summaryHeaderCell(String text, {double? width, Alignment? align}) {
    return Container(
      width: width,
      alignment: align ?? Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _summaryDataCell(String text, {double? width, Alignment? align}) {
    return Container(
      width: width,
      alignment: align ?? Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }

  Widget _buildBranchSummary() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Branch Wise Summary',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            if (_branchSummary.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No branch summary found')),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          _summaryHeaderCell('Branch', width: 90),
                          _summaryHeaderCell('Sale', width: 120),
                          _summaryHeaderCell('Cash', width: 120),
                          _summaryHeaderCell('UPI', width: 120),
                          _summaryHeaderCell('Card', width: 120),
                          _summaryHeaderCell('Expense', width: 120),
                          _summaryHeaderCell('Commission', width: 130),
                          _summaryHeaderCell('Salary Adv.', width: 130),
                          _summaryHeaderCell('Cash In Hand', width: 140),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._branchSummary.map((e) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            _summaryDataCell(
                              e['branch'].toString(),
                              width: 90,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['sale'])}',
                              width: 120,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['cash'])}',
                              width: 120,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['upi'])}',
                              width: 120,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['card'])}',
                              width: 120,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['expense'])}',
                              width: 120,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['commission'])}',
                              width: 130,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['salary_advance'])}',
                              width: 130,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(e['cash_in_hand'])}',
                              width: 140,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconBg,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1.2,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: iconBg ?? Colors.blueGrey.shade50,
                child: Icon(icon, color: Colors.blueGrey.shade800),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _actionCard(
          title: 'Transactions Monitor',
          subtitle: 'Cash in, cash out, expense, filters',
          icon: Icons.receipt_long,
          iconBg: Colors.blue.shade50,
          onTap: () => _go(
            AdminTransactionsPage(username: widget.username),
          ),
        ),
        _actionCard(
          title: 'Commission Monitor',
          subtitle: 'Paid / pending commission overview',
          icon: Icons.account_balance_wallet,
          iconBg: Colors.purple.shade50,
          onTap: () => _go(
            AdminCommissionMonitorPage(username: widget.username),
          ),
        ),
        _actionCard(
          title: 'Ticket Report Monitor',
          subtitle: 'Branch wise tickets and sale details',
          icon: Icons.list_alt,
          iconBg: Colors.green.shade50,
          onTap: () => _go(
            const AdminTicketReportPage(),
          ),
        ),
        _actionCard(
          title: 'Attendance Monitor',
          subtitle: 'Present, absent, half day records',
          icon: Icons.fact_check,
          iconBg: Colors.orange.shade50,
          onTap: () => _go(
            const AdminAttendancePage(),
          ),
        ),
        _actionCard(
          title: 'Staff Monitor',
          subtitle: 'Staff details and branch mapping',
          icon: Icons.people,
          iconBg: Colors.teal.shade50,
          onTap: () => _go(
            const AdminStaffPage(),
          ),
        ),
        _actionCard(
          title: 'Salary Monitor',
          subtitle: 'Salary totals and salary records',
          icon: Icons.currency_rupee,
          iconBg: Colors.indigo.shade50,
          onTap: () => _go(
            const AdminSalaryPage(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Victory • Control Center'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: ListView(
                  children: [
                    _heroHeader(context),
                    const SizedBox(height: 14),
                    _buildTopKpis(),
                    const SizedBox(height: 14),
                    _buildBranchSummary(),
                    const SizedBox(height: 14),
                    const Text(
                      'Quick Access',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildActionGrid(),
                  ],
                ),
              ),
            ),
    );
  }
}