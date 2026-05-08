import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../widgets/stat_card.dart';
import '../widgets/category_card.dart';
import '../widgets/recent_order_card.dart';
import '../widgets/drawer_menu.dart';
import '../services/database_helper.dart';
import '../services/financial_calculator.dart';
import '../services/sync_service.dart';
import '../services/low_stock_service.dart';
import '../utils/app_date_filter.dart';
import 'orders_list_screen.dart';
import 'profit_details_screen.dart';
import 'shipment_dashboard_screen.dart';

class ManagerHome extends StatefulWidget {
  const ManagerHome({Key? key}) : super(key: key);

  @override
  _ManagerHomeState createState() => _ManagerHomeState();
}

class _ManagerHomeState extends State<ManagerHome> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Timer? _lowStockTimer;
  StreamSubscription<bool>? _dataChangedSubscription;
  bool _initialSyncTriggered = false;

  String _managerName = 'Manager';
  String _branchName = 'Branch';
  bool _isLoading = true;

  // Stats data (combined)
  int _totalOrders = 0;
  int _pendingOrders = 0;
  int _completedOrders = 0;
  int _returnedCount = 0;
  int _withDriverCount = 0;
  int _processingCount = 0;
  int _cancelledBefore = 0;
  int _cancelledAfter = 0;
  double _totalRevenue = 0.0;
  double _salesTotal = 0.0;
  double _toCollectAmount =
      0.0; // pending + processing + out_for_delivery amounts
  double _totalExpenses = 0.0;
  double _profit = 0.0;
  double _cogs = 0.0;
  double _otherExpenses = 0.0;
  double _losses = 0.0;
  double _grossProfit = 0.0;
  double _netProfit = 0.0;
  double _cancelledPayments = 0.0;
  double _cogsFromOrders = 0.0;
  double _tailorCommissions = 0.0;
  double _salesCommissions = 0.0;
  double _deliveryCommissions = 0.0;
  double _commissionExpenses = 0.0;
  double _fuelExpenses = 0.0;
  double _maintenanceExpenses = 0.0;
  double _materialExpenses = 0.0;
  double _weekProfit = 0.0;
  List<Map<String, dynamic>> _expenseItems = [];
  List<Map<String, dynamic>> _orderProfitItems = [];
  List<Map<String, dynamic>> _recentOrders = [];
  double _rentalIncome = 0.0;
  double _rentalExpense = 0.0;
  double _rentalNet = 0.0;
  double _tenantOverdue = 0.0;
  double _landlordOverdue = 0.0;
  double _rentalOccupancyRate = 0.0;

  @override
  void initState() {
    super.initState();
    _loadManagerData();
    _loadStatsEnhanced();
    _loadRentalSummary();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      _loadStatsEnhanced();
      _loadRentalSummary();
    });
    _startLowStockPeriodicCheck();
  }

  void _startLowStockPeriodicCheck() {
    _lowStockTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      await LowStockService().checkAndNotify();
    });
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    _lowStockTimer?.cancel();
    _dataChangedSubscription?.cancel();
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    _loadStatsEnhanced();
  }

  Future<void> _triggerInitialSync() async {
    if (_initialSyncTriggered) return;
    _initialSyncTriggered = true;
    await _syncService.syncAll();
  }

  double _asDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

  int _asInt(dynamic value) => (value as num?)?.toInt() ?? 0;

  Stream<List<Map<String, dynamic>>> _getLowStockStream() async* {
    while (true) {
      var products = await _dbHelper.query('products');
      var materials = await _dbHelper.query('materials');
      List<Map<String, dynamic>> lowStock = [];
      lowStock.addAll(
        products.where((p) => (p['stock'] ?? 0) < (p['minimumLevel'] ?? 5)),
      );
      lowStock.addAll(
        materials.where((m) => (m['stock'] ?? 0) < (m['minimumLevel'] ?? 5)),
      );
      yield lowStock;
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  Future<void> _loadManagerData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            _managerName = userDoc.get('name') ?? 'Manager';
            _branchName = userDoc.get('branchId') ?? 'Branch';
            _isLoading = false;
          });
          await _triggerInitialSync();
          _loadStatsEnhanced();
        } else {
          setState(() => _isLoading = false);
          await _triggerInitialSync();
          _loadStatsEnhanced();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading manager data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    await _loadStatsEnhanced();
  }

  Future<void> _loadStatsEnhanced() async {
    final selectedRange = AppDateFilter.instance.range;
    final startMillis = selectedRange == null
        ? 0
        : DateTime(
            selectedRange.start.year,
            selectedRange.start.month,
            selectedRange.start.day,
          ).millisecondsSinceEpoch;
    final endMillis = selectedRange == null
        ? DateTime.now().millisecondsSinceEpoch
        : DateTime(
            selectedRange.end.year,
            selectedRange.end.month,
            selectedRange.end.day,
            23,
            59,
            59,
            999,
          ).millisecondsSinceEpoch;
    final summary = await FinancialCalculator().calculateSummary(
      range: selectedRange,
      branchId: _branchName,
    );
    final ordersList = await _dbHelper.getOrdersInDateRange(
      startMillis,
      endMillis,
      branchId: _branchName,
    );

    int total = 0;
    int pending = 0;
    int completed = 0;
    int withDriver = 0;
    int processingCount = 0;
    int returned = 0;
    int cancelledBefore = 0;
    int cancelledAfter = 0;
    double toCollect = 0.0;
    for (final order in ordersList) {
      total++;
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      final totalAmount = _asDouble(order['totalAmount']);
      final paid = _asDouble(order['paid_amount']);
      switch (status) {
        case 'pending':
          pending++;
          break;
        case 'processing':
          processingCount++;
          break;
        case 'out_for_delivery':
          withDriver++;
          break;
        case 'completed':
        case 'delivered':
          completed++;
          break;
        case 'cancelled':
          final stockDeducted = (order['stock_deducted'] as num?)?.toInt() ?? 0;
          if (stockDeducted == 0) {
            cancelledBefore++;
          } else {
            cancelledAfter++;
          }
          break;
        case 'returned':
          returned++;
          break;
      }
      if (status != 'cancelled' && status != 'returned' && paid < totalAmount) {
        toCollect += (totalAmount - paid);
      }
    }

    ordersList.sort(
      (a, b) => _asInt(b['createdAt']).compareTo(_asInt(a['createdAt'])),
    );

    setState(() {
      _totalOrders = total;
      _pendingOrders = pending;
      _completedOrders = completed;
      _returnedCount = returned;
      _withDriverCount = withDriver;
      _processingCount = processingCount;
      _cancelledBefore = cancelledBefore;
      _cancelledAfter = cancelledAfter;
      _totalRevenue = summary.revenue;
      _salesTotal = summary.salesTotal;
      _toCollectAmount = toCollect;
      _cogs = summary.cogs;
      _cogsFromOrders = summary.cogsFromOrders;
      _tailorCommissions = summary.tailorCommissions;
      _salesCommissions = summary.salesCommissions;
      _deliveryCommissions = summary.deliveryCommissions;
      _commissionExpenses = summary.commissionExpenses;
      _fuelExpenses = summary.fuelExpenses;
      _maintenanceExpenses = summary.maintenanceExpenses;
      _materialExpenses = summary.materialExpenses;
      _otherExpenses = summary.otherExpenses;
      _losses = summary.losses;
      _grossProfit = summary.grossProfit;
      _cancelledPayments = summary.cancelledPayments;
      _netProfit = summary.netProfit;
      _totalExpenses = summary.totalExpenses;
      _profit = summary.netProfit;
      _weekProfit = summary.weekProfit;
      _expenseItems = summary.expenseItems.map((item) => item.toMap()).toList();
      _orderProfitItems = summary.orderProfitItems
          .map((item) => item.toMap())
          .toList();
      _recentOrders = ordersList.take(5).toList();
    });
  }

  // ========== NAVIGATION HELPERS ==========
  void _navigateToCreateOrder() {
    Navigator.pushNamed(context, '/create-order');
  }

  void _navigateToOrdersWithStatus(String? status) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrdersListScreen(
          initialStatus: status,
          hideStatusFilter: status != null,
        ),
      ),
    );
  }

  void _navigateToUnpaidOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OrdersListScreen(
          showUnpaidOnly: true,
          hideStatusFilter: true,
        ),
      ),
    );
  }

  void _navigateToOrders() {
    Navigator.pushNamed(context, '/orders');
  }

  void _navigateToInventory() {
    Navigator.pushNamed(context, '/inventory');
  }

  void _navigateToReports() {
    Navigator.pushNamed(context, '/reports');
  }

  void _navigateToShipments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShipmentDashboardScreen(
          initialBranchId: _branchName,
          lockBranchFilter: true,
        ),
      ),
    );
  }

  void _navigateToProperties() {
    Navigator.pushNamed(context, '/properties');
  }

  void _navigateToEmployees() {
    Navigator.pushNamed(context, '/employees');
  }

  void _showCogsBreakdown() {
    showDialog(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text(
            'Cost of Goods Sold (COGS) Breakdown',
            style: TextStyle(color: Colors.black),
          ),
          content: Text(
            'Product COGS: ETB ${_cogsFromOrders.toStringAsFixed(2)}\n'
            'Materials Used: ETB ${_materialExpenses.toStringAsFixed(2)}\n'
            'Tailor Commissions: ETB ${_tailorCommissions.toStringAsFixed(2)}\n'
            'Total COGS: ETB ${_cogs.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.black),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showProfitDialog() {
    _navigateToProfitDetails();
  }

  Future<void> _loadRentalSummary() async {
    try {
      final rentPayments = await _dbHelper.query('rent_payments');
      final landlordPayments = await _dbHelper.query('landlord_payments');
      final properties = await _dbHelper.query('properties');
      final rentDues = await _dbHelper.query('rent_dues');
      final landlordDues = await _dbHelper.query('landlord_dues');

      final now = DateTime.now();
      final currentMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      double income = 0;
      for (final payment in rentPayments) {
        if (payment['month'] == currentMonth) {
          income += (payment['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      double expense = 0;
      for (final payment in landlordPayments) {
        if (payment['month'] == currentMonth) {
          expense += (payment['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      double tenantOverdue = 0;
      for (final d in rentDues) {
        final property = properties.firstWhere(
          (p) => p['id'] == d['propertyId'],
          orElse: () => <String, dynamic>{},
        );
        final usageType =
            property['usageType']?.toString() ??
            (property['ownership'] == 'leased' ? 'business_use' : 'rented_out');
        if (usageType != 'rented_out') continue;
        if (d['status'] == 'pending' &&
            (d['dueDate'] as int) < now.millisecondsSinceEpoch) {
          tenantOverdue += (d['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      double landlordOverdue = 0;
      for (final due in landlordDues) {
        if (due['status'] == 'pending' &&
            (due['dueDate'] as int) < now.millisecondsSinceEpoch) {
          landlordOverdue += (due['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      final rentalProperties = properties.where((p) {
        final usageType =
            p['usageType']?.toString() ??
            (p['ownership'] == 'leased' ? 'business_use' : 'rented_out');
        return usageType == 'rented_out';
      }).toList();
      final total = rentalProperties.length;
      final occupied = rentalProperties
          .where((p) => p['status'] == 'occupied')
          .length;

      if (!mounted) return;
      setState(() {
        _rentalIncome = income;
        _rentalExpense = expense;
        _rentalNet = income - expense;
        _tenantOverdue = tenantOverdue;
        _landlordOverdue = landlordOverdue;
        _rentalOccupancyRate = total > 0 ? (occupied / total) * 100 : 0;
      });
    } catch (e) {
      print('Error loading rental summary: $e');
    }
  }

  void _navigateToProfitDetails() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProfitDetailsScreen(
        branchId: _branchName,  // The manager's fixed branch ID (String? variable)
      ),
    ),
  );
}

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DrawerMenu(role: 'manager'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 180.0,
                    floating: false,
                    pinned: true,
                    backgroundColor: Colors.transparent,
                    leading: Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu, color: AppColors.white),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.logout, color: AppColors.white),
                        onPressed: _logout,
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(color: Colors.transparent),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Low Stock Banner
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _getLowStockStream(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const SizedBox();
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.2),
                                border: Border.all(color: AppColors.warning),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '⚠️ Low Stock Alert',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...snapshot.data!.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '${item['name']}: ${item['stock']} remaining',
                                        style: const TextStyle(
                                          color: AppColors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // Branch Info Card
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: AppColors.primaryRed
                                      .withOpacity(0.1),
                                  child: const Icon(
                                    Icons.store,
                                    color: AppColors.primaryRed,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _managerName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkGrey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Manager · $_branchName',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.mediumGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text(
                          'Good day, $_managerName!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Here\'s your branch performance.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 24),

                        _buildQuickActions(),
                        const SizedBox(height: 24),

                        // Consolidated Stats Grid
                        _buildStatsGrid(),
                        const SizedBox(height: 24),

                        _buildFinancialGrid(),
                        const SizedBox(height: 24),

                        _buildRentalSummary(),
                        const SizedBox(height: 24),

                        _buildCategoriesSection(),
                        const SizedBox(height: 24),

                        _buildRecentOrdersSection(),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateOrder,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: AppColors.white),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 0, right: 60),
            children: [
              _buildQuickActionCard(
                Icons.shopping_bag,
                'New Order',
                AppColors.primaryRed,
                _navigateToCreateOrder,
              ),
              _buildQuickActionCard(
                Icons.inventory,
                'Inventory',
                AppColors.info,
                _navigateToInventory,
              ),
              _buildQuickActionCard(
                Icons.people,
                'Staff',
                AppColors.success,
                _navigateToEmployees,
              ),
              _buildQuickActionCard(
                Icons.receipt,
                'Reports',
                AppColors.accent,
                _navigateToReports,
              ),
              _buildQuickActionCard(
                Icons.local_shipping,
                'Shipments',
                AppColors.warning,
                _navigateToShipments,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 10),
      child: Card(
        elevation: 3,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
          child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGrey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Consolidated stats grid for manager
  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Branch Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            // Total Orders → all orders
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus(null),
              child: StatCard(
                title: 'Total Orders',
                value: _totalOrders.toString(),
                icon: Icons.shopping_bag,
                color: AppColors.primaryRed,
              ),
            ),
            // Total Revenue → reports
            GestureDetector(
              onTap: _navigateToReports,
              child: StatCard(
                title: 'Revenue',
                value: 'ETB ${_totalRevenue.toStringAsFixed(0)}',
                icon: Icons.attach_money,
                color: AppColors.success,
              ),
            ),
            // Pending Orders → pending filter
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus('pending'),
              child: StatCard(
                title: 'Pending',
                value: _pendingOrders.toString(),
                icon: Icons.pending_actions,
                color: AppColors.warning,
              ),
            ),
            // Completed Orders → delivered filter
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus('delivered'),
              child: StatCard(
                title: 'Completed',
                value: _completedOrders.toString(),
                icon: Icons.check_circle,
                color: AppColors.info,
              ),
            ),
            // To Collect (amount) → pending/processing/out_for_delivery filter
            GestureDetector(
              onTap: _navigateToUnpaidOrders,
              child: StatCard(
                title: 'To Collect',
                value: 'ETB ${_toCollectAmount.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet,
                color: AppColors.accent,
              ),
            ),
            // With Driver → out_for_delivery filter
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus('out_for_delivery'),
              child: StatCard(
                title: 'With Driver',
                value: _withDriverCount.toString(),
                icon: Icons.delivery_dining,
                color: AppColors.primaryRed,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(
                          Icons.cancel,
                          color: AppColors.error,
                          size: 20,
                        ),
                        Text(
                          '${_cancelledBefore + _cancelledAfter}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGrey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cancelled',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mediumGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_cancelledBefore before / $_cancelledAfter after',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinancialGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Financial Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.white.withOpacity(0.1),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showProfitDialog,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      size: 28,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Financial Summary',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'View breakdown by currency',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
        if (_cancelledPayments > 0) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notice: ETB ${_cancelledPayments.toStringAsFixed(0)} was received on cancelled orders and may need refund handling.',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRentalSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Rental Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: _navigateToProperties,
                  child: const Text('Manage >'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRentalStat(
                  'Income',
                  'ETB ${_rentalIncome.toStringAsFixed(0)}',
                  Icons.arrow_upward,
                  AppColors.success,
                ),
                _buildRentalStat(
                  'Expense',
                  'ETB ${_rentalExpense.toStringAsFixed(0)}',
                  Icons.arrow_downward,
                  AppColors.error,
                ),
                _buildRentalStat(
                  'Net',
                  'ETB ${_rentalNet.toStringAsFixed(0)}',
                  Icons.account_balance,
                  _rentalNet >= 0 ? AppColors.success : AppColors.error,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRentalStat(
                  'Tenants Due',
                  'ETB ${_tenantOverdue.toStringAsFixed(0)}',
                  Icons.warning,
                  AppColors.warning,
                ),
                _buildRentalStat(
                  'We Owe',
                  'ETB ${_landlordOverdue.toStringAsFixed(0)}',
                  Icons.payments,
                  AppColors.error,
                ),
                _buildRentalStat(
                  'Occupancy',
                  '${_rentalOccupancyRate.toStringAsFixed(1)}%',
                  Icons.percent,
                  AppColors.info,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentalStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Order Categories',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            TextButton(
              onPressed: _navigateToOrders,
              child: const Text(
                'See All >',
                style: TextStyle(color: AppColors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _navigateToOrdersWithStatus('out_for_delivery'),
                child: CategoryCard(
                  title: 'To Deliver',
                  count: _withDriverCount.toString(),
                  color: AppColors.primaryRed,
                  icon: Icons.delivery_dining,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _navigateToOrdersWithStatus('processing'),
                child: CategoryCard(
                  title: 'Processing',
                  count: _processingCount.toString(),
                  color: AppColors.warning,
                  icon: Icons.pending,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _navigateToOrdersWithStatus('delivered'),
                child: CategoryCard(
                  title: 'Delivered',
                  count: _completedOrders.toString(),
                  color: AppColors.success,
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _navigateToOrdersWithStatus('returned'),
                child: CategoryCard(
                  title: 'Returned',
                  count: _returnedCount.toString(),
                  color: AppColors.error,
                  icon: Icons.assignment_return,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentOrdersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Orders',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            TextButton(
              onPressed: _navigateToOrders,
              child: const Text(
                'View All',
                style: TextStyle(color: AppColors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _recentOrders.isEmpty
            ? Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'No orders yet',
                    style: TextStyle(color: AppColors.mediumGrey),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentOrders.length,
                itemBuilder: (context, index) {
                  var order = _recentOrders[index];
                  return GestureDetector(
                    onTap: _navigateToOrders,
                    child: RecentOrderCard(
                      orderId: order['id'],
                      customer: order['customerName'] ?? 'Unknown',
                      amount:
                          'ETB ${(order['totalAmount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      status: order['status'] ?? 'pending',
                    ),
                  );
                },
              ),
      ],
    );
  }
}
