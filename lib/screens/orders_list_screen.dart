import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
import '../utils/currency_helper.dart';
import '../utils/app_date_filter.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import 'order_details_screen.dart';
import 'scanner_screen.dart';

class OrdersListScreen extends StatefulWidget {
  final String? initialStatus;
  final bool showUnpaidOnly;
  final bool hideStatusFilter;
  const OrdersListScreen({
    super.key,
    this.initialStatus,
    this.showUnpaidOnly = false,
    this.hideStatusFilter = false,
  });

  @override
  _OrdersListScreenState createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _commissions = [];
  List<Map<String, dynamic>> _filteredCommissions = [];
  bool _isLoading = true;
  StreamSubscription<bool>? _dataChangedSubscription;
  String _filterStatus = 'all';
  String _filterBranch = 'all';
  String _filterEmployee = 'all';
  String _filterRole = 'all';
  final TextEditingController _searchController = TextEditingController();

  bool get _showEmployeeEarnings => _filterEmployee != 'all';

  @override
  void initState() {
    super.initState();
    _filterStatus = widget.initialStatus ?? 'all';
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _loadOrders();
    _loadBranches();
    _loadEmployees();
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      if (!mounted) return;
      _loadOrders();
      _loadBranches();
      _loadEmployees();
    });
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    _dataChangedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    _applyFilters();
  }

  Future<void> _loadOrders() async {
    if (mounted) setState(() => _isLoading = true);
    var orders = List<Map<String, dynamic>>.from(
      await _dbHelper.query('orders'),
    );
    var assignments = await _dbHelper.query('order_assignments');
    var commissions = List<Map<String, dynamic>>.from(
      await _dbHelper.query('commissions'),
    );
    if (widget.showUnpaidOnly) {
      orders = orders.where((order) {
        final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final status = (order['status'] as String?)?.toLowerCase() ?? '';
        return paid < total && status != 'cancelled' && status != 'returned';
      }).toList();
    }
    orders.sort(
      (a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int),
    );
    commissions.sort(
      (a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int),
    );
    if (!mounted) return;
    _orders = orders;
    _assignments = List<Map<String, dynamic>>.from(assignments);
    _commissions = commissions;
    _applyFilters();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadBranches() async {
    final branches = await _dbHelper.query('branches');
    if (!mounted) return;
    setState(() {
      _branches = List<Map<String, dynamic>>.from(branches);
    });
  }

  Future<void> _loadEmployees() async {
    final employees = await _dbHelper.query('users');
    if (!mounted) return;
    setState(() {
      _employees = List<Map<String, dynamic>>.from(employees);
    });
  }

  void _applyFilters() {
    var filtered = _orders;
    var filteredCommissions = _commissions;

    final range = AppDateFilter.instance.range;
    if (range != null) {
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      ).millisecondsSinceEpoch;
      final end = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;
      filtered = filtered.where((o) {
        final createdAt = (o['createdAt'] as num?)?.toInt() ?? 0;
        return createdAt >= start && createdAt <= end;
      }).toList();
      filteredCommissions = filteredCommissions.where((c) {
        final paidAt = (c['paidAt'] as num?)?.toInt();
        final createdAt = (c['createdAt'] as num?)?.toInt();
        final date = paidAt ?? createdAt ?? 0;
        return date >= start && date <= end;
      }).toList();
    }

    if (widget.showUnpaidOnly) {
      filtered = filtered.where((order) {
        final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final status = (order['status'] as String?)?.toLowerCase() ?? '';
        return paid < total && status != 'cancelled' && status != 'returned';
      }).toList();
    }

    if (_filterStatus != 'all') {
      filtered = filtered.where((o) => o['status'] == _filterStatus).toList();
      final matchingOrderIds = _orders
          .where((o) => o['status'] == _filterStatus)
          .map((o) => o['id'])
          .toSet();
      filteredCommissions = filteredCommissions
          .where((c) => matchingOrderIds.contains(c['orderId']))
          .toList();
    }

    if (_filterBranch != 'all') {
      filtered = filtered.where((o) => o['branchId'] == _filterBranch).toList();
      final matchingOrderIds = _orders
          .where((o) => o['branchId'] == _filterBranch)
          .map((o) => o['id'])
          .toSet();
      filteredCommissions = filteredCommissions
          .where((c) => matchingOrderIds.contains(c['orderId']))
          .toList();
    }

    if (_filterRole != 'all') {
      final roleEmployeeIds = _employees
          .where((e) => e['role'] == _filterRole)
          .map((e) => e['id'])
          .toSet();
      final orderIds = _assignments
          .where((a) => roleEmployeeIds.contains(a['employeeId']))
          .map((a) => a['orderId'])
          .toSet();
      filtered = filtered.where((o) => orderIds.contains(o['id'])).toList();
      filteredCommissions = filteredCommissions
          .where((c) => c['type'] == _filterRole)
          .toList();
    }

    if (_filterEmployee != 'all') {
      final orderIds = _assignments
          .where((a) => a['employeeId'] == _filterEmployee)
          .map((a) => a['orderId'])
          .toSet();
      filtered = filtered.where((o) => orderIds.contains(o['id'])).toList();
      filteredCommissions = filteredCommissions
          .where((c) => c['employeeId'] == _filterEmployee)
          .toList();
    }

    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((o) {
        return (o['customerName'] ?? '').toLowerCase().contains(query) ||
            (o['id'] ?? '').toLowerCase().contains(query);
      }).toList();
      filteredCommissions = filteredCommissions.where((c) {
        return (c['employeeName'] ?? '').toLowerCase().contains(query) ||
            (c['orderId'] ?? '').toLowerCase().contains(query) ||
            (c['type'] ?? '').toLowerCase().contains(query) ||
            (c['status'] ?? '').toLowerCase().contains(query);
      }).toList();
    }

    if (!mounted) {
      _filteredOrders = filtered;
      _filteredCommissions = filteredCommissions;
      return;
    }
    setState(() {
      _filteredOrders = filtered;
      _filteredCommissions = filteredCommissions;
    });
  }

  void _filterByStatus(String? value) {
    setState(() {
      _filterStatus = value ?? 'all';
    });
    _applyFilters();
  }

  void _filterByBranch(String? value) {
    setState(() {
      _filterBranch = value ?? 'all';
    });
    _applyFilters();
  }

  void _filterByEmployee(String? value) {
    setState(() {
      _filterEmployee = value ?? 'all';
    });
    _applyFilters();
  }

  void _filterByRole(String? value) {
    setState(() {
      _filterRole = value ?? 'all';
    });
    _applyFilters();
  }

  void _search(String query) {
    _applyFilters();
  }

  Future<void> _openManualOrderLookup() async {
    final controller = TextEditingController();
    final orderId = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Enter Order ID'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Order ID',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || orderId == null || orderId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(orderId: orderId),
      ),
    );
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'processing':
        return AppColors.info;
      case 'out_for_delivery':
        return AppColors.accent;
      case 'completed':
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.mediumGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;
    final showingCardFilters = widget.hideStatusFilter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Barcode',
            onPressed: _openScanner,
          ),
          IconButton(
            icon: const Icon(Icons.pin_outlined),
            tooltip: 'Enter Order ID',
            onPressed: _openManualOrderLookup,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(showingCardFilters ? 170 : 220),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by customer or order ID...',
                    hintStyle: TextStyle(
                      color: AppColors.white.withOpacity(0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.white,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.white.withOpacity(0.1),
                  ),
                  onChanged: _search,
                ),
              ),
              Container(
                color: AppColors.primaryRedDark,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!showingCardFilters) ...[
                            const Text(
                              'Status:',
                              style: TextStyle(color: AppColors.white),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _filterStatus,
                              dropdownColor: AppColors.backgroundStart,
                              style: const TextStyle(color: AppColors.white),
                              underline: Container(),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.white,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('All'),
                                ),
                                DropdownMenuItem(
                                  value: 'pending',
                                  child: Text('Pending'),
                                ),
                                DropdownMenuItem(
                                  value: 'processing',
                                  child: Text('Processing'),
                                ),
                                DropdownMenuItem(
                                  value: 'out_for_delivery',
                                  child: Text('Out for Delivery'),
                                ),
                                DropdownMenuItem(
                                  value: 'delivered',
                                  child: Text('Delivered'),
                                ),
                                DropdownMenuItem(
                                  value: 'completed',
                                  child: Text('Completed'),
                                ),
                                DropdownMenuItem(
                                  value: 'cancelled',
                                  child: Text('Cancelled'),
                                ),
                                DropdownMenuItem(
                                  value: 'returned',
                                  child: Text('Returned'),
                                ),
                              ],
                              onChanged: _filterByStatus,
                            ),
                            const SizedBox(width: 16),
                          ],
                          const Text(
                            'Employee:',
                            style: TextStyle(color: AppColors.white),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _filterEmployee,
                            dropdownColor: AppColors.backgroundStart,
                            style: const TextStyle(color: AppColors.white),
                            underline: Container(),
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: AppColors.white,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('All Employees'),
                              ),
                              ..._employees.map(
                                (e) => DropdownMenuItem(
                                  value: e['id'],
                                  child: Text(e['name'] ?? 'Unknown'),
                                ),
                              ),
                            ],
                            onChanged: _filterByEmployee,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'Branch:',
                            style: TextStyle(color: AppColors.white),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _filterBranch,
                            dropdownColor: AppColors.backgroundStart,
                            style: const TextStyle(color: AppColors.white),
                            underline: Container(),
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: AppColors.white,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('All Branches'),
                              ),
                              ..._branches.map(
                                (b) => DropdownMenuItem(
                                  value: b['id'],
                                  child: Text(b['name']),
                                ),
                              ),
                            ],
                            onChanged: _filterByBranch,
                          ),
                          if (!showingCardFilters) ...[
                            const SizedBox(width: 16),
                            const Text(
                              'Role:',
                              style: TextStyle(color: AppColors.white),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _filterRole,
                              dropdownColor: AppColors.backgroundStart,
                              style: const TextStyle(color: AppColors.white),
                              underline: Container(),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.white,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('All Roles'),
                                ),
                                DropdownMenuItem(
                                  value: 'sales',
                                  child: Text('Sales'),
                                ),
                                DropdownMenuItem(
                                  value: 'tailor',
                                  child: Text('Tailor'),
                                ),
                                DropdownMenuItem(
                                  value: 'delivery',
                                  child: Text('Delivery'),
                                ),
                                DropdownMenuItem(
                                  value: 'manager',
                                  child: Text('Manager'),
                                ),
                                DropdownMenuItem(
                                  value: 'admin',
                                  child: Text('Admin'),
                                ),
                              ],
                              onChanged: _filterByRole,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _showEmployeeEarnings
              ? _buildEmployeeEarningsView()
              : filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No orders found.',
                    style: TextStyle(color: AppColors.white),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: AppColors.white, height: 0.5),
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    final total =
                        (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
                    final paid =
                        (order['paid_amount'] as num?)?.toDouble() ?? 0.0;
                    final remaining = total - paid;
                    final createdAt = DateTime.fromMillisecondsSinceEpoch(
                      order['createdAt'],
                    );
                    final dateStr = DateFormat(
                      'dd/MM/yy HH:mm',
                    ).format(createdAt);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 0,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  OrderDetailsScreen(orderId: order['id']),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: _getStatusColor(order['status']),
                          child: Text(
                            (order['id']?.substring(0, 1) ?? '#'),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        title: Text(
                          order['customerName'] ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '#${order['id']?.substring(0, 6)} • $dateStr',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.mediumGrey,
                              ),
                            ),
                            if ((order['status'] as String?)?.toLowerCase() ==
                                    'cancelled' &&
                                paid > 0) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'To Refund',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                            if (widget.showUnpaidOnly) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Remaining: ETB ${remaining.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyHelper.formatAmount(
                                total,
                                order['currency'],
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (widget.showUnpaidOnly && paid > 0)
                              Text(
                                'Paid: ETB ${paid.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.mediumGrey,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(
                                  order['status'],
                                ).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                order['status'] ?? 'pending',
                                style: TextStyle(
                                  color: _getStatusColor(order['status']),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildEmployeeEarningsView() {
    final employee = _employees.cast<Map<String, dynamic>?>().firstWhere(
      (e) => e?['id'] == _filterEmployee,
      orElse: () => null,
    );
    final employeeName = employee?['name'] ?? 'Employee';
    final pendingTotal = _filteredCommissions
        .where((c) => c['status'] == 'pending')
        .fold<double>(
          0.0,
          (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0),
        );
    final paidTotal = _filteredCommissions
        .where((c) => c['status'] == 'paid')
        .fold<double>(
          0.0,
          (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0),
        );

    if (_filteredCommissions.isEmpty) {
      return Center(
        child: Text(
          'No commission records found for $employeeName.',
          style: const TextStyle(color: AppColors.white),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _filteredCommissions.length + 1,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.white, height: 0.5),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$employeeName Earnings',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Pending: ETB ${pendingTotal.toStringAsFixed(0)}'),
                  Text('Paid: ETB ${paidTotal.toStringAsFixed(0)}'),
                ],
              ),
            ),
          );
        }

        final commission = _filteredCommissions[index - 1];
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          commission['createdAt'],
        );
        final dateStr = DateFormat('dd/MM/yy').format(createdAt);
        final amount = (commission['amount'] as num?)?.toDouble() ?? 0.0;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      OrderDetailsScreen(orderId: commission['orderId']),
                ),
              );
            },
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: _getStatusColor(commission['status']),
              child: Text(
                (commission['type'] ?? '?')[0].toUpperCase(),
                style: const TextStyle(color: AppColors.white, fontSize: 14),
              ),
            ),
            title: Text(
              '${commission['type']} commission',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            subtitle: Text(
              'Order #${commission['orderId']?.substring(0, 6)} • $dateStr',
              style: const TextStyle(fontSize: 12, color: AppColors.mediumGrey),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'ETB ${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      commission['status'],
                    ).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    commission['status'] ?? 'pending',
                    style: TextStyle(
                      color: _getStatusColor(commission['status']),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
