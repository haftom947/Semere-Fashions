import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
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
  bool _isLoading = true;
  bool _paymentsLoading = false;
  bool _isAdminOrManager = true;

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
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final orderData = await _dbHelper.queryById('orders', widget.orderId);
      _order = orderData != null ? Map<String, dynamic>.from(orderData) : null;

      if (_order != null) {
        if (_order!['items'] is String) {
          _items = List<Map<String, dynamic>>.from(
            jsonDecode(_order!['items']),
          );
        } else {
          _items = List<Map<String, dynamic>>.from(
            _order!['items'] as List? ?? [],
          );
        }

        final allAssignments = await _dbHelper.query('order_assignments');
        _assignments = allAssignments
            .where((a) => a['orderId'] == widget.orderId)
            .map((a) => Map<String, dynamic>.from(a))
            .toList();

        final allEmployees = await _dbHelper.query('users');
        _employees = allEmployees
            .where((e) => e['status'] == 'active')
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final branchId = _order!['branchId'] as String?;
        if (branchId != null && branchId.isNotEmpty) {
          final branch = await _dbHelper.queryById('branches', branchId);
          _branchName = branch?['name'] ?? branchId;
        } else {
          _branchName = null;
        }

        final allCommissions = await _dbHelper.query('commissions');
        _commissions = allCommissions
            .where((c) => c['orderId'] == widget.orderId)
            .map((c) => Map<String, dynamic>.from(c))
            .toList();

        if (mounted) {
          setState(() => _paymentsLoading = true);
        }
        try {
          final allPayments = await _dbHelper.query('payment_transaction');
          final mutablePayments = List<Map<String, dynamic>>.from(allPayments);
          _payments = mutablePayments
              .where((p) => p['orderId'] == widget.orderId)
              .map((p) => Map<String, dynamic>.from(p)) // ← mutable copy
              .toList();
          for (final payment in _payments) {
            final breakdowns = await _dbHelper.queryWhere(
              'payment_breakdown',
              'payment_transaction_id = ?',
              [payment['id']],
            );
            if (breakdowns.isNotEmpty) {
              payment['method'] = breakdowns.first['method'];
            }
          }
          print('Payments for order ${widget.orderId}: $_payments');
        } catch (e) {
          print('Payment table error: $e');
          _payments = [];
        } finally {
          if (mounted) {
            setState(() => _paymentsLoading = false);
          }
        }
      }
    } catch (e, stack) {
      print('Error loading order details: $e');
      print(stack);
      if (mounted) {
        ErrorHandler.showError(
          context,
          'Failed to load order details: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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

  Future<bool> _deductStockIfNeeded(Map<String, dynamic> updatedOrder) async {
    if (updatedOrder['stock_deducted'] == 1) return true;

    double totalCogs = 0.0;   // <-- add this variable

    for (final item in _items) {
      final productId = item['productId'];
      if (productId == null) continue;

      final product = await _dbHelper.queryById('products', productId);
      if (product == null) {
        if (mounted) ErrorHandler.showError(context, 'Product not found for ${item['description']}');
        return false;
      }

      final currentStock = (product['stock'] as num?)?.toInt() ?? 0;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      if (currentStock < quantity) {
        if (mounted) ErrorHandler.showError(context, 'Not enough stock for ${item['description']}');
        return false;
      }

      final updatedProduct = Map<String, dynamic>.from(product);
      updatedProduct['stock'] = currentStock - quantity;
      await _dbHelper.update('products', updatedProduct);

      // Add to COGS
      final productCost = (product['costPrice'] as num?)?.toDouble() ?? 0.0;
      totalCogs += productCost * quantity;   // <-- accumulate cost
    }

    updatedOrder['stock_deducted'] = 1;
    updatedOrder['cogs'] = totalCogs;   // <-- store in order
    return true;
  }
  
  Future<void> _restoreStockIfNeeded(Map<String, dynamic> updatedOrder) async {
    final stockDeducted = updatedOrder['stock_deducted'] == 1;
    if (!stockDeducted) return;

    for (final item in _items) {
      final productId = item['productId'];
      if (productId == null) continue;

      final product = await _dbHelper.queryById('products', productId);
      if (product == null) continue;

      final updatedProduct = Map<String, dynamic>.from(product);
      updatedProduct['stock'] =
          ((updatedProduct['stock'] as num?)?.toInt() ?? 0) +
          ((item['quantity'] as num?)?.toInt() ?? 0);
      await _dbHelper.update('products', updatedProduct);
    }

    updatedOrder['stock_deducted'] = 0;
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_order == null) return;

    setState(() => _isLoading = true);
    try {
      final updatedOrder = Map<String, dynamic>.from(_order!);
      final previousStatus = _order!['status'];
      updatedOrder['status'] = newStatus;

      if (newStatus == 'delivered') {
        final deducted = await _deductStockIfNeeded(updatedOrder);
        if (!deducted) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      if (newStatus == 'cancelled') {
        await _reverseOrderEffects(
          restoreStock:
              previousStatus == 'delivered' ||
              updatedOrder['stock_deducted'] == 1,
          updatedOrder: updatedOrder,
        );
      }

      await _dbHelper.update('orders', updatedOrder);
      _order = updatedOrder;

      if (newStatus == 'out_for_delivery') {
        await _calculateSalesCommissionIfNeeded();
      }

      if (newStatus == 'delivered') {
        await _calculateAllCommissions();
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

  Future<void> _reverseOrderEffects({
    required bool restoreStock,
    required Map<String, dynamic> updatedOrder,
  }) async {
    for (final comm in _commissions) {
      if (comm['status'] == 'pending') {
        final updatedCommission = Map<String, dynamic>.from(comm);
        updatedCommission['status'] = 'voided';
        await _dbHelper.update('commissions', updatedCommission);
      }
    }

    await _dbHelper.clearPaymentsForOrder(widget.orderId);
    updatedOrder['paid_amount'] = 0.0;

    if (restoreStock) {
      await _restoreStockIfNeeded(updatedOrder);
      if (mounted) {
        ErrorHandler.showSuccess(context, 'Order cancelled. Stock restored.');
      }
    } else if (mounted) {
      ErrorHandler.showSuccess(context, 'Order cancelled.');
    }
  }

  bool _hasCommissionFor({
    required String employeeId,
    required String type,
  }) {
    return _commissions.any(
      (comm) =>
          comm['orderId'] == widget.orderId &&
          comm['employeeId']?.toString() == employeeId &&
          comm['type']?.toString() == type &&
          comm['status']?.toString() != 'voided',
    );
  }

  Future<void> _calculateAllCommissions() async {
    for (final assignment in _assignments) {
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
        } else if (assignment['role'] == 'tailor') {
          commission = (employee['tailorCut'] as num?)?.toDouble() ?? 0;
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
          'id': '${assignment['id']}_${DateTime.now().millisecondsSinceEpoch}',
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

    final commissionRate = (salesPerson['commissionRate'] as num?)?.toDouble() ?? 0;
    if (commissionRate <= 0) return;

    final totalAmount = (_order!['totalAmount'] as num?)?.toDouble() ?? 0;
    final commissionAmount = totalAmount * commissionRate / 100;
    await _dbHelper.insert('commissions', {
      'id': '${salesPersonId}_${DateTime.now().millisecondsSinceEpoch}',
      'orderId': widget.orderId,
      'employeeId': salesPersonId,
      'employeeName': salesPerson['name'] ?? '',
      'amount': commissionAmount,
      'type': 'sales',
      'status': 'pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _loadData();
  }

  Future<void> _assignRole(String role) async {
    final availableEmployees = _employees
        .where((e) => e['role'] == role && e['status'] == 'active')
        .toList();
    if (availableEmployees.isEmpty) {
      ErrorHandler.showError(context, 'No active $role available');
      return;
    }

    final selected = await EmployeeSelectorDialog.showEmployeeSelector(
      context,
      employees: availableEmployees,
      title: 'Select $role',
    );

    if (selected == null) return;

    double? deliveryFee;
    if (role == 'delivery') {
      deliveryFee = await _showDeliveryFeeDialog();
      if (deliveryFee == null) return;
    }

    final assignmentData = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'orderId': widget.orderId,
      'employeeId': selected['id'],
      'employeeName': selected['name'],
      'role': role,
      'assignedAt': DateTime.now().millisecondsSinceEpoch,
      'commission_amount': 0, // will be calculated later for delivery
    };
    await _dbHelper.insert('order_assignments', assignmentData);

    if (role == 'delivery' && deliveryFee != null) {
      await _updateDeliveryFee(deliveryFee);
    }

    // Auto‑mark processing when tailor assigned and order is pending
    if (role == 'tailor' && _order!['status'] == 'pending') {
      final updatedOrder = Map<String, dynamic>.from(_order!);
      updatedOrder['status'] = 'processing';
      await _dbHelper.update('orders', updatedOrder);
      _order = updatedOrder;
      _syncService.emitDataChanged();
    }

    await _loadData();
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
      await _loadData();
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Cancel Order'),
          content: const Text(
            'Are you sure you want to cancel this order? This will void commissions, reverse payments, and restore stock if it was deducted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Yes',
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
                              'Assignments',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._assignments.map(
                              (a) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${a['role']}: ${a['employeeName']}',
                                        style: const TextStyle(
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                    if (a['commission_amount'] != null &&
                                        (a['commission_amount'] as num) > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: Chip(
                                          label: Text(
                                            'ETB ${(a['commission_amount'] as num).toStringAsFixed(0)}',
                                          ),
                                          backgroundColor: AppColors.info,
                                        ),
                                      ),
                                    if (_isAdminOrManager)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.monetization_on,
                                          size: 16,
                                          color: Colors.black,
                                        ),
                                        onPressed: () => _editCommission(a),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (_assignments.isEmpty)
                              const Text(
                                'No assignments yet.',
                                style: TextStyle(color: Colors.black),
                              ),
                            if (_isAdminOrManager) ...[
                              Center(
                                child: TextButton.icon(
                                  onPressed: () => _assignRole('tailor'),
                                  icon: const Icon(
                                    Icons.person,
                                    color: Colors.blue,
                                  ),
                                  label: const Text(
                                    'Assign Tailor',
                                    style: TextStyle(color: Colors.blue),
                                  ),
                                ),
                              ),
                              Center(
                                child: TextButton.icon(
                                  onPressed: () => _assignRole('delivery'),
                                  icon: const Icon(
                                    Icons.delivery_dining,
                                    color: Colors.blue,
                                  ),
                                  label: const Text(
                                    'Assign Delivery',
                                    style: TextStyle(color: Colors.blue),
                                  ),
                                ),
                              ),
                            ],
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
