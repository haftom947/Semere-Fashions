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
import '../services/financial_calculator.dart';
import '../services/sync_service.dart';
import '../services/low_stock_service.dart';
import '../utils/error_handler.dart';
import 'profit_details_screen.dart';
import 'add_employee_screen.dart';
import 'orders_list_screen.dart';
import 'order_details_screen.dart';
import 'inventory_screen.dart';
import 'employee_list_screen.dart';
import 'customers_screen.dart';
import 'reports_screen.dart';
import 'shipment_dashboard_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({Key? key}) : super(key: key);

  @override
  _AdminHomeState createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FinancialCalculator _financialCalculator = FinancialCalculator();
  final SyncService _syncService = SyncService();
  Timer? _lowStockTimer;
  StreamSubscription? _lowStockSubscription;
  DateTimeRange? get currentRange => AppDateFilter.instance.range;
  String? _selectedBranchId;
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
  int _cancelledBefore = 0;
  int _cancelledAfter = 0;
  int _returnedCount = 0;

  // Financial stats
  double _totalRevenue = 0.0;
  double _salesTotal = 0.0;
  double _toCollectAmount = 0.0;
  double _totalExpenses = 0.0; // will be sum of the breakdown below
  double _profit = 0.0;
  double _cogs = 0.0;
  double _otherExpenses = 0.0;
  double _losses = 0.0;
  double _grossProfit = 0.0;
  double _netProfit = 0.0;
  double _cancelledPayments = 0.0;

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

  // Currencies for currency-specific financials (moved to ProfitDetailsScreen)

  // Rental summary
  double _rentalIncome = 0.0;
  double _rentalExpense = 0.0;
  double _rentalNet = 0.0;
  double _tenantOverdue = 0.0;
  double _landlordOverdue = 0.0;
  double _rentalOccupancyRate = 0.0;
  @override
  void initState() {
    super.initState();
    _loadAdminData();
    _loadStats();
    // currencies moved into ProfitDetailsScreen; no longer loaded here
    _loadRentalSummary();
    AppDateFilter.instance.rangeNotifier.addListener(_handleGlobalRangeChanged);

    // Listen to sync events to refresh data
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      print('Ã°Å¸â€â€ž Data changed Ã¢â‚¬â€œ reloading stats');
      _loadStats();
      // currencies moved into ProfitDetailsScreen; no longer loaded here
      _loadRentalSummary();
    });

    _startLowStockPeriodicCheck();
    _listenToLowStock();

    // Trigger an initial sync to load data from Firebase
    _syncService.syncAll().then((_) {
      print('Ã¢Å“â€¦ Initial sync completed');
      // Refresh stats again after sync
      _loadStats();
      // currencies moved into ProfitDetailsScreen; no longer loaded here
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

  /// Consistently parses dynamic values to doubles to prevent runtime casting errors.
  double _asDouble(dynamic value) {
    if (value is String) return double.tryParse(value) ?? 0.0;
    return (value as num?)?.toDouble() ?? 0.0;
  }

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
    AppDateFilter.instance.rangeNotifier.removeListener(
      _handleGlobalRangeChanged,
    );
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
    const cacheVersion = 'v4';
    if (range == null) return 'dashboard_${cacheVersion}_all';
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
    return 'dashboard_${cacheVersion}_${start}_$end';
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
      _cancelledBefore = (cached['cancelledBefore'] as num?)?.toInt() ?? 0;
      _cancelledAfter = (cached['cancelledAfter'] as num?)?.toInt() ?? 0;
      _returnedCount = (cached['returnedCount'] as num?)?.toInt() ?? 0;
      _totalRevenue = (cached['totalRevenue'] as num?)?.toDouble() ?? 0.0;
      _salesTotal = (cached['salesTotal'] as num?)?.toDouble() ?? 0.0;
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
      _losses = (cached['losses'] as num?)?.toDouble() ?? 0.0;
      _grossProfit = (cached['grossProfit'] as num?)?.toDouble() ?? 0.0;
      _cancelledPayments =
          (cached['cancelledPayments'] as num?)?.toDouble() ?? 0.0;
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

    final summary = await _financialCalculator.calculateSummary(
      range: selectedRange,
    );

    var orders = await _dbHelper.query('orders');
    var payments = await _dbHelper.query('payment_transaction');
    var commissions = await _dbHelper.query('commissions');
    var fuelLogs = await _dbHelper.query('fuel_logs');
    var maintenanceLogs = await _dbHelper.query('maintenance_logs');
    var materialUsage = await _dbHelper.query('material_usage');
    var losses = await _dbHelper.query('losses');
    var materials = await _dbHelper.query('materials');
    var products = await _dbHelper.query('products');

    List<Map<String, dynamic>> ordersList = List.from(orders);
    List<Map<String, dynamic>> mutablePayments = List.from(payments);
    List<Map<String, dynamic>> mutableCommissions = List.from(commissions);
    List<Map<String, dynamic>> mutableFuel = List.from(fuelLogs);
    List<Map<String, dynamic>> mutableMaintenance = List.from(maintenanceLogs);
    List<Map<String, dynamic>> mutableMaterialUsage = List.from(materialUsage);
    List<Map<String, dynamic>> mutableLosses = List.from(losses);
    List<Map<String, dynamic>> mutableMaterials = List.from(materials);
    List<Map<String, dynamic>> mutableProducts = List.from(products);

    final materialNamesById = <String, String>{
      for (final material in mutableMaterials)
        if ((material['id'] as String?)?.isNotEmpty ?? false)
          material['id'] as String:
              (material['name'] as String?) ?? material['id'] as String,
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
        paymentsByOrderId[orderId] =
            (paymentsByOrderId[orderId] ?? 0.0) + amount;
      } else {
        paymentsByOrderId[orderId] =
            (paymentsByOrderId[orderId] ?? 0.0) - amount;
      }
    }

    final expenseItems = <Map<String, dynamic>>[];
    final orderProfitItems = <Map<String, dynamic>>[];
    double salesTotal = 0.0;
    double orderMaterialCogs = 0.0;
    double revenue = 0.0; // Actual cash collected
    double totalExpenses = 0.0;

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
      if (!withinSelectedRange(createdAt)) continue;
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      final totalAmount = _asDouble(order['totalAmount']);

      if (status != 'cancelled' && status != 'returned') {
        salesTotal += totalAmount;
      }

      final orderId = order['id']?.toString() ?? '';
      double linkedOrderMaterialCost = 0.0;
      if (status == 'delivered' || status == 'completed') {
        final cogsAmount = _asDouble(order['cogs']);
        weekExpenses += cogsAmount;
        totalExpenses += cogsAmount;

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
                'Order #${orderId.substring(0, orderId.length < 6 ? orderId.length : 6)} â€¢ Qty ${quantity.toStringAsFixed(0)} Ã— ETB ${unitCost.toStringAsFixed(2)}',
            'amount': lineCogs,
            'date': createdAt,
            'branchId': order['branchId'],
          });
        }

        for (final mu in mutableMaterialUsage) {
          final muOrderId = mu['orderId']?.toString();
          final muType = mu['type']?.toString() ?? 'order';
          if (muType != 'order' || muOrderId != orderId) continue;
          final amount = _asDouble(mu['cost']);
          if (amount <= 0) continue;
          if (amount <= 0.0) continue;
          linkedOrderMaterialCost += amount;
          weekExpenses += amount;
          totalExpenses += amount;
          final materialId = mu['material_id']?.toString();
          expenseItems.add({
            'category': 'COGS',
            'title':
                materialNamesById[materialId] ??
                materialId ??
                'Order material usage',
            'subtitle':
                'Order #${orderId.substring(0, orderId.length < 6 ? orderId.length : 6)}',
            'amount': amount,
            'date': createdAt,
            'branchId': order['branchId'],
          });
        }

        if (cogsAmount > itemCogsTotal) {
          final remainder = cogsAmount - itemCogsTotal;
          expenseItems.add({
            'category': 'COGS',
            'title': 'Unmapped COGS',
            'subtitle':
                'Order #${orderId.substring(0, orderId.length < 6 ? orderId.length : 6)}',
            'amount': remainder,
            'date': createdAt,
            'branchId': order['branchId'],
          });
        }
      }

      final idealRevenue = totalAmount;
      final actualRevenue = paymentsByOrderId[orderId] ?? 0.0;
      final orderCommissions = mutableCommissions
          .where((c) {
            if (c['orderId'] != order['id']) return false;
            if (c['status'] == 'voided') return false;
            final effectiveDate = c['createdAt'] ?? c['paidAt'];
            return withinSelectedRange(effectiveDate);
          })
          .fold<double>(0.0, (total, c) => total + _asDouble(c['amount']));
      final cogsValue = _asDouble(order['cogs']) + linkedOrderMaterialCost;
      orderMaterialCogs += linkedOrderMaterialCost;
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

    // Calculate Revenue from payments within range
    for (var p in mutablePayments) {
      if (withinSelectedRange(p['date'])) {
        final amount = _asDouble(p['amount']);
        revenue += (p['type'] == 'payment' ? amount : -amount);
      }
    }

    for (var c in mutableCommissions) {
      if (c['status'] == 'voided') continue;
      final effectiveDate = c['createdAt'] ?? c['paidAt'];
      if (effectiveDate == null || !withinSelectedRange(effectiveDate))
        continue;
      final amount = _asDouble(c['amount']);
      weekExpenses += amount;
      totalExpenses += amount;
      final linkedOrder = ordersList.firstWhere(
        (order) => order['id'] == c['orderId'],
        orElse: () => <String, dynamic>{},
      );
      expenseItems.add({
        'category': 'Commission',
        'title': c['employeeName'] ?? 'Commission',
        'subtitle':
            'Order #${(c['orderId'] as String?)?.substring(0, 6) ?? ''}',
        'amount': amount,
        'date': _asInt(effectiveDate),
        'branchId': linkedOrder['branchId'],
      });
    }
    for (var f in mutableFuel) {
      if (withinSelectedRange(f['date'])) {
        final amount = _asDouble(f['cost']);
        weekExpenses += amount;
        totalExpenses += amount;
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
        totalExpenses += amount;
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
      if (!withinSelectedRange(mu['date'])) continue;
      final amount = _asDouble(mu['cost']);
      final usageType = mu['type']?.toString() ?? 'order';
      if (usageType != 'general') continue;
      weekExpenses += amount;
      totalExpenses += amount;
      final materialId = mu['material_id'] as String?;
      expenseItems.add({
        'category': 'Material',
        'title':
            materialNamesById[materialId] ??
            materialId ??
            'General material usage',
        'subtitle':
            'Qty ${(mu['quantity'] as num?)?.toStringAsFixed(0) ?? '0'}',
        'amount': amount,
        'date': _asInt(mu['date']),
      });
    }
    for (final loss in mutableLosses) {
      if (!withinSelectedRange(loss['date'])) continue;
      final amount = _asDouble(loss['amount']);
      if (amount <= 0) continue;
      weekExpenses += amount;
      totalExpenses += amount;
      expenseItems.add({
        'category': 'Loss',
        'title': loss['type'] ?? 'Loss',
        'subtitle': loss['reason'] ?? 'Uncategorised loss',
        'amount': amount,
        'date': _asInt(loss['date']),
        'branchId': loss['branchId'],
      });
    }
    final weekProfit = weekRevenue - weekExpenses;
    final calculatedNetProfit = revenue - totalExpenses;
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
      if (c['status'] == 'paid' &&
          c['paidAt'] != null &&
          withinSelectedRange(c['paidAt'])) {
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
      if (!withinSelectedRange(mu['date'])) continue;
      final amount = _asDouble(mu['cost']);
      final usageType = mu['type']?.toString() ?? 'order';
      if (usageType == 'general') {
        materialExpenses += amount;
      }
    }

    double lossesExpense = 0.0;
    for (final loss in mutableLosses) {
      if (!withinSelectedRange(loss['date'])) continue;
      lossesExpense += _asDouble(loss['amount']);
    }

    final cogs = cogsFromOrders + orderMaterialCogs;
    final otherExpenses =
        commissionExpenses +
        fuelExpenses +
        maintenanceExpenses +
        materialExpenses;
    final grossProfit = revenue - cogs;
    final netProfit = grossProfit - otherExpenses - lossesExpense;
    final profit = netProfit;

    int total = 0;
    int pending = 0,
        completed = 0,
        withDriver = 0,
        cancelled = 0,
        returned = 0,
        processingCount = 0;
    int cancelledBefore = 0, cancelledAfter = 0;
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
      (a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int),
    );
    var recent = ordersList.take(5).toList();
    expenseItems.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
    orderProfitItems.sort(
      (a, b) => (b['date'] as int).compareTo(a['date'] as int),
    );

    setState(() {
      // Order stats
      _totalOrders = total;
      _pendingOrders = pending;
      _completedOrders = completed;
      _withDriverCount = withDriver;
      _processingCount = processingCount;
      _cancelledCount = cancelled;
      _cancelledBefore = cancelledBefore;
      _cancelledAfter = cancelledAfter;
      _returnedCount = returned;

      // Financial stats (selected period)
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
      _expenseItems = summary.expenseItems.map((item) => item.toMap()).toList();
      _orderProfitItems = summary.orderProfitItems
          .map((item) => item.toMap())
          .toList();
      // Week profit
      _weekProfit = summary.weekProfit;

      // Recent orders
      _recentOrders = recent;
    });

    unawaited(
      _dbHelper.saveCache(cacheKey, {
        'totalOrders': total,
        'pendingOrders': pending,
        'completedOrders': completed,
        'withDriverCount': withDriver,
        'processingCount': processingCount,
        'cancelledCount': cancelled,
        'cancelledBefore': cancelledBefore,
        'cancelledAfter': cancelledAfter,
        'returnedCount': returned,
        'totalRevenue': summary.revenue,
        'salesTotal': summary.salesTotal,
        'toCollectAmount': toCollect,
        'cogs': summary.cogs,
        'cogsFromOrders': summary.cogsFromOrders,
        'tailorCommissions': summary.tailorCommissions,
        'salesCommissions': summary.salesCommissions,
        'deliveryCommissions': summary.deliveryCommissions,
        'commissionExpenses': summary.commissionExpenses,
        'fuelExpenses': summary.fuelExpenses,
        'maintenanceExpenses': summary.maintenanceExpenses,
        'materialExpenses': summary.materialExpenses,
        'otherExpenses': summary.otherExpenses,
        'losses': summary.losses,
        'grossProfit': summary.grossProfit,
        'cancelledPayments': summary.cancelledPayments,
        'netProfit': summary.netProfit,
        'totalExpenses': summary.totalExpenses,
        'profit': summary.netProfit,
        'weekProfit': summary.weekProfit,
        'recentOrders': recent,
      }),
    );
  }

  void _showExpensesBreakdown() {
    // Old ProfitDetailsScreen navigation removed. Use currency reports instead.
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

      final net = income - expense;

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
      int total = rentalProperties.length;
      int occupied = rentalProperties
          .where((p) => p['status'] == 'occupied')
          .length;
      double occupancy = total > 0 ? (occupied / total) * 100 : 0;

      setState(() {
        _rentalIncome = income;
        _rentalExpense = expense;
        _rentalNet = net;
        _tenantOverdue = tenantOverdue;
        _landlordOverdue = landlordOverdue;
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

  void _navigateToShipments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ShipmentDashboardScreen(),
      ),
    );
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
        builder: (context) =>
            PurchaseOrdersListScreen(initialStatus: 'received'),
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
      builder: (_) => ProfitDetailsScreen(
        dateRange: currentRange,      // The global date range (DateTimeRange? variable)
        branchId: _selectedBranchId,  // The branch filter (String? variable; may be null)
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
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/images/dashboard_header.png',
                            fit: BoxFit.cover,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.58, 0.82, 1.0],
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  AppColors.backgroundStart.withOpacity(0.32),
                                  AppColors.backgroundEnd.withOpacity(0.52),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Text(
                          'Welcome back, ${_adminName.split(' ').first}!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
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
                        _buildStatusGrid(),
                        const SizedBox(height: 24),

                        // Rental Summary
                        _buildRentalSummary(),
                        const SizedBox(height: 24),

                        // Top Customers
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getTopCustomers(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty)
                              return const SizedBox();
                            var topCustomers = snapshot.data!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'TOP CUSTOMERS',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.white,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _navigateToCustomers,
                                      child: const Text(
                                        'See All >',
                                        style: TextStyle(
                                          color: AppColors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primaryRed,
                                      child: Text(
                                        (topCustomers.first['name'][0])
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    title: Text(topCustomers.first['name']),
                                    subtitle: Text(
                                      '${topCustomers.first['orders']} orders',
                                    ),
                                    trailing: Text(
                                      'ETB ${(topCustomers.first['total'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                    ),
                                    onTap: () {
                                      // Optionally navigate to orders filtered by this customer
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              OrdersListScreen(
                                                showUnpaidOnly: false,
                                              ),
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
                                    'View All >',
                                    style: TextStyle(color: AppColors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _recentOrders.isEmpty
                                ? const Text(
                                    'No recent orders',
                                    style: TextStyle(color: AppColors.white),
                                  )
                                : Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _getStatusColor(
                                          _recentOrders.first['status'],
                                        ),
                                        child: Text(
                                          (_recentOrders.first['id']?.substring(0, 1) ?? '#'),
                                          style: const TextStyle(
                                            color: AppColors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        _recentOrders.first['customerName'] ?? 'Unknown',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '#${_recentOrders.first['id']?.substring(0, 6)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'ETB ${(_recentOrders.first['totalAmount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(
                                                _recentOrders.first['status'],
                                              ).withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _recentOrders.first['status'] ??
                                                  'pending',
                                              style: TextStyle(
                                                color: _getStatusColor(
                                                  _recentOrders.first['status'],
                                                ),
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
                                            builder: (context) =>
                                                OrderDetailsScreen(
                                                  orderId:
                                                      _recentOrders.first['id'],
                                                ),
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
                        const SizedBox(height: 16),
                      ]),
                    ),
                  ),
                ],
              ),
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
                Icons.person_add,
                'Add Employee',
                AppColors.primaryRed,
                _navigateToAddEmployee,
              ),
              _buildQuickActionCard(
                Icons.shopping_bag,
                'New Order',
                AppColors.success,
                _navigateToCreateOrder,
              ),
              _buildQuickActionCard(
                Icons.inventory,
                'Add Stock',
                AppColors.info,
                _navigateToInventory,
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

  double _statusCardWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const horizontalPadding = 16.0;
    const spacing = 4.0;
    const totalSpacing = spacing * 2;
    final availableWidth = screenWidth - (horizontalPadding * 2) - totalSpacing;
    return availableWidth / 3;
  }

  Widget _buildStatusCard(Map<String, dynamic> status, VoidCallback? onTap) {
    final cardWidth = _statusCardWidth(context);
    return SizedBox(
      width: cardWidth,
      height: 105,
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          color: AppColors.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(status['icon'] as IconData, color: status['color'] as Color, size: 22),
                const SizedBox(height: 6),
                Text(
                  '${status['count']}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: status['color'] as Color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  status['label'] as String,
                  style: const TextStyle(fontSize: 11, color: AppColors.darkGrey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusGrid() {
    final statuses = [
      {'label': 'Total', 'count': _totalOrders, 'icon': Icons.receipt_long, 'color': AppColors.info},
      {'label': 'Pending', 'count': _pendingOrders, 'icon': Icons.hourglass_empty, 'color': AppColors.warning},
      {'label': 'Processing', 'count': _processingCount, 'icon': Icons.settings, 'color': AppColors.info},
      {'label': 'Completed', 'count': _completedOrders, 'icon': Icons.check_circle, 'color': AppColors.success},
      {'label': 'Cancelled', 'count': _cancelledBefore + _cancelledAfter, 'icon': Icons.cancel, 'color': AppColors.error},
      {'label': 'With Driver', 'count': _withDriverCount, 'icon': Icons.local_shipping, 'color': AppColors.warning},
    ];

    return Column(
      children: [
        Row(
          children: [
            _buildStatusCard(statuses[0], () => _navigateToOrdersWithStatus(null)),
            const SizedBox(width: 4),
            _buildStatusCard(statuses[1], () => _navigateToOrdersWithStatus('pending')),
            const SizedBox(width: 4),
            _buildStatusCard(statuses[2], () => _navigateToOrdersWithStatus('processing')),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildStatusCard(statuses[3], () => _navigateToOrdersWithStatus('delivered')),
            const SizedBox(width: 4),
            _buildStatusCard(statuses[4], () => _navigateToOrdersWithStatus('cancelled')),
            const SizedBox(width: 4),
            _buildStatusCard(statuses[5], () => _navigateToOrdersWithStatus('out_for_delivery')),
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

  int _getProcessingCount() {
    return _processingCount;
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
            onTap: _navigateToProfitDetails,
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
}
