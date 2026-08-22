import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddonModulePage extends StatefulWidget {
  final String username;
  final String branchCode;
  final String department; // PHOTO / VR
  final int initialTab;
  final bool management;

  const AddonModulePage({
    super.key,
    required this.username,
    required this.branchCode,
    required this.department,
    this.initialTab = 0,
    this.management = false,
  });

  @override
  State<AddonModulePage> createState() => _AddonModulePageState();
}

class _AddonModulePageState extends State<AddonModulePage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;

  late TabController _tabController;

  String get branch => widget.branchCode.trim().toUpperCase();
  String get dept => widget.department.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    final length = widget.management ? 2 : 4;
    final safeInitial = widget.initialTab.clamp(0, length - 1).toInt();
    _tabController = TabController(
      length: length,
      vsync: this,
      initialIndex: safeInitial,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.management
        ? const [
            Tab(text: 'Sales Summary'),
            Tab(text: 'Commission'),
          ]
        : const [
            Tab(text: 'Items'),
            Tab(text: 'Sale'),
            Tab(text: 'Report'),
            Tab(text: 'Summary'),
          ];

    final views = widget.management
        ? [
            _AddonReportTab(
              username: widget.username,
              branchCode: branch,
              department: dept,
              summaryOnly: false,
            ),
            _AddonCommissionTab(
              username: widget.username,
              branchCode: branch,
              department: dept,
            ),
          ]
        : [
            _AddonItemsTab(
              branchCode: branch,
              department: dept,
            ),
            _AddonSaleTab(
              username: widget.username,
              branchCode: branch,
              department: dept,
            ),
            _AddonReportTab(
              username: widget.username,
              branchCode: branch,
              department: dept,
              summaryOnly: false,
            ),
            _AddonReportTab(
              username: widget.username,
              branchCode: branch,
              department: dept,
              summaryOnly: true,
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.management
              ? '$dept Management • $branch'
              : '$dept • $branch',
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: views,
      ),
    );
  }
}

class _AddonItemsTab extends StatefulWidget {
  final String branchCode;
  final String department;

  const _AddonItemsTab({
    required this.branchCode,
    required this.department,
  });

  @override
  State<_AddonItemsTab> createState() => _AddonItemsTabState();
}

class _AddonItemsTabState extends State<_AddonItemsTab> {
  final supabase = Supabase.instance.client;
  final nameCtl = TextEditingController();
  final rateCtl = TextEditingController();

  bool loading = true;
  bool saving = false;
  List<Map<String, dynamic>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    nameCtl.dispose();
    rateCtl.dispose();
    super.dispose();
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = await supabase
          .from('addon_items')
          .select()
          .eq('branch_code', widget.branchCode)
          .eq('department', widget.department)
          .order('created_at', ascending: false);

      rows = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _msg('Items load error: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final name = nameCtl.text.trim();
    final rate = double.tryParse(rateCtl.text.trim()) ?? 0;

    if (name.isEmpty || rate <= 0) {
      _msg('Item name aur rate sahi bharo');
      return;
    }

    setState(() => saving = true);
    try {
      await supabase.from('addon_items').insert({
        'branch_code': widget.branchCode,
        'department': widget.department,
        'item_name': name,
        'rate': rate,
        'active': true,
      });
      nameCtl.clear();
      rateCtl.clear();
      await _load();
      _msg('Item saved');
    } catch (e) {
      _msg('Item save error: $e');
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    final active = row['active'] == true;
    try {
      await supabase
          .from('addon_items')
          .update({'active': !active})
          .eq('id', row['id']);
      await _load();
    } catch (e) {
      _msg('Update error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: nameCtl,
                      decoration: const InputDecoration(
                        labelText: 'Item Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: rateCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rate',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(saving ? 'Saving...' : 'Save Item'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final active = r['active'] == true;
                      return ListTile(
                        title: Text((r['item_name'] ?? '').toString()),
                        subtitle: Text(
                          'Rate: ₹${_num(r['rate']).toStringAsFixed(2)}',
                        ),
                        trailing: Switch(
                          value: active,
                          onChanged: (_) => _toggle(r),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddonSaleTab extends StatefulWidget {
  final String username;
  final String branchCode;
  final String department;

  const _AddonSaleTab({
    required this.username,
    required this.branchCode,
    required this.department,
  });

  @override
  State<_AddonSaleTab> createState() => _AddonSaleTabState();
}

class _AddonSaleTabState extends State<_AddonSaleTab> {
  final supabase = Supabase.instance.client;
  final searchCtl = TextEditingController();
  final qtyCtl = TextEditingController(text: '1');
  final discountCtl = TextEditingController(text: '0');

  bool loading = true;
  bool saving = false;

  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> ticketMatches = [];

  String? selectedItemId;
  Map<String, dynamic>? selectedTicket;
  String paymentMode = 'Cash';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    searchCtl.dispose();
    qtyCtl.dispose();
    discountCtl.dispose();
    super.dispose();
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _loadItems() async {
    setState(() => loading = true);
    try {
      final data = await supabase
          .from('addon_items')
          .select()
          .eq('branch_code', widget.branchCode)
          .eq('department', widget.department)
          .eq('active', true)
          .order('item_name');

      items = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _msg('Items load error: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _searchTicket() async {
    final suffix = searchCtl.text.trim();
    if (suffix.isEmpty) {
      _msg('Ticket ke last number dalo');
      return;
    }

    try {
      final today = _dateOnly(DateTime.now());
      final data = await supabase
          .from('tickets')
          .select('id, ticket_no, final_amount, ticket_date, created_at, agent_id')
          .eq('branch_code', widget.branchCode)
          .gte('ticket_date', '${today}T00:00:00')
          .lte('ticket_date', '${today}T23:59:59')
          .like('ticket_no', '%$suffix')
          .order('created_at', ascending: false)
          .limit(20);

      setState(() {
        ticketMatches = List<Map<String, dynamic>>.from(data);
        selectedTicket = ticketMatches.length == 1 ? ticketMatches.first : null;
      });

      if (ticketMatches.isEmpty) _msg('Aaj ka matching ticket nahi mila');
    } catch (e) {
      _msg('Ticket search error: $e');
    }
  }

  Map<String, dynamic>? get selectedItem {
    if (selectedItemId == null) return null;
    for (final e in items) {
      if (e['id'].toString() == selectedItemId) return e;
    }
    return null;
  }

  double get rate => _num(selectedItem?['rate']);
  double get qty => double.tryParse(qtyCtl.text.trim()) ?? 0;
  double get gross => rate * qty;
  double get discount => double.tryParse(discountCtl.text.trim()) ?? 0;
  double get net => (gross - discount) < 0 ? 0 : (gross - discount);

  Future<void> _saveSale() async {
    if (selectedTicket == null) {
      _msg('Ticket select karo');
      return;
    }
    if (selectedItem == null) {
      _msg('Item select karo');
      return;
    }
    if (qty <= 0) {
      _msg('Qty sahi bharo');
      return;
    }

    setState(() => saving = true);

    try {
      final now = DateTime.now();
      final sale = await supabase
          .from('addon_sales')
          .insert({
            'branch_code': widget.branchCode,
            'department': widget.department,
            'ticket_id': selectedTicket!['id'],
            'ticket_no': selectedTicket!['ticket_no'],
            'sale_date': _dateOnly(now),
            'sale_time': now.toIso8601String(),
            'gross_amount': gross,
            'discount_amount': discount,
            'net_amount': net,
            'payment_mode': paymentMode,
            'created_by': widget.username,
          })
          .select()
          .single();

      await supabase.from('addon_sale_items').insert({
        'addon_sale_id': sale['id'],
        'item_id': selectedItem!['id'],
        'item_name': selectedItem!['item_name'],
        'qty': qty,
        'rate': rate,
        'line_total': gross,
      });

      final percent = widget.department == 'VR' ? 20.0 : 10.0;

      // Database trigger enforces PHOTO=10% and VR=20%.
      await supabase.from('addon_commissions').insert({
        'branch_code': widget.branchCode,
        'department': widget.department,
        'addon_sale_id': sale['id'],
        'ticket_no': selectedTicket!['ticket_no'],
        'agent_id': selectedTicket!['agent_id'],
        'sale_date': _dateOnly(now),
        'net_amount': net,
        'commission_percent': percent,
        'commission_amount': net * percent / 100,
        'status': 'PENDING',
      });

      searchCtl.clear();
      qtyCtl.text = '1';
      discountCtl.text = '0';
      setState(() {
        selectedTicket = null;
        selectedItemId = null;
        ticketMatches = [];
        paymentMode = 'Cash';
      });

      _msg('${widget.department} sale saved');
    } catch (e) {
      _msg('Sale save error: $e');
    }

    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchCtl,
                          decoration: const InputDecoration(
                            labelText: 'Ticket Search • Last Number',
                            hintText: 'Example: 0015',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _searchTicket(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _searchTicket,
                        icon: const Icon(Icons.search),
                        label: const Text('Search'),
                      ),
                    ],
                  ),
                  if (ticketMatches.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedTicket?['id']?.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Aaj ka Ticket',
                        border: OutlineInputBorder(),
                      ),
                      items: ticketMatches
                          .map(
                            (t) => DropdownMenuItem<String>(
                              value: t['id'].toString(),
                              child: Text(
                                '${t['ticket_no']} • Main Ticket ₹${_num(t['final_amount']).toStringAsFixed(2)}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        setState(() {
                          selectedTicket = ticketMatches
                              .firstWhere((e) => e['id'].toString() == id);
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedItemId,
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      border: OutlineInputBorder(),
                    ),
                    items: items
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text(
                              '${e['item_name']} • ₹${_num(e['rate']).toStringAsFixed(2)}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => selectedItemId = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: qtyCtl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Rate',
                            border: OutlineInputBorder(),
                          ),
                          child: Text('₹${rate.toStringAsFixed(2)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Gross',
                            border: OutlineInputBorder(),
                          ),
                          child: Text('₹${gross.toStringAsFixed(2)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: discountCtl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Discount',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: paymentMode,
                          decoration: const InputDecoration(
                            labelText: 'Payment Mode',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Cash',
                              child: Text('Cash'),
                            ),
                            DropdownMenuItem(
                              value: 'UPI',
                              child: Text('UPI'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => paymentMode = v ?? 'Cash'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Net Amount',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            '₹${net.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saving ? null : _saveSale,
                      icon: const Icon(Icons.save),
                      label: Text(saving ? 'Saving...' : 'Save Sale'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddonReportTab extends StatefulWidget {
  final String username;
  final String branchCode;
  final String department;
  final bool summaryOnly;

  const _AddonReportTab({
    required this.username,
    required this.branchCode,
    required this.department,
    required this.summaryOnly,
  });

  @override
  State<_AddonReportTab> createState() => _AddonReportTabState();
}

class _AddonReportTabState extends State<_AddonReportTab> {
  final supabase = Supabase.instance.client;

  DateTime from = DateTime.now();
  DateTime to = DateTime.now();
  bool loading = true;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> agents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = await supabase
          .from('addon_sales')
          .select('*, addon_sale_items(*)')
          .eq('branch_code', widget.branchCode)
          .eq('department', widget.department)
          .gte('sale_date', _dateOnly(from))
          .lte('sale_date', _dateOnly(to))
          .order('sale_time', ascending: false);

      rows = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _msg('Report load error: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        from = d;
        if (to.isBefore(from)) to = from;
      } else {
        to = d;
        if (from.isAfter(to)) from = to;
      }
    });
    await _load();
  }

  double get total => rows.fold(0, (s, e) => s + _num(e['net_amount']));
  double get gross => rows.fold(0, (s, e) => s + _num(e['gross_amount']));
  double get discount =>
      rows.fold(0, (s, e) => s + _num(e['discount_amount']));
  double get cash => rows
      .where((e) => (e['payment_mode'] ?? '').toString() == 'Cash')
      .fold(0, (s, e) => s + _num(e['net_amount']));
  double get upi => rows
      .where((e) => (e['payment_mode'] ?? '').toString() == 'UPI')
      .fold(0, (s, e) => s + _num(e['net_amount']));

  Map<String, Map<String, double>> grouped() {
    final map = <String, Map<String, double>>{};
    for (final e in rows) {
      final d = (e['sale_date'] ?? '').toString();
      map.putIfAbsent(
        d,
        () => {'gross': 0, 'discount': 0, 'net': 0, 'cash': 0, 'upi': 0},
      );
      final m = map[d]!;
      m['gross'] = m['gross']! + _num(e['gross_amount']);
      m['discount'] = m['discount']! + _num(e['discount_amount']);
      m['net'] = m['net']! + _num(e['net_amount']);
      if ((e['payment_mode'] ?? '').toString() == 'Cash') {
        m['cash'] = m['cash']! + _num(e['net_amount']);
      }
      if ((e['payment_mode'] ?? '').toString() == 'UPI') {
        m['upi'] = m['upi']! + _num(e['net_amount']);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final dayGroups = grouped().entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pick(true),
                    icon: const Icon(Icons.date_range),
                    label: Text('From: ${_dateOnly(from)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(false),
                    icon: const Icon(Icons.date_range),
                    label: Text('To: ${_dateOnly(to)}'),
                  ),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _stat('Gross', gross),
                  _stat('Discount', discount),
                  _stat('Net Sale', total),
                  _stat('Cash', cash),
                  _stat('UPI', upi),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : widget.summaryOnly
                  ? ListView.separated(
                      itemCount: dayGroups.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = dayGroups[i];
                        final m = e.value;
                        return ListTile(
                          title: Text(e.key),
                          subtitle: Text(
                            'Gross ₹${m['gross']!.toStringAsFixed(2)} | '
                            'Discount ₹${m['discount']!.toStringAsFixed(2)} | '
                            'Cash ₹${m['cash']!.toStringAsFixed(2)} | '
                            'UPI ₹${m['upi']!.toStringAsFixed(2)}',
                          ),
                          trailing: Text(
                            '₹${m['net']!.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final itemRows = (r['addon_sale_items'] is List)
                            ? List<Map<String, dynamic>>.from(
                                r['addon_sale_items'] as List,
                              )
                            : <Map<String, dynamic>>[];
                        final itemText = itemRows
                            .map(
                              (x) =>
                                  '${x['item_name']} x${_num(x['qty']).toStringAsFixed(0)}',
                            )
                            .join(', ');

                        return ListTile(
                          title: Text(
                            '${r['ticket_no']} • ₹${_num(r['net_amount']).toStringAsFixed(2)}',
                          ),
                          subtitle: Text(
                            '${r['sale_date']} • $itemText • '
                            'Disc ₹${_num(r['discount_amount']).toStringAsFixed(2)} • '
                            '${r['payment_mode']} • ${r['created_by'] ?? ''}',
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _AddonCommissionTab extends StatefulWidget {
  final String username;
  final String branchCode;
  final String department;

  const _AddonCommissionTab({
    required this.username,
    required this.branchCode,
    required this.department,
  });

  @override
  State<_AddonCommissionTab> createState() => _AddonCommissionTabState();
}

class _AddonCommissionTabState extends State<_AddonCommissionTab> {
  final supabase = Supabase.instance.client;
  final searchCtl = TextEditingController();

  DateTime from = DateTime.now();
  DateTime to = DateTime.now();

  bool loading = true;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> agents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchCtl.dispose();
    super.dispose();
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = await supabase
          .from('addon_commissions')
          .select()
          .eq('branch_code', widget.branchCode)
          .eq('department', widget.department)
          .gte('sale_date', _dateOnly(from))
          .lte('sale_date', _dateOnly(to))
          .order('created_at', ascending: false);

      final agentData = await supabase
          .from('agents')
          .select('id, agent_name, agent_code')
          .eq('branch_code', widget.branchCode);

      rows = List<Map<String, dynamic>>.from(data);
      agents = List<Map<String, dynamic>>.from(agentData);
    } catch (e) {
      _msg('Commission load error: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  Map<String, dynamic>? _agentFor(Map<String, dynamic> row) {
    final id = (row['agent_id'] ?? '').toString();
    if (id.isEmpty) return null;
    for (final a in agents) {
      if ((a['id'] ?? '').toString() == id) return a;
    }
    return null;
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        from = d;
        if (to.isBefore(from)) to = from;
      } else {
        to = d;
        if (from.isAfter(to)) from = to;
      }
    });
    await _load();
  }

  List<Map<String, dynamic>> get filtered {
    final q = searchCtl.text.trim().toLowerCase();
    if (q.isEmpty) return rows;

    return rows.where((r) {
      final agent = _agentFor(r);
      final hay = [
        r['ticket_no'],
        agent?['agent_name'],
        agent?['agent_code'],
        r['paid_to_name'],
        r['paid_to_id'],
        r['status'],
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  double get pending => rows
      .where((r) => (r['status'] ?? '') == 'PENDING')
      .fold(0, (s, r) => s + _num(r['commission_amount']));

  double get paid => rows
      .where((r) => (r['status'] ?? '') == 'PAID')
      .fold(0, (s, r) => s + _num(r['commission_amount']));

  Future<void> _markPaid(Map<String, dynamic> row) async {
    final agent = _agentFor(row);
    final agentName = (agent?['agent_name'] ?? '').toString().trim();
    final agentCode = (agent?['agent_code'] ?? '').toString().trim();

    if (agent == null || agentName.isEmpty) {
      _msg(
        'Is ticket me agent link nahi mila. Pehle main ticket commission me agent check karo.',
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pay Commission • ${row['ticket_no']}'),
        content: Text(
          'Sale Date: ${row['sale_date']}\n'
          'Agent: $agentName (${agentCode.isEmpty ? '-' : agentCode})\n'
          'Net: ₹${_num(row['net_amount']).toStringAsFixed(2)}\n'
          'Commission: ${_num(row['commission_percent']).toStringAsFixed(0)}% = '
          '₹${_num(row['commission_amount']).toStringAsFixed(2)}\n\n'
          'Isi linked agent ko commission paid mark karna hai?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Paid'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final paidAt = DateTime.now();
      final category = widget.department == 'VR'
          ? 'VR Commission Paid'
          : 'Photo Commission Paid';

      await supabase
          .from('addon_commissions')
          .update({
            'status': 'PAID',
            'paid_to_name': agentName,
            'paid_to_id': agentCode,
            'paid_at': paidAt.toIso8601String(),
            'paid_by': widget.username,
          })
          .eq('id', row['id'])
          .eq('status', 'PENDING');

      await supabase.from('transactions').insert({
        'branch_code': widget.branchCode,
        'tx_date': paidAt.toIso8601String(),
        'flow_type': 'OUT',
        'category': category,
        'amount': _num(row['commission_amount']),
        'note':
            '${widget.department} commission | Ticket ${row['ticket_no']} | '
            'Sale date ${row['sale_date']} | Agent $agentName ($agentCode)',
        'person_name': agentName,
        'created_by': widget.username,
        'payment_method': 'Cash',
      });

      await _load();
      _msg('Commission paid: $agentName ($agentCode)');
    } catch (e) {
      _msg('Commission payment error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pick(true),
                    icon: const Icon(Icons.date_range),
                    label: Text('Sale From: ${_dateOnly(from)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(false),
                    icon: const Icon(Icons.date_range),
                    label: Text('Sale To: ${_dateOnly(to)}'),
                  ),
                  _stat('Pending', pending),
                  _stat('Paid', paid),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: searchCtl,
                decoration: const InputDecoration(
                  labelText: 'Search Ticket / Name / ID',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = list[i];
                    final isPaid = (r['status'] ?? '') == 'PAID';

                    return ListTile(
                      title: Text(
                        '${r['ticket_no']} • Net ₹${_num(r['net_amount']).toStringAsFixed(2)} • '
                        '${_num(r['commission_percent']).toStringAsFixed(0)}% = '
                        '₹${_num(r['commission_amount']).toStringAsFixed(2)}',
                      ),
                      subtitle: Builder(
                        builder: (_) {
                          final agent = _agentFor(r);
                          final agentName =
                              (agent?['agent_name'] ?? '-').toString();
                          final agentCode =
                              (agent?['agent_code'] ?? '-').toString();

                          return Text(
                            isPaid
                                ? 'Sale: ${r['sale_date']} | Agent: $agentName ($agentCode) | '
                                    'PAID: ${_fmtDt(r['paid_at'])} | By ${r['paid_by']}'
                                : 'Sale: ${r['sale_date']} | Agent: $agentName ($agentCode) | PENDING',
                          );
                        },
                      ),
                      trailing: isPaid
                          ? const Chip(label: Text('PAID'))
                          : FilledButton(
                              onPressed: () => _markPaid(r),
                              child: const Text('Pay'),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Widget _stat(String title, double value) {
  return Chip(
    label: Text('$title: ₹${value.toStringAsFixed(2)}'),
  );
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse((v ?? '').toString()) ?? 0;
}

String _fmtDt(dynamic value) {
  final s = (value ?? '').toString();
  if (s.isEmpty) return '-';
  try {
    final d = DateTime.parse(s).toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return s;
  }
}
