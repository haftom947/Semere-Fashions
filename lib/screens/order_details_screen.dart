import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/colors.dart';
import '../services/barcode_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/error_handler.dart';
import 'employee_selector_dialog.dart';
import 'record_payment_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailsScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _dataChangedSubscription;

  Map<String, dynamic>? _order;
  String? _branchName;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _commissions = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _statusLogs = [];
  bool _isLoading = true;
  bool _paymentsLoading = false;
  bool _isAdminOrManager = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _dataChangedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final loadId = ++_loadGeneration;
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final orderData = await _dbHelper.queryById('orders', widget.orderId);
      if (!mounted || loadId != _loadGeneration) return;

      Map<String, dynamic>? order;
      List<Map<String, dynamic>> items = [];
      List<Map<String, dynamic>> assignments = [];
      List<Map<String, dynamic>> employees = [];
      List<Map<String, dynamic>> commissions = [];
      List<Map<String, dynamic>> payments = [];
      List<Map<String, dynamic>> statusLogs = [];
      String? branchName;

      if (orderData != null) {
        order = Map<String, dynamic>.from(orderData);

        if (order['items'] is String) {
          items = List<Map<String, dynamic>>.from(jsonDecode(order['items']));
        } else {
          items = List<Map<String, dynamic>>.from(
            order['items'] as List? ?? [],
          );
        }

        final allAssignments = await _dbHelper.query('order_assignments');
        if (!mounted || loadId != _loadGeneration) return;
        assignments = allAssignments
            .where((a) => a['orderId'] == widget.orderId)
            .map((a) => Map<String, dynamic>.from(a))
            .toList();

        final allEmployees = await _dbHelper.query('users');
        if (!mounted || loadId != _loadGeneration) return;
        employees = allEmployees
            .where((e) => e['status'] == 'active')
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final branchId = order['branchId'] as String?;
        if (branchId != null && branchId.isNotEmpty) {
          final branch = await _dbHelper.queryById('branches', branchId);
          if (!mounted || loadId != _loadGeneration) return;
          branchName = branch?['name'] ?? branchId;
        } else {
          branchName = null;
        }

        final allCommissions = await _dbHelper.query('commissions');
        if (!mounted || loadId != _loadGeneration) return;
        commissions = allCommissions
            .where((c) => c['orderId'] == widget.orderId)
            .map((c) => Map<String, dynamic>.from(c))
            .toList();

        statusLogs = await _dbHelper.getStatusLogsForOrder(widget.orderId);
        if (!mounted || loadId != _loadGeneration) return;

        try {
          final localPayments = await _dbHelper.getPaymentsForOrder(
            widget.orderId,
          );
          if (!mounted || loadId != _loadGeneration) return;

          payments = List<Map<String, dynamic>>.from(localPayments)
              .map(Map<String, dynamic>.from)
              .toList();

          if (payments.isEmpty) {
            await _syncService.syncPaymentsForOrder(widget.orderId);
            if (!mounted || loadId != _loadGeneration) return;
            final refreshedPayments = await _dbHelper.getPaymentsForOrder(
              widget.orderId,
            );
            if (!mounted || loadId != _loadGeneration) return;
            payments = List<Map<String, dynamic>>.from(refreshedPayments)
                .map(Map<String, dynamic>.from)
                .toList();
          }
          print('Loaded ${payments.length} payments for order ${widget.orderId}');
        } catch (e) {
          print('Payment table error: $e');
          payments = [];
        }
      }

      if (!mounted || loadId != _loadGeneration) return;
      setState(() {
        _order = order;
        _items = items;
        _assignments = assignments;
        _employees = employees;
        _branchName = branchName;
        _commissions = commissions;
        _payments = payments;
        _statusLogs = statusLogs;
        _paymentsLoading = false;
        _isLoading = false;
      });
    } catch (e, stack) {
      print('Error loading order details: $e');
      print(stack);
      if (mounted && loadId == _loadGeneration) {
        ErrorHandler.showError(
          context,
          'Failed to load order details: ${e.toString()}',
        );
        setState(() {
          _isLoading = false;
          _paymentsLoading = false;
        });
      }
    }
  }

  double _calculateItemsSubtotal() {
    double subtotal = 0;
    for (final item in _items) {
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
      final price = (item['price'] as num?)?.toDouble() ?? 0;
      subtotal += quantity * price;
    }
    return subtotal;
  }

  double _calculateDiscountAmount({double? deliveryFeeOverride}) {
    if (_order == null) return 0;
    final subtotal = _calculateItemsSubtotal();
    final deliveryFee =
        deliveryFeeOverride ??
        (_order!['delivery_fee'] as num?)?.toDouble() ??
        0;
    final discountValue = (_order!['discount_value'] as num?)?.toDouble() ?? 0;
    final discountType = _order!['discount_type'] ?? 'none';
    final discountBase = subtotal + deliveryFee;

    if (discountType == 'percentage') {
      return discountBase * discountValue / 100;
    } else if (discountType == 'fixed') {
      return discountValue;
    }
    return 0;
  }

  double _calculateOrderTotal({double? deliveryFeeOverride}) {
    final subtotal = _calculateItemsSubtotal();
    final deliveryFee =
        deliveryFeeOverride ??
        (_order?['delivery_fee'] as num?)?.toDouble() ??
        0;
    final discountAmount = _calculateDiscountAmount(
      deliveryFeeOverride: deliveryFee,
    );
    final total = subtotal + deliveryFee - discountAmount;
    return total < 0 ? 0 : total;
  }

  Future<void> _updateDeliveryFee(double fee) async {
    if (_order == null) return;

    final updatedOrder = Map<String, dynamic>.from(_order!);
    updatedOrder['delivery_fee'] = fee;
    updatedOrder['totalAmount'] = _calculateOrderTotal(
      deliveryFeeOverride: fee,
    );

    await _dbHelper.update('orders', updatedOrder);
    _order = updatedOrder;
    _syncService.emitDataChanged();
  }

  Future<double?> _showDeliveryFeeDialog() async {
    final controller = TextEditingController(
      text: ((_order?['delivery_fee'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(0),
    );

    return showDialog<double>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text(
            'Delivery Fee',
            style: TextStyle(color: Colors.black),
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Delivery Fee (ETB)',
              labelStyle: TextStyle(color: Colors.black54),
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
            ElevatedButton(
              onPressed: () {
                final fee = double.tryParse(controller.text.trim());
                if (fee != null && fee >= 0) {
                  Navigator.pop(context, fee);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<double?> _showAmountDialog({
    required String title,
    required String label,
    required double initialValue,
    String? helperText,
  }) async {
    final controller = TextEditingController(
      text: initialValue.toStringAsFixed(initialValue % 1 == 0 ? 0 : 2),
    );

    return showDialog<double>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: Text(title, style: const TextStyle(color: Colors.black)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (helperText != null) ...[
                Text(helperText, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: label,
                  labelStyle: const TextStyle(color: Colors.black54),
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(controller.text.trim());
                if (amount != null && amount >= 0) {
                  Navigator.pop(context, amount);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _deductStockIfNeeded(Map<String, dynamic> updatedOrder) async {
    if (updatedOrder['stock_deducted'] == 1) return true;

    double totalCogs = 0.0; // <-- add this variable

    for (final item in _items) {
      final productId = item['productId'];
      if (productId == null) continue;

      final product = await _dbHelper.queryById('products', productId);
      if (product == null) {
        if (mounted)
          ErrorHandler.showError(
            context,
            'Product not found for ${item['description']}',
          );
        return false;
      }

      final currentStock = (product['stock'] as num?)?.toInt() ?? 0;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      if (currentStock < quantity) {
        if (mounted)
          ErrorHandler.showError(
            context,
            'Not enough stock for ${item['description']}',
          );
        return false;
      }

      final updatedProduct = Map<String, dynamic>.from(product);
      updatedProduct['stock'] = currentStock - quantity;
      await _dbHelper.update('products', updatedProduct);

      // Add to COGS
      final productCost = (product['costPrice'] as num?)?.toDouble() ?? 0.0;
      totalCogs += productCost * quantity; // <-- accumulate cost
    }

    updatedOrder['stock_deducted'] = 1;
    updatedOrder['cogs'] = totalCogs; // <-- store in order
    return true;
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_order == null) return;

    setState(() => _isLoading = true);
    try {
      final previousStatus = _order!['status']?.toString();
      if (newStatus == 'cancelled' && previousStatus == 'delivered') {
        if (mounted) {
          ErrorHandler.showError(
            context,
            'Delivered orders cannot be cancelled. Use refund instead.',
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      final updatedOrder = Map<String, dynamic>.from(_order!);
      updatedOrder['status'] = newStatus;

      if (newStatus == 'cancelled') {
        await _restoreOptimisticStockIfNeeded(updatedOrder);
      }

      if (newStatus == 'out_for_delivery' &&
          (updatedOrder['stock_deducted'] ?? 0) != 1) {
        final deducted = await _deductStockIfNeeded(updatedOrder);
        if (!deducted) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      await _dbHelper.update('orders', updatedOrder);
      final changedBy = await _resolveCurrentUserName();
      await _dbHelper.insertStatusLog(
        orderId: widget.orderId,
        newStatus: newStatus,
        changedBy: changedBy,
        changedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _order = updatedOrder;

      if (newStatus == 'delivered') {
        await _createTailorCommission();
        await _calculateAllCommissions();
        await _recalculateSalesCommission(); // Recalculate sales commission after all other commissions are set
      }

      if (newStatus == 'cancelled') {
        await _voidCommissionsOnly(previousStatus);
        if (mounted) {
          ErrorHandler.showSuccess(context, 'Order cancelled.');
        }
      }

      final connectivityResults = await Connectivity().checkConnectivity();
      if (!connectivityResults.contains(ConnectivityResult.none)) {
        _syncService.syncAll();
      }

      await _loadData();
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, 'Failed to update order status: $e');
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String> _resolveCurrentUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId =
          prefs.getString('userId') ?? FirebaseAuth.instance.currentUser?.uid;
      if (userId != null && userId.isNotEmpty) {
        final user = await _dbHelper.queryById('users', userId);
        final name = user?['name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'Unknown user';
  }

  Future<void> _printLabel() async {
    if (_order == null) return;
    await BarcodeService.printLabel(
      orderId: widget.orderId,
      customerName: _order!['customerName']?.toString(),
      status: _order!['status']?.toString(),
      branchName: _branchName,
      createdAtLabel: _formatDate((_order!['createdAt'] as num?)?.toInt() ?? 0),
    );
  }

  Future<void> _shareLabel() async {
    if (_order == null) return;
    await BarcodeService.shareLabel(
      orderId: widget.orderId,
      customerName: _order!['customerName']?.toString(),
      status: _order!['status']?.toString(),
      branchName: _branchName,
      createdAtLabel: _formatDate((_order!['createdAt'] as num?)?.toInt() ?? 0),
    );
  }

  Future<void> _restoreOptimisticStockIfNeeded(
    Map<String, dynamic> order,
  ) async {
    if ((order['stock_deducted'] as num?)?.toInt() == 1) {
      return;
    }

    for (final item in _items) {
      final productId = item['productId']?.toString();
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      if (productId == null || productId.isEmpty || quantity <= 0) {
        continue;
      }
      await _dbHelper.increaseProductStock(productId, quantity);
    }
  }

  Future<void> _voidCommissionsOnly(String? currentStatus) async {
    final deliveryHappened =
        currentStatus == 'out_for_delivery' || currentStatus == 'delivered';

    for (final comm in _commissions) {
      if (comm['status']?.toString() == 'voided') continue;

      final type = comm['type']?.toString();
      bool shouldVoid = false;

      if (type == 'sales') {
        shouldVoid = true;
      } else if (type == 'tailor') {
        shouldVoid = false;
      } else if (type == 'delivery') {
        shouldVoid = !deliveryHappened;
      }

      if (!shouldVoid) continue;

      final updatedCommission = Map<String, dynamic>.from(comm);
      updatedCommission['status'] = 'voided';
      await _dbHelper.update('commissions', updatedCommission);
    }
  }

  bool _hasCommissionFor({required String employeeId, required String type}) {
    return _commissions.any(
      (comm) =>
          comm['orderId'] == widget.orderId &&
          comm['employeeId']?.toString() == employeeId &&
          comm['type']?.toString() == type &&
          comm['status']?.toString() != 'voided',
    );
  }

  Future<void> _recalculateSalesCommission() async {
    if (_order == null || _order!['status']?.toString() != 'delivered') {
      return; // Only recalculate for delivered orders
    }

    final salesPersonId = _order!['salesPersonId'];
    if (salesPersonId == null) return;

    final salesPerson = await _dbHelper.queryById('users', salesPersonId);
    if (salesPerson == null) return;

    final commissionRate = (salesPerson['commissionRate'] as num?)?.toDouble() ?? 0;
    if (commissionRate <= 0) return;

    final totalAmount = (_order!['totalAmount'] as num?)?.toDouble() ?? 0;
    final cogsValue = (_order!['cogs'] as num?)?.toDouble() ?? 0;
    final grossProfit = (totalAmount - cogsValue).clamp(0.0, double.infinity);
    if (grossProfit <= 0) return;

    final otherCuts = await _dbHelper.getNonSalesCommissionsForOrder(widget.orderId);
    final baseForSales = (grossProfit - otherCuts).clamp(0.0, double.infinity);
    final newSalesCommission = baseForSales * (commissionRate / 100);

    final existingSalesCommission = _commissions.firstWhere(
      (c) => c['employeeId'] == salesPersonId && c['type'] == 'sales',
      orElse: () => <String, dynamic>{},
    );

    if (existingSalesCommission.isNotEmpty) {
      // Update existing commission
      final updatedCommission = Map<String, dynamic>.from(existingSalesCommission);
      updatedCommission['amount'] = newSalesCommission;
      updatedCommission['syncStatus'] = 'pending';
      await _dbHelper.update('commissions', updatedCommission);
    } else if (newSalesCommission > 0) {
      // Create new commission (edge case, but good to handle)
      await _dbHelper.insert('commissions', {
        'orderId': widget.orderId,
        'employeeId': salesPersonId,
        'employeeName': salesPerson['name'] ?? '',
        'amount': newSalesCommission,
        'type': 'sales',
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
    // No need to call _loadData() here, it is usually called by the method triggering this recalc
  }

  Future<void> _createTailorCommission() async {
    final tailorAssignment = _assignments.firstWhere(
      (a) => a['role']?.toString() == 'tailor',
      orElse: () => <String, dynamic>{},
    );
    if (tailorAssignment.isEmpty) return;

    final tailorId = tailorAssignment['employeeId']?.toString() ?? '';
    if (tailorId.isEmpty) return;
    if (_hasCommissionFor(employeeId: tailorId, type: 'tailor')) return;

    final tailorName = tailorAssignment['employeeName']?.toString() ?? '';
    final employee = _employees.firstWhere(
      (e) => e['id']?.toString() == tailorId,
      orElse: () => <String, dynamic>{},
    );
    final commissionAmount =
        (tailorAssignment['commission_amount'] as num?)?.toDouble() ??
        (employee['tailorCut'] as num?)?.toDouble() ??
        0.0;
    if (commissionAmount <= 0) return;

    await _dbHelper.insert('commissions', {
      'orderId': widget.orderId,
      'employeeId': tailorId,
      'employeeName': tailorName,
      'amount': commissionAmount,
      'type': 'tailor',
      'status': 'pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _loadData();
  }

  Future<void> _calculateAllCommissions() async {
    for (final assignment in _assignments) {
      final role = assignment['role']?.toString();
      if (role == 'tailor' || role == 'sales') continue;

      double commission = 0;
      if (assignment['commission_amount'] != null &&
          (assignment['commission_amount'] as num) > 0) {
        commission = (assignment['commission_amount'] as num).toDouble();
      } else {
        final employee = _employees.firstWhere(
          (e) => e['id'] == assignment['employeeId'],
          orElse: () => <String, dynamic>{},
        );
        if (employee.isEmpty) continue;

        if (assignment['role'] == 'delivery') {
          final type = employee['delivery_commission_type'] ?? 'fixed';
          final value =
              (employee['delivery_commission_value'] as num?)?.toDouble() ?? 0;
          final deliveryFee =
              (_order!['delivery_fee'] as num?)?.toDouble() ?? 0;
          commission = type == 'percentage' ? deliveryFee * value / 100 : value;
        }
      }
      final assignmentEmployeeId = assignment['employeeId']?.toString() ?? '';
      final assignmentType = assignment['role']?.toString() ?? '';
      if (commission > 0 &&
          assignmentEmployeeId.isNotEmpty &&
          !_hasCommissionFor(
            employeeId: assignmentEmployeeId,
            type: assignmentType,
          )) {
        await _dbHelper.insert('commissions', {
          'orderId': widget.orderId,
          'employeeId': assignmentEmployeeId,
          'employeeName': assignment['employeeName'],
          'amount': commission,
          'type': assignmentType,
          'status': 'pending',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
  }

  Future<void> _calculateSalesCommissionIfNeeded() async {
    if (_order == null) return;
    final salesPersonId = _order!['salesPersonId'];
    if (salesPersonId == null) return;

    if (_hasCommissionFor(employeeId: salesPersonId, type: 'sales')) return;

    final salesPerson = await _dbHelper.queryById('users', salesPersonId);
    if (salesPerson == null) return;

    final commissionRate =
        (salesPerson['commissionRate'] as num?)?.toDouble() ?? 0;
    if (commissionRate <= 0) return;
    // Delegate to the recalculation method
    await _recalculateSalesCommission();
  }

  Future<void> _assignParticipant() async {
    final allEmployees = await _dbHelper.query('users');
    final activeEmployees = allEmployees.where((e) => e['status'] == 'active').toList();
    if (activeEmployees.isEmpty) {
      ErrorHandler.showError(context, 'No active employees available');
      return;
    }

    final selectedEmployee = await EmployeeSelectorDialog.showEmployeeSelector(
      context,
      employees: activeEmployees,
      title: 'Select Employee',
    );
    if (selectedEmployee == null) return;

    String employeeRole = selectedEmployee['role']?.toString() ?? 'other';
    String selectedRole = employeeRole;
    bool isCustomRole = false;
    final customRoleController = TextEditingController();
    double? deliveryFee;
    String commissionPreview = '';
    double tailorCutOverride = 0.0;
    bool overrideTailorCut = false;
    double customCommission = 0.0;
    bool addCustomCommission = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          void updateDeliveryPreview() {
            final fee = deliveryFee;
            setStateDialog(() {
              if (selectedRole == 'delivery' && fee != null && fee > 0) {
                final type = selectedEmployee['delivery_commission_type']?.toString() ?? 'fixed';
                final value = (selectedEmployee['delivery_commission_value'] as num?)?.toDouble() ?? 0.0;
                if (type == 'percentage') {
                  final amt = fee * value / 100;
                  commissionPreview = 'Commission: ${value.toStringAsFixed(0)}% of fee = ETB ${amt.toStringAsFixed(2)}';
                } else {
                  commissionPreview = 'Commission: Fixed ETB ${value.toStringAsFixed(2)}';
                }
              } else {
                commissionPreview = '';
              }
            });
          }

          return AlertDialog(
            title: const Text('Assign Role', style: TextStyle(color: Colors.black)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: isCustomRole ? 'custom' : selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      labelStyle: TextStyle(color: Colors.black54),
                    ),
                    style: const TextStyle(color: Colors.black),
                    items: [
                      DropdownMenuItem(value: employeeRole, child: Text(employeeRole)),
                      if (employeeRole != 'tailor') const DropdownMenuItem(value: 'tailor', child: Text('tailor')),
                      if (employeeRole != 'delivery') const DropdownMenuItem(value: 'delivery', child: Text('delivery')),
                      if (employeeRole != 'sales') const DropdownMenuItem(value: 'sales', child: Text('sales')),
                      const DropdownMenuItem(value: 'custom', child: Text('Custom...')),
                    ],
                    onChanged: (value) {
                      setStateDialog(() {
                        if (value == 'custom') {
                          isCustomRole = true;
                          selectedRole = '';
                        } else {
                          isCustomRole = false;
                          selectedRole = value!;
                        }
                      });
                    },
                  ),
                  if (isCustomRole)
                    TextField(
                      controller: customRoleController,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        labelText: 'Custom Role',
                        labelStyle: TextStyle(color: Colors.black54),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (selectedRole == 'delivery') ...[
                    TextField(
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        labelText: 'Delivery Fee (ETB) *',
                        labelStyle: TextStyle(color: Colors.black54),
                      ),
                      onChanged: (value) {
                        deliveryFee = double.tryParse(value);
                        updateDeliveryPreview();
                      },
                    ),
                    if (commissionPreview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(commissionPreview, style: const TextStyle(fontSize: 12, color: Colors.green)),
                      ),
                  ] else if (selectedRole == 'tailor') ...[
                    const Text('Tailor cut defaults to employee setting.', style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Override tailor cut?', style: TextStyle(color: Colors.black)),
                      value: overrideTailorCut,
                      onChanged: (v) => setStateDialog(() => overrideTailorCut = v ?? false),
                    ),
                    if (overrideTailorCut)
                      TextField(
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.black),
                        decoration: const InputDecoration(
                          labelText: 'Tailor Cut (ETB)',
                          labelStyle: TextStyle(color: Colors.black54),
                        ),
                        onChanged: (v) => tailorCutOverride = double.tryParse(v) ?? 0,
                      ),
                  ] else if (selectedRole != employeeRole && selectedRole != 'custom') ...[
                    CheckboxListTile(
                      title: const Text('Add custom commission?', style: TextStyle(color: Colors.black)),
                      value: addCustomCommission,
                      onChanged: (v) => setStateDialog(() => addCustomCommission = v ?? false),
                    ),
                    if (addCustomCommission)
                      TextField(
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.black),
                        decoration: const InputDecoration(
                          labelText: 'Commission Amount (ETB)',
                          labelStyle: TextStyle(color: Colors.black54),
                        ),
                        onChanged: (v) => customCommission = double.tryParse(v) ?? 0,
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign')),
            ],
          );
        },
      ),
    );

    if (result != true) return;

    final finalRole = isCustomRole ? customRoleController.text.trim() : selectedRole;
    if (finalRole.isEmpty) {
      ErrorHandler.showError(context, 'Role is required');
      return;
    }

    double commission = 0.0;
    final roleLower = finalRole.toLowerCase();

    // Handle delivery role
    if (roleLower == 'delivery') {
      if (deliveryFee == null || deliveryFee! <= 0) {
        ErrorHandler.showError(context, 'Valid delivery fee required');
        return;
      }
      // Update order delivery fee and total
      final updatedOrder = Map<String, dynamic>.from(_order!);
      updatedOrder['delivery_fee'] = deliveryFee;
      final subtotal = _calculateItemsSubtotal();
      final discount = _calculateDiscountAmount(deliveryFeeOverride: deliveryFee);
      updatedOrder['totalAmount'] = subtotal + deliveryFee! - discount;
      await _dbHelper.update('orders', updatedOrder, markSynced: true);
      _order = updatedOrder;

      final deliveryType = selectedEmployee['delivery_commission_type']?.toString() ?? 'fixed';
      final deliveryValue = (selectedEmployee['delivery_commission_value'] as num?)?.toDouble() ?? 0.0;
      if (deliveryType == 'percentage') {
        commission = deliveryFee! * deliveryValue / 100;
      } else {
        commission = deliveryValue;
      }
    }
    // Handle tailor role
    else if (roleLower == 'tailor') {
      if (overrideTailorCut) {
        commission = tailorCutOverride;
      } else {
        commission = (selectedEmployee['tailorCut'] as num?)?.toDouble() ?? 0.0;
      }
      if (_order!['status'] == 'pending') {
        final updatedOrder = Map<String, dynamic>.from(_order!);
        updatedOrder['status'] = 'processing';
        await _dbHelper.update('orders', updatedOrder, markSynced: true);
        _order = updatedOrder;
      }
    }
    // Other roles (including custom)
    else {
      if (addCustomCommission) {
        commission = customCommission;
      }
    }

    final assignmentData = {
      'orderId': widget.orderId,
      'employeeId': selectedEmployee['id'],
      'employeeName': selectedEmployee['name'],
      'employeePhone':
          selectedEmployee['phone'] ??
          selectedEmployee['contact'] ??
          selectedEmployee['mobile'],
      'role': finalRole,
      'assignedAt': DateTime.now().millisecondsSinceEpoch,
      'commission_amount': commission,
    };
    await _dbHelper.insert('order_assignments', assignmentData);
    await _recalculateSalesCommission(); // Recalculate sales commission after assignment changes
    await _loadData();
    ErrorHandler.showSuccess(context, 'Assigned $finalRole');
  }

  Future<double?> _showCustomCommissionDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text(
            'Custom Commission',
            style: TextStyle(color: Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter a custom commission amount (optional). Leave blank to use default.',
                style: TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (ETB)',
                  labelStyle: TextStyle(color: Colors.black54),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip', style: TextStyle(color: Colors.blue)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true && controller.text.isNotEmpty) {
      return double.tryParse(controller.text) ?? 0;
    }
    return null;
  }

  Future<void> _editCommission(Map<String, dynamic> assignment) async {
    final controller = TextEditingController(
      text: (assignment['commission_amount'] ?? 0).toString(),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text(
            'Custom Commission',
            style: TextStyle(color: Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter a custom commission amount. Leave blank to use default.',
                style: TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (ETB)',
                  labelStyle: TextStyle(color: Colors.black54),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final updatedAssignment = Map<String, dynamic>.from(assignment);
      updatedAssignment['commission_amount'] =
          double.tryParse(controller.text) ?? 0;
      await _dbHelper.update('order_assignments', updatedAssignment);
      await _recalculateSalesCommission(); // Recalculate sales commission after assignment changes
      await _loadData();
    }
  }

  Widget _buildAssignmentTile(Map<String, dynamic> assignment) {
    final role = assignment['role'] as String? ?? '?';
    final employeeName = assignment['employeeName'] as String? ?? 'Unknown';
    final commission = (assignment['commission_amount'] as num?)?.toDouble() ?? 0.0;
    final assignmentId = assignment['id']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryRed.withOpacity(0.1),
            child: Text(
              role.isNotEmpty ? role.substring(0, 1).toUpperCase() : '?',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryRed),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employeeName,
                  style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 2),
                Text(
                  role,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          if (commission > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'ETB ${commission.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.info),
              ),
            ),
          if (_isAdminOrManager) ...[
              IconButton(
                icon: const Icon(
                  Icons.monetization_on,
                  size: 18,
                  color: Colors.black,
                ),
                onPressed: () => _editCommission(assignment),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                onPressed: () => _deleteAssignment(assignmentId, employeeName, role),
                tooltip: 'Remove assignment',
              ),
            ],
        ],
      ),
    );
  }

    Future<void> _deleteAssignment(String assignmentId, String employeeName, String role) async {
      if (assignmentId.isEmpty) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove Assignment'),
          content: Text('Remove $employeeName from $role?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm == true) {
        await _dbHelper.delete('order_assignments', assignmentId);
        await _loadData();
        await _recalculateSalesCommission(); // Recalculate sales commission after assignment changes
        ErrorHandler.showSuccess(context, 'Assignment removed');
      }
    }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }

  Color _paymentColor(String? type) {
    return type == 'refund' ? AppColors.error : AppColors.success;
  }

  Future<void> _showCancelDialog() async {
    if (_order?['status']?.toString() == 'delivered') {
      ErrorHandler.showError(
        context,
        'Delivered orders cannot be cancelled. Use refund instead.',
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Cancel Order'),
          content: const Text(
            'Are you sure you want to cancel this order?\n\n'
            '• Payments will NOT be automatically refunded.\n'
            '• Stock will NOT be restored.\n'
            '• Sales commissions will be voided.\n'
            '• Tailor commissions remain (work done).\n'
            '• Delivery commissions remain if delivery happened.\n\n'
            'To refund a payment, use "Record Payment" with type "Refund".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Yes, Cancel',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await _updateStatus('cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final discountAmount = _calculateDiscountAmount();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _order == null ? null : _printLabel,
            tooltip: 'Print Label',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _order == null ? null : _shareLabel,
            tooltip: 'Share Label',
          ),
        ],
      ),
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
            : _order == null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Order not found',
                      style: TextStyle(color: AppColors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order ID: ${_order!['id']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Customer: ${_order!['customerName'] ?? 'Unknown'}',
                            ),
                            Text(
                              'Branch: ${_branchName ?? 'No branch assigned'}',
                            ),
                            Text('Date: ${_formatDate(_order!['createdAt'])}'),
                            Text('Status: ${_order!['status']}'),
                            if (_order!['delivery_fee'] != null)
                              Text(
                                'Delivery Fee: ETB ${((_order!['delivery_fee'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                              ),
                            if (discountAmount > 0)
                              Text(
                                'Discount: -ETB ${discountAmount.toStringAsFixed(2)} (${_order!['discount_type']})',
                              ),
                            Text(
                              'Total: ETB ${((_order!['totalAmount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                            ),
                            if (_order!['tracking_number'] != null)
                              Text(
                                'Tracking: ${_order!['tracking_number']} (${_order!['courier_name'] ?? 'courier'})',
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._items.map(
                      (item) => Card(
                        child: ListTile(
                          title: Text(item['description'] ?? 'Item'),
                          subtitle: Text(
                            'Qty: ${item['quantity']} @ ETB ${((item['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                          ),
                          trailing: Text(
                            'ETB ${((((item['quantity'] as num?)?.toDouble() ?? 0) * ((item['price'] as num?)?.toDouble() ?? 0))).toStringAsFixed(2)}',
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Card(
                      color: AppColors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Status History',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_statusLogs.isEmpty)
                              const Text(
                                'No status updates recorded yet.',
                                style: TextStyle(color: Colors.black54),
                              )
                            else
                              ..._statusLogs.map(
                                (log) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.timeline,
                                    color: AppColors.primaryRed,
                                  ),
                                  title: Text(
                                    (log['status'] ?? '').toString(),
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                  subtitle: Text(
                                    '${_formatDate((log['changedAt'] as num?)?.toInt() ?? 0)} by ${log['changedBy'] ?? 'Unknown'}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Card(
                      color: AppColors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.group, size: 20, color: AppColors.primaryRed),
                                SizedBox(width: 8),
                                Text(
                                  'Assignments',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_assignments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No assignments yet', style: TextStyle(color: Colors.black54)),
                              )
                            else
                              ..._assignments.map((a) => _buildAssignmentTile(a)),
                            const SizedBox(height: 12),
                            if (_isAdminOrManager)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _assignParticipant,
                                  icon: const Icon(Icons.person_add, size: 18),
                                  label: const Text('Assign Participant'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryRed,
                                    side: BorderSide(color: AppColors.primaryRed),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Card(
                      color: AppColors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Payment History',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_paymentsLoading)
                              const Center(child: CircularProgressIndicator())
                            else if (_payments.isEmpty)
                              const Text(
                                'No payments recorded',
                                style: TextStyle(color: Colors.black),
                              )
                            else
                              ..._payments.map(
                                (payment) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.payment,
                                    color: _paymentColor(
                                      payment['type'] as String?,
                                    ),
                                  ),
                                  title: Text(
                                    '${payment['type']} - ${DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch((payment['date'] as num?)?.toInt() ?? 0))}',
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                  subtitle: Text(
                                    'Method: ${(payment['method'] ?? payment['receivedBy'] ?? 'recorded').toString()}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                  trailing: Text(
                                    'ETB ${((payment['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: _paymentColor(
                                        payment['type'] as String?,
                                      ),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => RecordPaymentScreen(
                                        orderId: widget.orderId,
                                      ),
                                    ),
                                  );
                                  await _loadData();
                                },
                                child: const Text('Record Payment'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (_isAdminOrManager &&
                        _order!['status'] != 'cancelled' &&
                        _order!['status'] != 'completed')
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _order!['status'] == 'pending'
                                  ? () => _updateStatus('processing')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.info,
                                foregroundColor: AppColors.white,
                              ),
                              child: const Text('Mark Processing'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _order!['status'] == 'processing'
                                  ? () => _updateStatus('out_for_delivery')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.warning,
                                foregroundColor: AppColors.white,
                              ),
                              child: const Text('Out for Delivery'),
                            ),
                          ),
                        ],
                      ),
                    if (_isAdminOrManager &&
                        _order!['status'] == 'out_for_delivery')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _updateStatus('delivered'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: AppColors.white,
                            ),
                            child: const Text('Mark Delivered'),
                          ),
                        ),
                      ),
                    if (_isAdminOrManager && _order!['status'] != 'cancelled')
                      Center(
                        child: TextButton(
                          onPressed: _showCancelDialog,
                          child: const Text(
                            'Cancel Order',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
