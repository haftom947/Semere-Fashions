import 'dart:convert';
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
import '../services/sync_service.dart';
import '../services/low_stock_service.dart';
import '../utils/app_date_filter.dart';
import 'orders_list_screen.dart';
import 'admin_home.dart' show ProfitDetailsScreen;

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
  double _totalRevenue = 0.0;
  double _toCollectAmount =
      0.0; // pending + processing + out_for_delivery amounts
  double _totalExpenses = 0.0;
  double _profit = 0.0;
  double _cogs = 0.0;
  double _otherExpenses = 0.0;
  double _grossProfit = 0.0;
  double _netProfit = 0.0;
  double _cogsFromOrders = 0.0;
  double _tailorCommissions = 0.0;
  double _salesCommissions = 0.0;
  double _commissionExpenses = 0.0;
  double _fuelExpenses = 0.0;
  double _maintenanceExpenses = 0.0;
  double _materialExpenses = 0.0;
  double _weekProfit = 0.0;
  List<Map<String, dynamic>> _expenseItems = [];
  List<Map<String, dynamic>> _orderProfitItems = [];
  List<Map<String, dynamic>> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadManagerData();
    _loadStatsEnhanced();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      _loadStatsEnhanced();
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
    var orders = await _dbHelper.query('orders');
    var payments = await _dbHelper.query('payment_transaction');

    // Filter by branch
    var branchOrders = orders.where((o) => o['branchId'] == _branchName).toList();
    List<Map<String, dynamic>> ordersList = List.from(branchOrders);
    List<Map<String, dynamic>> mutablePayments = List.from(payments);

    print('📊 Loaded ${ordersList.length} orders for branch $_branchName');

    int total = ordersList.length;
    int pending = 0, completed = 0, withDriver = 0, processingCount = 0;
    double revenue = 0.0;
    double toCollect = 0.0;

    // Revenue from payments (only payments related to this branch's orders? Might need filtering)
    for (var p in mutablePayments) {
      double amount = (p['amount'] as num?)?.toDouble() ?? 0;
      if (p['type'] == 'payment') revenue += amount;
      else revenue -= amount;
    }

    // Order counts and to‑collect
    for (var order in ordersList) {
      String status = (order['status'] as String?)?.toLowerCase() ?? '';
      double totalAmount = (order['totalAmount'] as num?)?.toDouble() ?? 0;
      double paid = (order['paid_amount'] as num?)?.toDouble() ?? 0;

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
      }

      // To‑collect: all active orders (not cancelled/returned) with remaining balance
      if (status != 'cancelled' && status != 'returned') {
        if (paid < totalAmount) {
          toCollect += (totalAmount - paid);
        }
      }
    }

    ordersList.sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    var recent = ordersList.take(5).toList();

    setState(() {
      _totalOrders = total;
      _pendingOrders = pending;
      _completedOrders = completed;
      _withDriverCount = withDriver;
      _processingCount = processingCount;
      _totalRevenue = revenue;
      _toCollectAmount = toCollect;
      _recentOrders = recent;
    });
  }

  Future<void> _loadStatsEnhanced() async {
    final orders = await _dbHelper.query('orders');
    final payments = await _dbHelper.query('payment_transaction');
    final commissions = await _dbHelper.query('commissions');
    final fuelLogs = await _dbHelper.query('fuel_logs');
    final maintenanceLogs = await _dbHelper.query('maintenance_logs');
    final materialUsage = await _dbHelper.query('material_usage');
    final materials = await _dbHelper.query('materials');
    final products = await _dbHelper.query('products');

    final branchOrders = orders.where((o) => o['branchId'] == _branchName).toList();
    final ordersList = List<Map<String, dynamic>>.from(branchOrders);
    final mutablePayments = List<Map<String, dynamic>>.from(payments);
    final mutableCommissions = List<Map<String, dynamic>>.from(commissions);
    final mutableFuel = List<Map<String, dynamic>>.from(fuelLogs);
    final mutableMaintenance = List<Map<String, dynamic>>.from(maintenanceLogs);
    final mutableMaterialUsage = List<Map<String, dynamic>>.from(materialUsage);
    final mutableMaterials = List<Map<String, dynamic>>.from(materials);
    final mutableProducts = List<Map<String, dynamic>>.from(products);

    final materialNamesById = <String, String>{
      for (final material in mutableMaterials)
        if ((material['id'] as String?)?.isNotEmpty ?? false)
          material['id'] as String: (material['name'] as String?) ?? material['id'] as String,
    };
    final productById = <String, Map<String, dynamic>>{
      for (final product in mutableProducts)
        if ((product['id'] as String?)?.isNotEmpty ?? false)
          product['id'] as String: product,
    };
    final branchOrderIds = ordersList
        .map((order) => order['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

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

    bool withinSelectedRange(dynamic value) {
      final intValue = (value as num?)?.toInt();
      return intValue != null &&
          intValue >= startMillis &&
          intValue <= endMillis;
    }

    final paymentsByOrderId = <String, double>{};
    for (final payment in mutablePayments) {
      final orderId = payment['orderId']?.toString();
      if (orderId == null || orderId.isEmpty || !branchOrderIds.contains(orderId)) continue;
      if (!withinSelectedRange(payment['date'])) continue;
      final amount = _asDouble(payment['amount']);
      if (payment['type'] == 'payment') {
        paymentsByOrderId[orderId] = (paymentsByOrderId[orderId] ?? 0.0) + amount;
      } else {
        paymentsByOrderId[orderId] = (paymentsByOrderId[orderId] ?? 0.0) - amount;
      }
    }

    final expenseItems = <Map<String, dynamic>>[];
    final orderProfitItems = <Map<String, dynamic>>[];

    double weekRevenue = 0.0;
    for (final payment in mutablePayments) {
      final orderId = payment['orderId']?.toString();
      if (orderId == null || orderId.isEmpty || !branchOrderIds.contains(orderId)) continue;
      if (withinSelectedRange(payment['date'])) {
        final amount = _asDouble(payment['amount']);
        if (payment['type'] == 'payment') {
          weekRevenue += amount;
        } else {
          weekRevenue -= amount;
        }
      }
    }

    double weekExpenses = 0.0;
    for (final order in ordersList) {
      final createdAt = _asInt(order['createdAt']);
      if (!withinSelectedRange(createdAt)) continue;
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      if (status != 'cancelled' && status != 'returned') {
        final cogsAmount = _asDouble(order['cogs']);
        weekExpenses += cogsAmount;

        double itemCogsTotal = 0.0;
        final rawItems = order['items'];
        final orderItems = rawItems is String
            ? (jsonDecode(rawItems) as List<dynamic>)
            : List<dynamic>.from(rawItems as List? ?? const []);
        for (final rawItem in orderItems) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          final productId = item['productId']?.toString();
          if (productId == null || productId.isEmpty) continue;
          final product = productById[productId];
          if (product == null) continue;
          final quantity = _asDouble(item['quantity']);
          final unitCost = _asDouble(product['costPrice']);
          final lineCogs = quantity * unitCost;
          if (lineCogs <= 0) continue;
          itemCogsTotal += lineCogs;
          expenseItems.add({
            'category': 'COGS',
            'title': product['name'] ?? item['description'] ?? 'Product',
            'subtitle': 'Order #${(order['id'] as String?)?.substring(0, 6) ?? ''} x Qty ${quantity.toStringAsFixed(0)} @ ETB ${unitCost.toStringAsFixed(2)}',
            'amount': lineCogs,
            'date': createdAt,
            'branchId': order['branchId'],
          });
        }
        if (cogsAmount > itemCogsTotal) {
          expenseItems.add({
            'category': 'COGS',
            'title': 'Unmapped COGS',
            'subtitle': 'Order #${(order['id'] as String?)?.substring(0, 6) ?? ''}',
            'amount': cogsAmount - itemCogsTotal,
            'date': createdAt,
            'branchId': order['branchId'],
          });
        }
      }

      final orderId = order['id']?.toString() ?? '';
      final idealRevenue = _asDouble(order['totalAmount']);
      final actualRevenue = paymentsByOrderId[orderId] ?? 0.0;
      final orderCommissions = mutableCommissions
          .where((c) =>
              c['orderId'] == order['id'] &&
              c['status'] == 'paid' &&
              withinSelectedRange(c['paidAt']))
          .fold<double>(0.0, (total, c) => total + _asDouble(c['amount']));
      final cogsValue = _asDouble(order['cogs']);
      orderProfitItems.add({
        'orderId': orderId,
        'customerName': order['customerName'] ?? 'Unknown',
        'status': order['status'] ?? '',
        'actualRevenue': actualRevenue,
        'idealRevenue': idealRevenue,
        'cogs': cogsValue,
        'commissions': orderCommissions,
        'actualProfit': actualRevenue - cogsValue - orderCommissions,
        'idealProfit': idealRevenue - cogsValue - orderCommissions,
        'date': createdAt,
        'branchId': order['branchId'],
      });
    }

    double cogsFromOrders = 0.0;
    for (final order in ordersList) {
      final createdAt = _asInt(order['createdAt']);
      if (!withinSelectedRange(createdAt)) continue;
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      if (status == 'completed' || status == 'delivered') {
        cogsFromOrders += _asDouble(order['cogs']);
      }
    }

    double commissionExpenses = 0.0;
    double tailorCommissions = 0.0;
    double salesCommissions = 0.0;
    for (final c in mutableCommissions) {
      final orderId = c['orderId']?.toString();
      if (orderId == null || orderId.isEmpty || !branchOrderIds.contains(orderId)) continue;
      if (c['status'] == 'paid' && c['paidAt'] != null && withinSelectedRange(c['paidAt'])) {
        final amount = _asDouble(c['amount']);
        commissionExpenses += amount;
        if (c['type'] == 'tailor') {
          tailorCommissions += amount;
        } else if (c['type'] == 'sales') {
          salesCommissions += amount;
        }
        expenseItems.add({
          'category': 'Commission',
          'title': c['employeeName'] ?? 'Commission',
          'subtitle': 'Order #${(c['orderId'] as String?)?.substring(0, 6) ?? ''}',
          'amount': amount,
          'date': _asInt(c['paidAt']),
        });
        weekExpenses += amount;
      }
    }

    double fuelExpenses = 0.0;
    for (final f in mutableFuel) {
      if (withinSelectedRange(f['date'])) {
        final amount = _asDouble(f['cost']);
        fuelExpenses += amount;
        weekExpenses += amount;
        expenseItems.add({
          'category': 'Fuel',
          'title': f['vehicleId'] ?? 'Fuel expense',
          'subtitle': 'Odometer ${f['odometer'] ?? '-'}',
          'amount': amount,
          'date': _asInt(f['date']),
        });
      }
    }

    double maintenanceExpenses = 0.0;
    for (final m in mutableMaintenance) {
      if (withinSelectedRange(m['date'])) {
        final amount = _asDouble(m['cost']);
        maintenanceExpenses += amount;
        weekExpenses += amount;
        expenseItems.add({
          'category': 'Maintenance',
          'title': m['type'] ?? 'Maintenance',
          'subtitle': m['description'] ?? m['notes'] ?? 'Maintenance expense',
          'amount': amount,
          'date': _asInt(m['date']),
        });
      }
    }

    double materialExpenses = 0.0;
    for (final mu in mutableMaterialUsage) {
      if (withinSelectedRange(mu['date'])) {
        final amount = _asDouble(mu['cost']);
        materialExpenses += amount;
        weekExpenses += amount;
        final materialId = mu['material_id'] as String?;
        expenseItems.add({
          'category': 'Material',
          'title': materialNamesById[materialId] ?? materialId ?? 'Material usage',
          'subtitle': 'Qty ${_asDouble(mu['quantity']).toStringAsFixed(0)}',
          'amount': amount,
          'date': _asInt(mu['date']),
        });
      }
    }

    final cogs = cogsFromOrders + materialExpenses + tailorCommissions;
    final otherExpenses = fuelExpenses + maintenanceExpenses + salesCommissions;
    final grossProfit = weekRevenue - cogs;
    final netProfit = grossProfit - otherExpenses;
    final totalExpenses = cogs + otherExpenses;
    final weekProfit = weekRevenue - weekExpenses;

    int total = 0;
    int pending = 0;
    int completed = 0;
    int withDriver = 0;
    int processingCount = 0;
    int returned = 0;
    double toCollect = 0.0;
    for (final order in ordersList) {
      final createdAt = _asInt(order['createdAt']);
      if (!withinSelectedRange(createdAt)) continue;
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
        case 'returned':
          returned++;
          break;
      }
      if (status != 'cancelled' && status != 'returned' && paid < totalAmount) {
        toCollect += (totalAmount - paid);
      }
    }

    ordersList.sort((a, b) => _asInt(b['createdAt']).compareTo(_asInt(a['createdAt'])));
    expenseItems.sort((a, b) => _asInt(b['date']).compareTo(_asInt(a['date'])));
    orderProfitItems.sort((a, b) => _asInt(b['date']).compareTo(_asInt(a['date'])));

    setState(() {
      _totalOrders = total;
      _pendingOrders = pending;
      _completedOrders = completed;
      _returnedCount = returned;
      _withDriverCount = withDriver;
      _processingCount = processingCount;
      _totalRevenue = weekRevenue;
      _toCollectAmount = toCollect;
      _cogs = cogs;
      _cogsFromOrders = cogsFromOrders;
      _tailorCommissions = tailorCommissions;
      _salesCommissions = salesCommissions;
      _commissionExpenses = commissionExpenses;
      _fuelExpenses = fuelExpenses;
      _maintenanceExpenses = maintenanceExpenses;
      _materialExpenses = materialExpenses;
      _otherExpenses = otherExpenses;
      _grossProfit = grossProfit;
      _netProfit = netProfit;
      _totalExpenses = totalExpenses;
      _profit = netProfit;
      _weekProfit = weekProfit;
      _expenseItems = expenseItems;
      _orderProfitItems = orderProfitItems;
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

  void _navigateToProfitDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfitDetailsScreen(
          showExpensesOnly: false,
          totalRevenue: _totalRevenue,
          totalExpenses: _totalExpenses,
          profit: _profit,
          weekProfit: _weekProfit,
          cogsAmount: _cogs,
          commissionExpenses: _commissionExpenses,
          fuelExpenses: _fuelExpenses,
          maintenanceExpenses: _maintenanceExpenses,
          materialExpenses: _materialExpenses,
          expenseItems: _expenseItems,
          orderProfitItems: _orderProfitItems,
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
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Operating Expenses (Non-COGS):',
                                style: TextStyle(color: AppColors.white, fontSize: 14),
                              ),
                              Text(
                                'ETB ${_otherExpenses.toStringAsFixed(0)}',
                                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Gross Profit (Revenue - COGS):',
                                style: TextStyle(color: AppColors.white, fontSize: 14),
                              ),
                              Text(
                                'ETB ${_grossProfit.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: _grossProfit >= 0 ? AppColors.success : AppColors.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildActionButton(
              Icons.shopping_bag,
              'New Order',
              AppColors.primaryRed,
              _navigateToCreateOrder,
            ),
            _buildActionButton(
              Icons.inventory,
              'Inventory',
              AppColors.info,
              _navigateToInventory,
            ),
            _buildActionButton(
              Icons.people,
              'Staff',
              AppColors.success,
              _navigateToEmployees,
            ),
            _buildActionButton(
              Icons.receipt,
              'Reports',
              AppColors.accent,
              _navigateToReports,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.white),
          ),
        ],
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
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            GestureDetector(
              onTap: _navigateToReports,
              child: StatCard(
                title: 'Revenue',
                value: 'ETB ${_totalRevenue.toStringAsFixed(0)}',
                icon: Icons.attach_money,
                color: AppColors.success,
              ),
            ),
            GestureDetector(
              onTap: _navigateToUnpaidOrders,
              child: StatCard(
                title: 'To Collect',
                value: 'ETB ${_toCollectAmount.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet,
                color: AppColors.accent,
              ),
            ),
            GestureDetector(
              onTap: _showCogsBreakdown,
              child: StatCard(
                title: 'COGS',
                value: 'ETB ${_cogs.toStringAsFixed(0)}',
                icon: Icons.inventory,
                color: AppColors.warning,
              ),
            ),
            GestureDetector(
              onTap: _showProfitDialog,
              child: StatCard(
                title: 'Net Profit',
                value: 'ETB ${_netProfit.toStringAsFixed(0)}',
                icon: Icons.trending_up,
                color: _netProfit >= 0 ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
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
