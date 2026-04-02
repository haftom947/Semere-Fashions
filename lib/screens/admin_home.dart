import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../widgets/stat_card.dart';
import '../widgets/category_card.dart';
import '../widgets/drawer_menu.dart';
import '../widgets/global_date_filter_card.dart';
import '../utils/app_date_filter.dart';
import 'purchase_orders_list_screen.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/low_stock_service.dart';
import '../utils/error_handler.dart';
import 'add_employee_screen.dart';
import 'orders_list_screen.dart';
import 'order_details_screen.dart';
import 'inventory_screen.dart';
import 'employee_list_screen.dart';
import 'customers_screen.dart';
import 'reports_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({Key? key}) : super(key: key);

  @override
  _AdminHomeState createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Timer? _lowStockTimer;
  StreamSubscription? _lowStockSubscription;
  StreamSubscription<bool>? _dataChangedSubscription;
  bool _hasShownLowStockAlert = false;
  String _adminName = 'Admin';
  bool _isLoading = true;

  // Operational stats
  int _totalOrders = 0;
  int _pendingOrders = 0;
  double _weekProfit = 0.0;
  int _completedOrders = 0;
  int _withDriverCount = 0;
  int _processingCount = 0;
  int _cancelledCount = 0;
  int _returnedCount = 0;

  // Financial stats
  double _totalRevenue = 0.0;
  double _toCollectAmount = 0.0;
  double _totalExpenses = 0.0;   // will be sum of the breakdown below
  double _profit = 0.0;
  double _cogs = 0.0;
  double _otherExpenses = 0.0;
  double _grossProfit = 0.0;
  double _netProfit = 0.0;

  // Expenses breakdown (for the dialog)
  double _cogsFromOrders = 0.0;
  double _tailorCommissions = 0.0;
  double _salesCommissions = 0.0;
  double _deliveryCommissions = 0.0;
  double _commissionExpenses = 0.0;
  double _fuelExpenses = 0.0;
  double _maintenanceExpenses = 0.0;
  double _materialExpenses = 0.0;
  List<Map<String, dynamic>> _expenseItems = [];
  List<Map<String, dynamic>> _orderProfitItems = [];

  // Other
  List<Map<String, dynamic>> _recentOrders = [];

  // Rental summary
  double _rentalReceivedThisMonth = 0.0;
  double _rentalOverdue = 0.0;
  double _rentalOccupancyRate = 0.0;
  @override
  void initState() {
    super.initState();
    _loadAdminData();
    _loadStats();
    _loadRentalSummary();
    AppDateFilter.instance.rangeNotifier.addListener(_handleGlobalRangeChanged);

    // Listen to sync events to refresh data
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      print('ðŸ”„ Data changed â€“ reloading stats');
      _loadStats();
      _loadRentalSummary();
    });

    _startLowStockPeriodicCheck();
    _listenToLowStock();

    // Trigger an initial sync to load data from Firebase
    _syncService.syncAll().then((_) {
      print('âœ… Initial sync completed');
      // Refresh stats again after sync
      _loadStats();
      _loadRentalSummary();
    });
  }
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
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
      case 'returned':
        return AppColors.warning;
      default:
        return AppColors.mediumGrey;
    }
  }

  double _asDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

  int _asInt(dynamic value) => (value as num?)?.toInt() ?? 0;

  void _listenToLowStock() {
    _lowStockSubscription = _getLowStockStream().listen((lowStock) {
      if (lowStock.isNotEmpty && !_hasShownLowStockAlert && mounted) {
        ErrorHandler.showWarning(
          context,
          'Low stock alert: ${lowStock.length} item${lowStock.length > 1 ? 's' : ''} below minimum.',
        );
        _hasShownLowStockAlert = true;
      }
    });
  }

  void _startLowStockPeriodicCheck() {
    _lowStockTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      await LowStockService().checkAndNotify();
    });
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_handleGlobalRangeChanged);
    _lowStockTimer?.cancel();
    _lowStockSubscription?.cancel();
    _dataChangedSubscription?.cancel();
    super.dispose();
  }

  void _handleGlobalRangeChanged() {
    if (!mounted) return;
    _loadStats();
  }

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
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  Future<void> _loadAdminData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>?;
          final adminName = userData?['name']?.toString().trim() ?? '';
          setState(() {
            _adminName = adminName.isNotEmpty ? adminName : 'Admin';
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading admin data: $e');
      setState(() => _isLoading = false);
    }
  }

  String _dashboardCacheKey() {
    final range = AppDateFilter.instance.range;
    if (range == null) return 'dashboard_all';
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
    return 'dashboard_${start}_$end';
  }

  void _applyStatsFromCache(Map<String, dynamic> cached) {
    if (!mounted) return;
    setState(() {
      _totalOrders = (cached['totalOrders'] as num?)?.toInt() ?? 0;
      _pendingOrders = (cached['pendingOrders'] as num?)?.toInt() ?? 0;
      _completedOrders = (cached['completedOrders'] as num?)?.toInt() ?? 0;
      _withDriverCount = (cached['withDriverCount'] as num?)?.toInt() ?? 0;
      _processingCount = (cached['processingCount'] as num?)?.toInt() ?? 0;
      _cancelledCount = (cached['cancelledCount'] as num?)?.toInt() ?? 0;
      _returnedCount = (cached['returnedCount'] as num?)?.toInt() ?? 0;
      _totalRevenue = (cached['totalRevenue'] as num?)?.toDouble() ?? 0.0;
      _toCollectAmount = (cached['toCollectAmount'] as num?)?.toDouble() ?? 0.0;
      _cogs = (cached['cogs'] as num?)?.toDouble() ?? 0.0;
      _cogsFromOrders = (cached['cogsFromOrders'] as num?)?.toDouble() ?? 0.0;
      _tailorCommissions =
          (cached['tailorCommissions'] as num?)?.toDouble() ?? 0.0;
      _salesCommissions =
          (cached['salesCommissions'] as num?)?.toDouble() ?? 0.0;
      _deliveryCommissions =
          (cached['deliveryCommissions'] as num?)?.toDouble() ?? 0.0;
      _commissionExpenses =
          (cached['commissionExpenses'] as num?)?.toDouble() ?? 0.0;
      _fuelExpenses = (cached['fuelExpenses'] as num?)?.toDouble() ?? 0.0;
      _maintenanceExpenses =
          (cached['maintenanceExpenses'] as num?)?.toDouble() ?? 0.0;
      _materialExpenses =
          (cached['materialExpenses'] as num?)?.toDouble() ?? 0.0;
      _otherExpenses = (cached['otherExpenses'] as num?)?.toDouble() ?? 0.0;
      _grossProfit = (cached['grossProfit'] as num?)?.toDouble() ?? 0.0;
      _netProfit = (cached['netProfit'] as num?)?.toDouble() ?? 0.0;
      _totalExpenses = (cached['totalExpenses'] as num?)?.toDouble() ?? 0.0;
      _profit = (cached['profit'] as num?)?.toDouble() ?? 0.0;
      _weekProfit = (cached['weekProfit'] as num?)?.toDouble() ?? 0.0;
      final recent = cached['recentOrders'];
      if (recent is List) {
        _recentOrders = recent
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    });
  }

  Future<void> _loadStats() async {
    final cacheKey = _dashboardCacheKey();
    final cached = await _dbHelper.loadCache(cacheKey);
    if (cached != null) {
      _applyStatsFromCache(cached);
    }

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

    var orders = await _dbHelper.query('orders');
    var payments = await _dbHelper.query('payment_transaction');
    var commissions = await _dbHelper.query('commissions');
    var fuelLogs = await _dbHelper.query('fuel_logs');
    var maintenanceLogs = await _dbHelper.query('maintenance_logs');
    var materialUsage = await _dbHelper.query('material_usage');
    var materials = await _dbHelper.query('materials');
    var products = await _dbHelper.query('products');

    List<Map<String, dynamic>> ordersList = List.from(orders);
    List<Map<String, dynamic>> mutablePayments = List.from(payments);
    List<Map<String, dynamic>> mutableCommissions = List.from(commissions);
    List<Map<String, dynamic>> mutableFuel = List.from(fuelLogs);
    List<Map<String, dynamic>> mutableMaintenance = List.from(maintenanceLogs);
    List<Map<String, dynamic>> mutableMaterialUsage = List.from(materialUsage);
    List<Map<String, dynamic>> mutableMaterials = List.from(materials);
    List<Map<String, dynamic>> mutableProducts = List.from(products);

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
    final paymentsByOrderId = <String, double>{};
    for (final payment in mutablePayments) {
      final orderId = payment['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) continue;
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
    for (var p in mutablePayments) {
      if (withinSelectedRange(p['date'])) {
        final amount = _asDouble(p['amount']);
        if (p['type'] == 'payment') {
          weekRevenue += amount;
        } else {
          weekRevenue -= amount;
        }
      }
    }

    double weekExpenses = 0.0;
    for (var order in ordersList) {
      final createdAt = _asInt(order['createdAt']);
      if (withinSelectedRange(createdAt)) {
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

            final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
            final unitCost = (product['costPrice'] as num?)?.toDouble() ?? 0.0;
            final lineCogs = quantity * unitCost;
            if (lineCogs <= 0) continue;

            itemCogsTotal += lineCogs;
            expenseItems.add({
              'category': 'COGS',
              'title': product['name'] ?? item['description'] ?? 'Product',
              'subtitle': 'Order #${(order['id'] as String?)?.substring(0, 6) ?? ''} • Qty ${quantity.toStringAsFixed(0)} × ETB ${unitCost.toStringAsFixed(2)}',
              'amount': lineCogs,
              'date': createdAt,
              'branchId': order['branchId'],
            });
          }

          if (cogsAmount > itemCogsTotal) {
            final remainder = cogsAmount - itemCogsTotal;
            expenseItems.add({
              'category': 'COGS',
              'title': 'Unmapped COGS',
              'subtitle': 'Order #${(order['id'] as String?)?.substring(0, 6) ?? ''}',
              'amount': remainder,
              'date': createdAt,
              'branchId': order['branchId'],
            });
          }
        }

        final orderId = order['id']?.toString() ?? '';
        final idealRevenue = _asDouble(order['totalAmount']);
        final actualRevenue = paymentsByOrderId[orderId] ?? 0.0;
        final orderCommissions = mutableCommissions
            .where((c) {
              if (c['orderId'] != order['id']) return false;
              if (c['status'] == 'voided') return false;
              final effectiveDate = c['paidAt'] ?? c['createdAt'];
              return withinSelectedRange(effectiveDate);
            })
            .fold<double>(0.0, (total, c) => total + _asDouble(c['amount']));
        final cogsValue = _asDouble(order['cogs']);
        final actualProfit = actualRevenue - cogsValue - orderCommissions;
        final idealProfit = idealRevenue - cogsValue - orderCommissions;
        orderProfitItems.add({
          'orderId': orderId,
          'customerName': order['customerName'] ?? 'Unknown',
          'status': order['status'] ?? '',
          'actualRevenue': actualRevenue,
          'idealRevenue': idealRevenue,
          'cogs': cogsValue,
          'commissions': orderCommissions,
          'actualProfit': actualProfit,
          'idealProfit': idealProfit,
          'date': createdAt,
          'branchId': order['branchId'],
        });
      }
    }
    for (var c in mutableCommissions) {
      if (c['status'] == 'voided') continue;
      final effectiveDate = c['paidAt'] ?? c['createdAt'];
      if (effectiveDate == null || !withinSelectedRange(effectiveDate)) continue;
      final amount = _asDouble(c['amount']);
      weekExpenses += amount;
      final linkedOrder = ordersList.firstWhere(
        (order) => order['id'] == c['orderId'],
        orElse: () => <String, dynamic>{},
      );
      expenseItems.add({
        'category': 'Commission',
        'title': c['employeeName'] ?? 'Commission',
        'subtitle': 'Order #${(c['orderId'] as String?)?.substring(0, 6) ?? ''}',
        'amount': amount,
        'date': _asInt(effectiveDate),
        'branchId': linkedOrder['branchId'],
      });
    }
    for (var f in mutableFuel) {
      if (withinSelectedRange(f['date'])) {
        final amount = _asDouble(f['cost']);
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
    for (var m in mutableMaintenance) {
      if (withinSelectedRange(m['date'])) {
        final amount = _asDouble(m['cost']);
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
    for (var mu in mutableMaterialUsage) {
      if (withinSelectedRange(mu['date'])) {
        final amount = _asDouble(mu['cost']);
        weekExpenses += amount;
        final materialId = mu['material_id'] as String?;
        expenseItems.add({
          'category': 'Material',
          'title': materialNamesById[materialId] ?? materialId ?? 'Material usage',
          'subtitle': 'Qty ${(mu['quantity'] as num?)?.toStringAsFixed(0) ?? '0'}',
          'amount': amount,
          'date': _asInt(mu['date']),
        });
      }
    }
    final weekProfit = weekRevenue - weekExpenses;

    double revenue = 0.0;
    for (var p in mutablePayments) {
      if (withinSelectedRange(p['date'])) {
        final amount = _asDouble(p['amount']);
        if (p['type'] == 'payment') {
          revenue += amount;
        } else {
          revenue -= amount;
        }
      }
    }

    double cogsFromOrders = 0.0;
    for (var order in ordersList) {
      final createdAt = _asInt(order['createdAt']);
      if (!withinSelectedRange(createdAt)) continue;
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      if (status == 'delivered' || status == 'completed') {
        cogsFromOrders += _asDouble(order['cogs']);
      }
    }

    double commissionExpenses = 0.0;
    double tailorCommissions = 0.0;
    double salesCommissions = 0.0;
    double deliveryCommissions = 0.0;
    for (var c in mutableCommissions) {
      if (c['status'] == 'paid' && c['paidAt'] != null && withinSelectedRange(c['paidAt'])) {
        final amount = _asDouble(c['amount']);
        commissionExpenses += amount;
        if (c['type'] == 'tailor') {
          tailorCommissions += amount;
        } else if (c['type'] == 'sales') {
          salesCommissions += amount;
        } else if (c['type'] == 'delivery') {
          deliveryCommissions += amount;
        }
      }
    }

    double fuelExpenses = 0.0;
    for (var f in mutableFuel) {
      if (withinSelectedRange(f['date'])) {
        fuelExpenses += _asDouble(f['cost']);
      }
    }

    double maintenanceExpenses = 0.0;
    for (var m in mutableMaintenance) {
      if (withinSelectedRange(m['date'])) {
        maintenanceExpenses += _asDouble(m['cost']);
      }
    }

    double materialExpenses = 0.0;
    for (var mu in mutableMaterialUsage) {
      if (withinSelectedRange(mu['date'])) {
        materialExpenses += _asDouble(mu['cost']);
      }
    }

    final cogs = cogsFromOrders + materialExpenses + tailorCommissions;
    final otherExpenses =
        fuelExpenses + maintenanceExpenses + salesCommissions + deliveryCommissions;
    final grossProfit = revenue - cogs;
    final netProfit = grossProfit - otherExpenses;
    final totalExpenses = cogs + otherExpenses;
    final profit = netProfit;

    int total = 0;
    int pending = 0, completed = 0, withDriver = 0, cancelled = 0, returned = 0, processingCount = 0;
    double toCollect = 0.0;

    for (var order in ordersList) {
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
        case 'cancelled':
          cancelled++;
          break;
        case 'returned':
          returned++;
          break;
      }

      if (status != 'cancelled' && status != 'returned' && paid < totalAmount) {
        toCollect += (totalAmount - paid);
      }
    }

    ordersList.sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    var recent = ordersList.take(5).toList();
    expenseItems.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
    orderProfitItems.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));

    setState(() {
      // Order stats
      _totalOrders = total;
      _pendingOrders = pending;
      _completedOrders = completed;
      _withDriverCount = withDriver;
      _processingCount = processingCount;
      _cancelledCount = cancelled;
      _returnedCount = returned;

      // Financial stats (selected period)
      _totalRevenue = revenue;
      _toCollectAmount = toCollect;
      _cogs = cogs;
      _cogsFromOrders = cogsFromOrders;
      _tailorCommissions = tailorCommissions;
      _salesCommissions = salesCommissions;
      _deliveryCommissions = deliveryCommissions;
      _commissionExpenses = commissionExpenses;
      _fuelExpenses = fuelExpenses;
      _maintenanceExpenses = maintenanceExpenses;
      _materialExpenses = materialExpenses;
      _otherExpenses = otherExpenses;
      _grossProfit = grossProfit;
      _netProfit = netProfit;
      _totalExpenses = totalExpenses;
      _profit = profit;
      _expenseItems = expenseItems;
      _orderProfitItems = orderProfitItems;
      // Week profit
      _weekProfit = weekProfit;

      // Recent orders
      _recentOrders = recent;
    });

    unawaited(
      _dbHelper.saveCache(
        cacheKey,
        {
          'totalOrders': total,
          'pendingOrders': pending,
          'completedOrders': completed,
          'withDriverCount': withDriver,
          'processingCount': processingCount,
          'cancelledCount': cancelled,
          'returnedCount': returned,
          'totalRevenue': revenue,
          'toCollectAmount': toCollect,
          'cogs': cogs,
          'cogsFromOrders': cogsFromOrders,
          'tailorCommissions': tailorCommissions,
          'salesCommissions': salesCommissions,
          'deliveryCommissions': deliveryCommissions,
          'commissionExpenses': commissionExpenses,
          'fuelExpenses': fuelExpenses,
          'maintenanceExpenses': maintenanceExpenses,
          'materialExpenses': materialExpenses,
          'otherExpenses': otherExpenses,
          'grossProfit': grossProfit,
          'netProfit': netProfit,
          'totalExpenses': totalExpenses,
          'profit': profit,
          'weekProfit': weekProfit,
          'recentOrders': recent,
        },
      ),
    );
  }

  void _showExpensesBreakdown() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfitDetailsScreen(
          showExpensesOnly: true,
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
  Future<void> _loadRentalSummary() async {
    try {
      var rentDues = await _dbHelper.query('rent_dues');
      var payments = await _dbHelper.query('rent_payments');
      var properties = await _dbHelper.query('properties');

      final now = DateTime.now();
      final currentMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      double received = 0;
      for (var p in payments) {
        if (p['month'] == currentMonth) {
          received += (p['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      double overdue = 0;
      for (var d in rentDues) {
        if (d['status'] == 'pending' &&
            (d['dueDate'] as int) < now.millisecondsSinceEpoch) {
          overdue += (d['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      int total = properties.length;
      int occupied = properties.where((p) => p['status'] == 'occupied').length;
      double occupancy = total > 0 ? (occupied / total) * 100 : 0;

      setState(() {
        _rentalReceivedThisMonth = received;
        _rentalOverdue = overdue;
        _rentalOccupancyRate = occupancy;
      });
    } catch (e) {
      print('Error loading rental summary: $e');
    }
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

  void _navigateToAddEmployee() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEmployeeScreen()),
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

  void _navigateToCustomers() {
    Navigator.pushNamed(context, '/customers');
  }
  void _navigateToReceivedPurchaseOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PurchaseOrdersListScreen(initialStatus: 'received'),
      ),
    );
  }

  void _showProfitDialog() {
    showDialog(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text(
            'Profit Calculation',
            style: TextStyle(color: Colors.black),
          ),
          content: Text(
            'Revenue: ETB ${_totalRevenue.toStringAsFixed(2)}\n'
            'COGS: ETB ${_cogs.toStringAsFixed(2)}\n'
            'Gross Profit: ETB ${_grossProfit.toStringAsFixed(2)}\n'
            'Operating Expenses: ETB ${_otherExpenses.toStringAsFixed(2)}\n'
            'Net Profit: ETB ${_netProfit.toStringAsFixed(2)}',
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
          initialRange: AppDateFilter.instance.range,
        ),
      ),
    );
  }
  void _navigateToProperties() {
    Navigator.pushNamed(context, '/properties');
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.light(),
          child: AlertDialog(
            title: const Text('Logout', style: TextStyle(color: Colors.black)),
            content: const Text(
              'Are you sure you want to logout?',
              style: TextStyle(color: Colors.black),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  }
                },
                child: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirm == true) {
      // Already signed out above
    }
  }

  Future<List<Map<String, dynamic>>> _getTopCustomers() async {
    var orders = await _dbHelper.query('orders');
    Map<String, Map<String, dynamic>> customerMap = {};
    for (var order in orders) {
      String customerId = order['customerId'] ?? '';
      String customerName = order['customerName'] ?? 'Unknown';
      double amount = (order['totalAmount'] as num?)?.toDouble() ?? 0;
      if (customerId.isEmpty) continue;
      if (!customerMap.containsKey(customerId)) {
        customerMap[customerId] = {
          'id': customerId,
          'name': customerName,
          'orders': 0,
          'total': 0.0,
        };
      }
      customerMap[customerId]!['orders'] =
          customerMap[customerId]!['orders'] + 1;
      customerMap[customerId]!['total'] =
          customerMap[customerId]!['total'] + amount;
    }
    var list = customerMap.values.toList();
    list.sort((a, b) => (b['orders'] as int).compareTo(a['orders'] as int));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DrawerMenu(role: 'admin'),
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
                    expandedHeight: 200.0,
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
                      // Temporary manual refresh button (you can remove later)
                      IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.white),
                        onPressed: () {
                          _syncService.syncAll().then((_) {
                            _loadStats();
                            _loadRentalSummary();
                          });
                        },
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
                        Text(
                          'Welcome back, ${_adminName.split(' ').first}!',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Here\'s your business overview for the selected period.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 24),

                        const GlobalDateFilterCard(),
                        const SizedBox(height: 24),

                        _buildQuickActions(),
                        const SizedBox(height: 24),

                        // Consolidated Stats Grid
                        _buildOrderStatsGrid(),
                        const SizedBox(height: 24),

                        // Rental Summary
                        _buildRentalSummary(),
                        const SizedBox(height: 24),

                        // Top Customers
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getTopCustomers(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox();
                            var topCustomers = snapshot.data!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('TOP CUSTOMERS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.white)),
                                    TextButton(onPressed: _navigateToCustomers, child: const Text('See All >', style: TextStyle(color: AppColors.white))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primaryRed,
                                      child: Text(
                                        (topCustomers.first['name'][0]).toUpperCase(),
                                        style: const TextStyle(color: AppColors.white, fontSize: 12),
                                      ),
                                    ),
                                    title: Text(topCustomers.first['name']),
                                    subtitle: Text('${topCustomers.first['orders']} orders'),
                                    trailing: Text('ETB ${(topCustomers.first['total'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                                    onTap: () {
                                      // Optionally navigate to orders filtered by this customer
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => OrdersListScreen(showUnpaidOnly: false),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // Recent Orders as chips
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Recent Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.white)),
                                TextButton(onPressed: _navigateToOrders, child: const Text('View All >', style: TextStyle(color: AppColors.white))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _recentOrders.isEmpty
                                ? const Text('No recent orders', style: TextStyle(color: AppColors.white))
                                : Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _getStatusColor(_recentOrders.first['status']),
                                        child: Text(
                                          (_recentOrders.first['id']?.substring(0, 1) ?? '#'),
                                          style: const TextStyle(color: AppColors.white, fontSize: 14),
                                        ),
                                      ),
                                      title: Text(
                                        _recentOrders.first['customerName'] ?? 'Unknown',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Text(
                                        '#${_recentOrders.first['id']?.substring(0, 6)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'ETB ${(_recentOrders.first['totalAmount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(_recentOrders.first['status']).withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _recentOrders.first['status'] ?? 'pending',
                                              style: TextStyle(
                                                color: _getStatusColor(_recentOrders.first['status']),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => OrderDetailsScreen(orderId: _recentOrders.first['id']),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Order Categories
                        _buildFinancialGrid(),
                        const SizedBox(height: 24),
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
              Icons.person_add,
              'Add Employee',
              AppColors.primaryRed,
              _navigateToAddEmployee,
            ),
            _buildActionButton(
              Icons.shopping_bag,
              'New Order',
              AppColors.success,
              _navigateToCreateOrder,
            ),
            _buildActionButton(
              Icons.inventory,
              'Add Stock',
              AppColors.info,
              _navigateToInventory,
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

  Widget _buildOrderStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.white),
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
              onTap: () => _navigateToOrdersWithStatus(null),
              child: StatCard(
                title: 'Total Orders',
                value: _totalOrders.toString(),
                icon: Icons.shopping_bag,
                color: AppColors.primaryRed,
              ),
            ),
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus('pending'),
              child: StatCard(
                title: 'Pending',
                value: _pendingOrders.toString(),
                icon: Icons.pending_actions,
                color: AppColors.warning,
              ),
            ),
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus('delivered'),
              child: StatCard(
                title: 'Completed',
                value: _completedOrders.toString(),
                icon: Icons.check_circle,
                color: AppColors.info,
              ),
            ),
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus('out_for_delivery'),
              child: StatCard(
                title: 'With Driver',
                value: _withDriverCount.toString(),
                icon: Icons.delivery_dining,
                color: AppColors.primaryRed,
              ),
            ),
            GestureDetector(
              onTap: () => _navigateToOrdersWithStatus('processing'),
              child: StatCard(
                title: 'Processing',
                value: _processingCount.toString(),
                icon: Icons.pending,
                color: AppColors.info,
              ),
            ),
          ],
        ),
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
                  'Received',
                  'ETB ${_rentalReceivedThisMonth.toStringAsFixed(0)}',
                  Icons.payment,
                  AppColors.success,
                ),
                _buildRentalStat(
                  'Overdue',
                  'ETB ${_rentalOverdue.toStringAsFixed(0)}',
                  Icons.warning,
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

  int _getProcessingCount() {
    return _processingCount;
  }

  Widget _buildFinancialGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Financial Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.white),
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
              onTap: _navigateToProfitDetails,
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
}

class ProfitDetailsScreen extends StatefulWidget {
  const ProfitDetailsScreen({
    super.key,
    required this.showExpensesOnly,
    required this.totalRevenue,
    required this.totalExpenses,
    required this.profit,
    required this.weekProfit,
    required this.cogsAmount,
    required this.commissionExpenses,
    required this.fuelExpenses,
    required this.maintenanceExpenses,
    required this.materialExpenses,
    required this.expenseItems,
    required this.orderProfitItems,
    this.initialRange,
  });

  final bool showExpensesOnly;
  final double totalRevenue;
  final double totalExpenses;
  final double profit;
  final double weekProfit;
  final double cogsAmount;
  final double commissionExpenses;
  final double fuelExpenses;
  final double maintenanceExpenses;
  final double materialExpenses;
  final List<Map<String, dynamic>> expenseItems;
  final List<Map<String, dynamic>> orderProfitItems;
  final DateTimeRange? initialRange;

  @override
  State<ProfitDetailsScreen> createState() => _ProfitDetailsScreenState();
}

class _ProfitDetailsScreenState extends State<ProfitDetailsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _branches = [];
  Map<String, String> _branchNamesById = {};
  String _selectedBranchId = 'all';
  DateTimeRange? _selectedRange;
  bool _isLoadingDetails = true;
  double _displayRevenue = 0.0;
  double _displayTotalExpenses = 0.0;
  double _displayProfit = 0.0;
  double _displayWeekProfit = 0.0;
  double _displayCogs = 0.0;
  double _displayCommissionExpenses = 0.0;
  double _displayFuelExpenses = 0.0;
  double _displayMaintenanceExpenses = 0.0;
  double _displayMaterialExpenses = 0.0;
  double _displayOtherExpenses = 0.0;
  double _displayGrossProfit = 0.0;
  double _displayNetProfit = 0.0;
  List<Map<String, dynamic>> _expenseItems = [];
  List<Map<String, dynamic>> _orderProfitItems = [];

  @override
  void initState() {
    super.initState();
    _selectedRange = widget.initialRange ?? AppDateFilter.instance.range;
    _displayRevenue = widget.totalRevenue;
    _displayTotalExpenses = widget.totalExpenses;
    _displayProfit = widget.profit;
    _displayWeekProfit = widget.weekProfit;
    _displayCogs = widget.cogsAmount;
    _displayCommissionExpenses = widget.commissionExpenses;
    _displayFuelExpenses = widget.fuelExpenses;
    _displayMaintenanceExpenses = widget.maintenanceExpenses;
    _displayMaterialExpenses = widget.materialExpenses;
    _displayOtherExpenses = widget.commissionExpenses + widget.fuelExpenses + widget.maintenanceExpenses;
    _displayGrossProfit = widget.totalRevenue - widget.cogsAmount;
    _displayNetProfit = widget.profit;
    _loadBranches();
    _loadDetails();
    AppDateFilter.instance.rangeNotifier.addListener(_handleGlobalRangeChanged);
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_handleGlobalRangeChanged);
    super.dispose();
  }

  void _handleGlobalRangeChanged() {
    final nextRange = AppDateFilter.instance.range;
    if (nextRange == _selectedRange) return;
    setState(() {
      _selectedRange = nextRange;
    });
    _loadDetails();
  }

  int _rangeStartMillis() {
    if (_selectedRange == null) return 0;
    final start = _selectedRange!.start;
    return DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
  }

  int _rangeEndMillis() {
    if (_selectedRange == null) return DateTime.now().millisecondsSinceEpoch;
    final end = _selectedRange!.end;
    return DateTime(
      end.year,
      end.month,
      end.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
  }

  bool _withinSelectedRange(dynamic value) {
    if (_selectedRange == null) return true;
    final timestamp = (value as num?)?.toInt();
    if (timestamp == null) return false;
    return timestamp >= _rangeStartMillis() && timestamp <= _rangeEndMillis();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoadingDetails = true);
    try {
      final orders = await _dbHelper.query('orders');
      final payments = await _dbHelper.query('payment_transaction');
      final commissions = await _dbHelper.query('commissions');
      final fuelLogs = await _dbHelper.query('fuel_logs');
      final maintenanceLogs = await _dbHelper.query('maintenance_logs');
      final materialUsage = await _dbHelper.query('material_usage');
      final materials = await _dbHelper.query('materials');
      final products = await _dbHelper.query('products');

      final orderList = List<Map<String, dynamic>>.from(orders);
      final paymentList = List<Map<String, dynamic>>.from(payments);
      final commissionList = List<Map<String, dynamic>>.from(commissions);
      final fuelList = List<Map<String, dynamic>>.from(fuelLogs);
      final maintenanceList = List<Map<String, dynamic>>.from(maintenanceLogs);
      final materialUsageList = List<Map<String, dynamic>>.from(materialUsage);
      final materialList = List<Map<String, dynamic>>.from(materials);
      final productList = List<Map<String, dynamic>>.from(products);

      final materialNamesById = <String, String>{
        for (final material in materialList)
          if ((material['id'] as String?)?.isNotEmpty ?? false)
            material['id'] as String:
                (material['name'] as String?) ?? material['id'] as String,
      };
      final productById = <String, Map<String, dynamic>>{
        for (final product in productList)
          if ((product['id'] as String?)?.isNotEmpty ?? false)
            product['id'] as String: product,
      };

      final expenseItems = <Map<String, dynamic>>[];
      final orderProfitItems = <Map<String, dynamic>>[];
      final paymentsByOrderId = <String, double>{};
      for (final payment in paymentList) {
        final orderId = payment['orderId']?.toString();
        if (orderId == null || orderId.isEmpty) continue;
        if (!_withinSelectedRange(payment['date'])) continue;
        final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
        if (payment['type'] == 'payment') {
          paymentsByOrderId[orderId] = (paymentsByOrderId[orderId] ?? 0.0) + amount;
        } else {
          paymentsByOrderId[orderId] = (paymentsByOrderId[orderId] ?? 0.0) - amount;
        }
      }

      double revenue = 0.0;
      for (final payment in paymentList) {
        if (_withinSelectedRange(payment['date'])) {
          final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
          if (payment['type'] == 'payment') {
            revenue += amount;
          } else {
            revenue -= amount;
          }
        }
      }

      double cogsFromOrders = 0.0;
      double materialExpenses = 0.0;
      double tailorCommissions = 0.0;
      double salesCommissions = 0.0;
      double commissionExpenses = 0.0;
      double fuelExpenses = 0.0;
      double maintenanceExpenses = 0.0;
      final totalOrderProfitItems = <Map<String, dynamic>>[];

      for (final order in orderList) {
        final createdAt = (order['createdAt'] as num?)?.toInt() ?? 0;
        if (!_withinSelectedRange(createdAt)) continue;

        final orderStatus = (order['status'] as String?)?.toLowerCase() ?? '';
        if (orderStatus == 'completed' || orderStatus == 'delivered') {
          cogsFromOrders += (order['cogs'] as num?)?.toDouble() ?? 0.0;
        }

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
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitCost = (product['costPrice'] as num?)?.toDouble() ?? 0.0;
          final lineCogs = quantity * unitCost;
          if (lineCogs <= 0) continue;
          itemCogsTotal += lineCogs;
          expenseItems.add({
            'category': 'COGS',
            'title': product['name'] ?? item['description'] ?? 'Product',
            'subtitle':
                'Order #${(order['id'] as String?)?.substring(0, 6) ?? ''} • Qty ${quantity.toStringAsFixed(0)} × ETB ${unitCost.toStringAsFixed(2)}',
            'amount': lineCogs,
            'date': createdAt,
            'branchId': order['branchId'],
          });
        }
        final orderCogs = (order['cogs'] as num?)?.toDouble() ?? 0.0;
        if (orderCogs > itemCogsTotal) {
          expenseItems.add({
            'category': 'COGS',
            'title': 'Unmapped COGS',
            'subtitle': 'Order #${(order['id'] as String?)?.substring(0, 6) ?? ''}',
            'amount': orderCogs - itemCogsTotal,
            'date': createdAt,
            'branchId': order['branchId'],
          });
        }

        final orderId = order['id']?.toString() ?? '';
        final idealRevenue = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final actualRevenue = paymentsByOrderId[orderId] ?? 0.0;
        final orderCommissions = commissionList
            .where((c) {
              if (c['orderId'] != order['id']) return false;
              if (c['status'] == 'voided') return false;
              final effectiveDate = c['paidAt'] ?? c['createdAt'];
              return _withinSelectedRange(effectiveDate);
            })
            .fold<double>(
              0.0,
              (total, c) => total + ((c['amount'] as num?)?.toDouble() ?? 0.0),
            );
        final cogsValue = (order['cogs'] as num?)?.toDouble() ?? 0.0;
        totalOrderProfitItems.add({
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

    for (final c in commissionList) {
      if (c['status'] != 'voided') {
        final effectiveDate = c['paidAt'] ?? c['createdAt'];
        if (effectiveDate == null || !_withinSelectedRange(effectiveDate)) {
          continue;
        }
        final amount = (c['amount'] as num?)?.toDouble() ?? 0.0;
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
          'date': (effectiveDate as num?)?.toInt() ?? 0,
          'branchId': c['branchId'],
        });
      }
    }

      for (final f in fuelList) {
        if (_withinSelectedRange(f['date'])) {
          final amount = (f['cost'] as num?)?.toDouble() ?? 0.0;
          fuelExpenses += amount;
          expenseItems.add({
            'category': 'Fuel',
            'title': f['vehicleId'] ?? 'Fuel expense',
            'subtitle': 'Odometer ${f['odometer'] ?? '-'}',
            'amount': amount,
            'date': (f['date'] as num?)?.toInt() ?? 0,
            'branchId': f['branchId'],
          });
        }
      }

      for (final m in maintenanceList) {
        if (_withinSelectedRange(m['date'])) {
          final amount = (m['cost'] as num?)?.toDouble() ?? 0.0;
          maintenanceExpenses += amount;
          expenseItems.add({
            'category': 'Maintenance',
            'title': m['type'] ?? 'Maintenance',
            'subtitle': m['description'] ?? m['notes'] ?? 'Maintenance expense',
            'amount': amount,
            'date': (m['date'] as num?)?.toInt() ?? 0,
            'branchId': m['branchId'],
          });
        }
      }

      for (final mu in materialUsageList) {
        if (_withinSelectedRange(mu['date'])) {
          final amount = (mu['cost'] as num?)?.toDouble() ?? 0.0;
          materialExpenses += amount;
          final materialId = mu['material_id'] as String?;
          expenseItems.add({
            'category': 'Material',
            'title': materialNamesById[materialId] ?? materialId ?? 'Material usage',
            'subtitle': 'Qty ${(mu['quantity'] as num?)?.toStringAsFixed(0) ?? '0'}',
            'amount': amount,
            'date': (mu['date'] as num?)?.toInt() ?? 0,
            'branchId': mu['branchId'],
          });
        }
      }

      final cogs = cogsFromOrders + materialExpenses + tailorCommissions;
      final otherExpenses = fuelExpenses + maintenanceExpenses + salesCommissions;
      final grossProfit = revenue - cogs;
      final netProfit = grossProfit - otherExpenses;
      final totalExpenses = cogs + otherExpenses;
      final weekProfit = revenue - (cogsFromOrders + materialExpenses + tailorCommissions + commissionExpenses + fuelExpenses + maintenanceExpenses + salesCommissions);

      expenseItems.sort((a, b) => ((b['date'] as num?)?.toInt() ?? 0).compareTo((a['date'] as num?)?.toInt() ?? 0));
      totalOrderProfitItems.sort((a, b) => ((b['date'] as num?)?.toInt() ?? 0).compareTo((a['date'] as num?)?.toInt() ?? 0));

      if (!mounted) return;
      setState(() {
        _expenseItems = expenseItems;
        _orderProfitItems = totalOrderProfitItems;
        _displayRevenue = revenue;
        _displayTotalExpenses = totalExpenses;
        _displayProfit = netProfit;
        _displayWeekProfit = weekProfit;
        _displayCogs = cogs;
        _displayCommissionExpenses = commissionExpenses;
        _displayFuelExpenses = fuelExpenses;
        _displayMaintenanceExpenses = maintenanceExpenses;
        _displayMaterialExpenses = materialExpenses;
        _displayOtherExpenses = otherExpenses;
        _displayGrossProfit = grossProfit;
        _displayNetProfit = netProfit;
        _isLoadingDetails = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _loadBranches() async {
    final branches = await _dbHelper.query('branches');
    if (!mounted) return;
    final branchList = List<Map<String, dynamic>>.from(branches);
    setState(() {
      _branches = branchList;
      _branchNamesById = {
        for (final branch in branchList)
          if ((branch['id'] as String?)?.isNotEmpty ?? false)
            branch['id'].toString(): (branch['name'] as String?) ??
                branch['id'].toString(),
      };
    });
  }

  String _branchNameForId(Object? id) {
    final branchId = id?.toString() ?? '';
    if (branchId.isEmpty) return 'Shared';
    return _branchNamesById[branchId] ?? branchId;
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatRangeLabel() {
    if (_selectedRange == null) return 'All dates';
    final start = _selectedRange!.start;
    final end = _selectedRange!.end;
    return '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}';
  }

  bool _matchesBranch(Map<String, dynamic> item) {
    if (_selectedBranchId == 'all') return true;
    final branchId = item['branchId']?.toString();
    return branchId == _selectedBranchId;
  }

  bool _matchesDate(Map<String, dynamic> item) {
    if (_selectedRange == null) return true;
    final timestamp = (item['date'] as num?)?.toInt();
    if (timestamp == null) return false;
    final start = DateTime(
      _selectedRange!.start.year,
      _selectedRange!.start.month,
      _selectedRange!.start.day,
    ).millisecondsSinceEpoch;
    final end = DateTime(
      _selectedRange!.end.year,
      _selectedRange!.end.month,
      _selectedRange!.end.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
    return timestamp >= start && timestamp <= end;
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    return _expenseItems
        .where(_matchesBranch)
        .where(_matchesDate)
        .where((item) => ((item['amount'] as num?)?.toDouble() ?? 0.0) > 0)
        .toList();
  }

  List<Map<String, dynamic>> get _filteredOrderProfit {
    return _orderProfitItems
        .where(_matchesBranch)
        .where(_matchesDate)
        .where(
          (item) =>
              ((item['actualProfit'] as num?)?.toDouble() ?? 0.0) != 0.0 ||
              ((item['idealProfit'] as num?)?.toDouble() ?? 0.0) != 0.0,
        )
        .toList();
  }

  double get _filteredExpenseTotal {
    return _filteredExpenses.fold<double>(
      0.0,
      (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0.0),
    );
  }

  double get _filteredActualProfitTotal {
    return _filteredOrderProfit.fold<double>(
      0.0,
      (total, item) => total + ((item['actualProfit'] as num?)?.toDouble() ?? 0.0),
    );
  }

  double get _filteredIdealProfitTotal {
    return _filteredOrderProfit.fold<double>(
      0.0,
      (total, item) => total + ((item['idealProfit'] as num?)?.toDouble() ?? 0.0),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupExpensesByCategory() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in _filteredExpenses) {
      final category = (item['category'] as String?) ?? 'Other';
      grouped.putIfAbsent(category, () => <Map<String, dynamic>>[]).add(item);
    }
    return grouped;
  }

  Map<String, List<Map<String, dynamic>>> _groupOrdersByBranch() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in _filteredOrderProfit) {
      final branchKey = item['branchId']?.toString() ?? '';
      grouped.putIfAbsent(branchKey, () => <Map<String, dynamic>>[]).add(item);
    }
    return grouped;
  }

  Widget _buildSummaryCard({
    required String title,
    required double value,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'ETB ${value.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.white,
        ),
      ),
    );
  }

  Widget _buildExpenseTile(Map<String, dynamic> item) {
    final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
    return Card(
      child: ListTile(
        title: Text('${item['category']}: ${item['title']}'),
        subtitle: Text(
          '${item['subtitle'] ?? ''}${item['date'] != null ? ' • ${_formatDate(item['date'] as int)}' : ''}',
        ),
        trailing: Text(
          'ETB ${amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildOrderProfitTile(Map<String, dynamic> item) {
    final actualProfit = (item['actualProfit'] as num?)?.toDouble() ?? 0;
    final idealProfit = (item['idealProfit'] as num?)?.toDouble() ?? 0;
    final actualRevenue = (item['actualRevenue'] as num?)?.toDouble() ?? 0;
    final idealRevenue = (item['idealRevenue'] as num?)?.toDouble() ?? 0;
    final cogs = (item['cogs'] as num?)?.toDouble() ?? 0;
    final commissions = (item['commissions'] as num?)?.toDouble() ?? 0;
    final unpaidAmount = idealRevenue - actualRevenue;
    final branchLabel = _branchNameForId(item['branchId']);
    return Card(
      child: ListTile(
        title: Text(item['customerName'] ?? 'Unknown customer'),
        subtitle: Text(
          'Order #${(item['orderId'] as String?)?.substring(0, 6) ?? ''}\n'
          'Branch: $branchLabel\n'
          'Actual Revenue: ETB ${actualRevenue.toStringAsFixed(2)} | Ideal Revenue: ETB ${idealRevenue.toStringAsFixed(2)}\n'
          'Unpaid: ETB ${unpaidAmount.toStringAsFixed(2)}\n'
          'COGS: ETB ${cogs.toStringAsFixed(2)} | Commissions: ETB ${commissions.toStringAsFixed(2)}\n'
          'Actual Profit: ETB ${actualProfit.toStringAsFixed(2)} | Ideal Profit: ETB ${idealProfit.toStringAsFixed(2)}',
        ),
        trailing: Text(
          'A ${actualProfit.toStringAsFixed(2)} / I ${idealProfit.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: actualProfit >= 0 ? AppColors.success : AppColors.error,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedActualProfit = _filteredActualProfitTotal;
    final displayedIdealProfit = _filteredIdealProfitTotal;
    final actualProfitPositive = displayedActualProfit >= 0;
    final idealProfitPositive = displayedIdealProfit >= 0;
    final filteredExpenses = _filteredExpenses;
    final filteredOrders = _filteredOrderProfit;
    final showingExpensesOnly = widget.showExpensesOnly;
    final expensesByCategory = _groupExpensesByCategory();
    final ordersByBranch = _groupOrdersByBranch();

    final branchItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('All Branches')),
      ..._branches.map(
        (branch) => DropdownMenuItem<String>(
          value: branch['id']?.toString() ?? '',
          child: Text(branch['name'] ?? branch['id'] ?? 'Branch'),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          showingExpensesOnly ? 'Expense Details' : 'Profit Details',
        ),
        backgroundColor: AppColors.primaryRed,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: _isLoadingDetails
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (showingExpensesOnly) ...[
              _buildSummaryCard(
                title: 'Expenses',
                value: _filteredExpenseTotal,
                color: AppColors.warning,
              ),
              const SizedBox(height: 12),
              _buildSummaryCard(
                title: 'COGS Total',
                value: _filteredExpenses
                    .where((item) => item['category'] == 'COGS')
                    .fold<double>(
                      0.0,
                      (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0.0),
                    ),
                color: AppColors.warning,
              ),
              const SizedBox(height: 8),
              _buildSummaryCard(
                title: 'Commissions Paid',
                value: _filteredExpenses
                    .where((item) => item['category'] == 'Commission')
                    .fold<double>(
                      0.0,
                      (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0.0),
                    ),
                color: AppColors.warning,
              ),
              const SizedBox(height: 8),
              _buildSummaryCard(
                title: 'Fuel',
                value: _filteredExpenses
                    .where((item) => item['category'] == 'Fuel')
                    .fold<double>(
                      0.0,
                      (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0.0),
                    ),
                color: AppColors.warning,
              ),
              const SizedBox(height: 8),
              _buildSummaryCard(
                title: 'Maintenance',
                value: _filteredExpenses
                    .where((item) => item['category'] == 'Maintenance')
                    .fold<double>(
                      0.0,
                      (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0.0),
                    ),
                color: AppColors.warning,
              ),
              const SizedBox(height: 8),
              _buildSummaryCard(
                title: 'Material Usage',
                value: _filteredExpenses
                    .where((item) => item['category'] == 'Material')
                    .fold<double>(
                      0.0,
                      (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0.0),
                    ),
                color: AppColors.warning,
              ),
            ] else ...[
              _buildSummaryCard(
                title: 'Actual Profit',
                value: displayedActualProfit,
                color: actualProfitPositive ? AppColors.success : AppColors.error,
              ),
              const SizedBox(height: 12),
              _buildSummaryCard(
                title: 'Ideal Profit',
                value: displayedIdealProfit,
                color: idealProfitPositive ? AppColors.success : AppColors.error,
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedBranchId,
                      decoration: const InputDecoration(
                        labelText: 'Branch filter',
                        border: OutlineInputBorder(),
                      ),
                      items: branchItems,
                      onChanged: (value) {
                        setState(() {
                          _selectedBranchId = value ?? 'all';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _selectedRange == null
                            ? 'Using the global dashboard date filter: All dates'
                            : 'Using the global dashboard date filter: ${_formatRangeLabel()}',
                        style: const TextStyle(color: AppColors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedBranchId = 'all';
                        });
                        _loadDetails();
                      },
                      child: const Text('Reset branch filter'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      showingExpensesOnly
                          ? 'Change the date from the dashboard card. This screen only follows the global range and branch filter.'
                          : 'Change the date from the dashboard card. This screen only follows the global range and branch filter.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            _buildSectionTitle(
              showingExpensesOnly ? 'Expense Breakdown' : 'Order Profit Breakdown',
            ),
            if (showingExpensesOnly) ...[
              if (filteredExpenses.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('No expense details found'),
                  ),
                )
              else
                ...expensesByCategory.entries.expand((entry) {
                  final items = entry.value;
                  final subtotal = items.fold<double>(
                    0.0,
                    (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0.0),
                  );
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Text(
                        '${entry.key} • ETB ${subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    ...items.map(_buildExpenseTile),
                  ];
                }),
            ] else ...[
              if (filteredOrders.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('No order profit details found'),
                  ),
                )
              else
                ...ordersByBranch.entries.expand((entry) {
                  final items = entry.value;
                  final actualSubtotal = items.fold<double>(
                    0.0,
                    (total, item) => total + ((item['actualProfit'] as num?)?.toDouble() ?? 0.0),
                  );
                  final idealSubtotal = items.fold<double>(
                    0.0,
                    (total, item) => total + ((item['idealProfit'] as num?)?.toDouble() ?? 0.0),
                  );
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Text(
                        '${_branchNameForId(entry.key)} • Actual ETB ${actualSubtotal.toStringAsFixed(2)} • Ideal ETB ${idealSubtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    ...items.map(_buildOrderProfitTile),
                  ];
                }),
            ],
          ],
        ),
      ),
    );
  }
}

