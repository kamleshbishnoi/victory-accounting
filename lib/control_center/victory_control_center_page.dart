import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_transactions_page.dart';
import 'admin_commission_monitor_page.dart';
import 'admin_ticket_report_page.dart';
import 'admin_gst_report_page.dart';
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

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _selectedBranch = 'ALL';

  List<Map<String, dynamic>> _branchSummary = [];

  static const List<String> _branches = [
    'ALL',
    'JPR',
    'UPR',
    'ILL',
    'VCT',
    'MYK',
    'WND',
    'LOK',
    'SND',
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _fmt(dynamic value) {
    return _toDouble(value).toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    return date.toIso8601String().split('T').first;
  }

  String _displayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final String fromDate = _formatDate(_fromDate);
      final String toDate = _formatDate(_toDate);

      dynamic ticketsQuery = supabase
          .from('tickets')
          .select('branch_code, final_amount, payment_method, ticket_date')
          .gte('ticket_date', fromDate)
          .lte('ticket_date', toDate);

      if (_selectedBranch != 'ALL') {
        ticketsQuery = ticketsQuery.eq('branch_code', _selectedBranch);
      }

      final List<dynamic> tickets = List<dynamic>.from(await ticketsQuery);

      dynamic transactionsQuery = supabase
          .from('transactions')
          .select('branch_code, category, amount, tx_date')
          .gte('tx_date', fromDate)
          .lte('tx_date', toDate);

      if (_selectedBranch != 'ALL') {
        transactionsQuery =
            transactionsQuery.eq('branch_code', _selectedBranch);
      }

      final List<dynamic> transactions =
          List<dynamic>.from(await transactionsQuery);

      dynamic closingsQuery = supabase
          .from('cash_day_closing')
          .select('branch_code, actual_closing_balance, closing_date')
          .gte('closing_date', fromDate)
          .lte('closing_date', toDate)
          .order('closing_date', ascending: true);

      if (_selectedBranch != 'ALL') {
        closingsQuery = closingsQuery.eq('branch_code', _selectedBranch);
      }

      final List<dynamic> closings = List<dynamic>.from(await closingsQuery);

      double totalSale = 0;
      double cashSale = 0;
      double upiSale = 0;
      double cardSale = 0;
      double expense = 0;
      double commission = 0;
      double salaryAdvance = 0;
      double cashInHand = 0;

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

      for (final dynamic ticketData in tickets) {
        final Map<String, dynamic> ticket =
            Map<String, dynamic>.from(ticketData as Map);

        final String branch =
            (ticket['branch_code'] ?? '-').toString().toUpperCase();
        final double amount = _toDouble(ticket['final_amount']);
        final String payment = (ticket['payment_method'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        ensureBranch(branch);

        totalSale += amount;
        branchMap[branch]!['sale'] =
            (branchMap[branch]!['sale'] ?? 0) + amount;

        if (payment == 'CASH') {
          cashSale += amount;
          branchMap[branch]!['cash'] =
              (branchMap[branch]!['cash'] ?? 0) + amount;
        } else if (payment == 'UPI' ||
            payment == 'UPI_CREDIT_CARD' ||
            payment == 'UPI_PPIWALLET' ||
            payment == 'UPI_LITE') {
          upiSale += amount;
          branchMap[branch]!['upi'] =
              (branchMap[branch]!['upi'] ?? 0) + amount;
        } else if (payment == 'CARD' ||
            payment == 'CREDIT CARD' ||
            payment == 'DEBIT CARD') {
          cardSale += amount;
          branchMap[branch]!['card'] =
              (branchMap[branch]!['card'] ?? 0) + amount;
        }
      }

      for (final dynamic transactionData in transactions) {
        final Map<String, dynamic> transaction =
            Map<String, dynamic>.from(transactionData as Map);

        final String branch =
            (transaction['branch_code'] ?? '-').toString().toUpperCase();
        final String category =
            (transaction['category'] ?? '').toString().trim();
        final double amount = _toDouble(transaction['amount']);

        ensureBranch(branch);

        if (category == 'Expense' ||
            category == 'Other Cash Out' ||
            category == 'Vendor Payment' ||
            category == 'Refund') {
          expense += amount;
          branchMap[branch]!['expense'] =
              (branchMap[branch]!['expense'] ?? 0) + amount;
        }

        if (category == 'Commission Paid') {
          commission += amount;
          branchMap[branch]!['commission'] =
              (branchMap[branch]!['commission'] ?? 0) + amount;
        }

        if (category == 'Salary Advance') {
          salaryAdvance += amount;
          branchMap[branch]!['salary_advance'] =
              (branchMap[branch]!['salary_advance'] ?? 0) + amount;
        }
      }

      for (final dynamic closingData in closings) {
        final Map<String, dynamic> closing =
            Map<String, dynamic>.from(closingData as Map);

        final String branch =
            (closing['branch_code'] ?? '-').toString().toUpperCase();
        final double amount =
            _toDouble(closing['actual_closing_balance']);

        ensureBranch(branch);

        // Query date order me hai, isliye har branch ka latest closing
        // balance final value rahega.
        branchMap[branch]!['cash_in_hand'] = amount;
      }

      for (final MapEntry<String, Map<String, double>> entry
          in branchMap.entries) {
        cashInHand += entry.value['cash_in_hand'] ?? 0;
      }

      final List<Map<String, dynamic>> branchSummary =
          branchMap.entries.map((entry) {
        return {
          'branch': entry.key,
          'sale': entry.value['sale'] ?? 0,
          'cash': entry.value['cash'] ?? 0,
          'upi': entry.value['upi'] ?? 0,
          'card': entry.value['card'] ?? 0,
          'expense': entry.value['expense'] ?? 0,
          'commission': entry.value['commission'] ?? 0,
          'salary_advance': entry.value['salary_advance'] ?? 0,
          'cash_in_hand': entry.value['cash_in_hand'] ?? 0,
        };
      }).toList()
        ..sort(
          (a, b) =>
              a['branch'].toString().compareTo(b['branch'].toString()),
        );

      if (!mounted) return;

      setState(() {
        _totalSale = totalSale;
        _cashSale = cashSale;
        _upiSale = upiSale;
        _cardSale = cardSale;
        _expense = expense;
        _commission = commission;
        _salaryAdvance = salaryAdvance;
        _cashInHand = cashInHand;
        _branchSummary = branchSummary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dashboard load error: $error'),
        ),
      );
    }
  }

  void _go(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Widget _heroHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String fromDateText = _displayDate(_fromDate);
    final String toDateText = _displayDate(_toDate);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 85),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
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
            blurRadius: 12,
            color: theme.colorScheme.primary.withOpacity(0.16),
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.account_balance,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Victory • Control Center',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'System Overview • Welcome ${widget.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fromDateText == toDateText
                      ? 'Date: $fromDateText'
                      : 'Date: $fromDateText to $toDateText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 145,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final DateTime? date = await showDatePicker(
                    context: context,
                    initialDate: _fromDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2035),
                  );

                  if (date != null && mounted) {
                    setState(() {
                      _fromDate = date;
                      if (_toDate.isBefore(_fromDate)) {
                        _toDate = date;
                      }
                    });
                  }
                },
                icon: const Icon(Icons.calendar_month, size: 17),
                label: Text(
                  _displayDate(_fromDate),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: 145,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final DateTime? date = await showDatePicker(
                    context: context,
                    initialDate: _toDate,
                    firstDate: _fromDate,
                    lastDate: DateTime(2035),
                  );

                  if (date != null && mounted) {
                    setState(() {
                      _toDate = date;
                    });
                  }
                },
                icon: const Icon(Icons.event_available, size: 17),
                label: Text(
                  _displayDate(_toDate),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: 155,
              child: DropdownButtonFormField<String>(
                value: _selectedBranch,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                items: _branches.map((String branch) {
                  return DropdownMenuItem<String>(
                    value: branch,
                    child: Text(branch == 'ALL' ? 'All Branches' : branch),
                  );
                }).toList(),
                onChanged: (String? value) {
                  if (value == null) return;
                  setState(() {
                    _selectedBranch = value;
                  });
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: _loadDashboard,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Apply'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                final DateTime now = DateTime.now();
                setState(() {
                  _fromDate = now;
                  _toDate = now;
                  _selectedBranch = 'ALL';
                });
                _loadDashboard();
              },
              icon: const Icon(Icons.today, size: 18),
              label: const Text('Today'),
            ),
          ],
        ),
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
      width: 160,
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor ?? Colors.black87),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopKpis() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _kpiCard(
          'Total Sale',
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

  Widget _summaryHeaderCell(
    String text, {
    double? width,
    Alignment? align,
  }) {
    return Container(
      width: width,
      alignment: align ?? Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _summaryDataCell(
    String text, {
    double? width,
    Alignment? align,
  }) {
    return Container(
      width: width,
      alignment: align ?? Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildBranchSummary() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Branch Wise Summary',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            if (_branchSummary.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
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
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          _summaryHeaderCell('Branch', width: 75),
                          _summaryHeaderCell('Sale', width: 105),
                          _summaryHeaderCell('Cash', width: 105),
                          _summaryHeaderCell('UPI', width: 105),
                          _summaryHeaderCell('Card', width: 105),
                          _summaryHeaderCell('Expense', width: 105),
                          _summaryHeaderCell('Commission', width: 115),
                          _summaryHeaderCell('Salary Adv.', width: 115),
                          _summaryHeaderCell('Cash In Hand', width: 125),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._branchSummary.map((Map<String, dynamic> entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            _summaryDataCell(
                              entry['branch'].toString(),
                              width: 75,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['sale'])}',
                              width: 105,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['cash'])}',
                              width: 105,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['upi'])}',
                              width: 105,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['card'])}',
                              width: 105,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['expense'])}',
                              width: 105,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['commission'])}',
                              width: 115,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['salary_advance'])}',
                              width: 115,
                            ),
                            _summaryDataCell(
                              '₹${_fmt(entry['cash_in_hand'])}',
                              width: 125,
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
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 210,
          height: 105,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: iconBg ?? Colors.blueGrey.shade50,
                child: Icon(
                  icon,
                  size: 20,
                  color: Colors.blueGrey.shade800,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 11,
                      ),
                    ),
                  ],
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
      spacing: 10,
      runSpacing: 10,
      children: [
        _actionCard(
          title: 'Transactions',
          subtitle: 'Cash in, cash out & expenses',
          icon: Icons.receipt_long,
          iconBg: Colors.blue.shade50,
          onTap: () => _go(
            AdminTransactionsPage(username: widget.username),
          ),
        ),
        _actionCard(
          title: 'Commission',
          subtitle: 'Paid / Pending commission',
          icon: Icons.account_balance_wallet,
          iconBg: Colors.purple.shade50,
          onTap: () => _go(
            AdminCommissionMonitorPage(username: widget.username),
          ),
        ),
        _actionCard(
          title: 'Ticket Report',
          subtitle: 'Branch wise sale report',
          icon: Icons.list_alt,
          iconBg: Colors.green.shade50,
          onTap: () => _go(const AdminTicketReportPage()),
        ),
        _actionCard(
          title: 'GST Item Report',
          subtitle: 'Item-wise quantity, taxable sale & GST',
          icon: Icons.receipt_long,
          iconBg: Colors.amber.shade50,
          onTap: () => _go(AdminGstReportPage()),
        ),
        _actionCard(
          title: 'Attendance',
          subtitle: 'Present & absent records',
          icon: Icons.fact_check,
          iconBg: Colors.orange.shade50,
          onTap: () => _go(const AdminAttendancePage()),
        ),
        _actionCard(
          title: 'Staff',
          subtitle: 'Staff details',
          icon: Icons.people,
          iconBg: Colors.teal.shade50,
          onTap: () => _go(const AdminStaffPage()),
        ),
        _actionCard(
          title: 'Salary',
          subtitle: 'Salary records',
          icon: Icons.currency_rupee,
          iconBg: Colors.indigo.shade50,
          onTap: () => _go(const AdminSalaryPage()),
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
                padding: const EdgeInsets.all(12),
                child: ListView(
                  children: [
                    _heroHeader(context),
                    const SizedBox(height: 10),
                    _buildFilterRow(),
                    const SizedBox(height: 10),
                    _buildTopKpis(),
                    const SizedBox(height: 12),
                    _buildBranchSummary(),
                    const SizedBox(height: 12),
                    const Text(
                      'Quick Access',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildActionGrid(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}
