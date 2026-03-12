import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/error_handler.dart';
import 'employee_selector_dialog.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailsScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _commissions = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  bool _isAdminOrManager = true; // You can implement actual role check

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncService.dataChangedStream.listen((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _order = await _dbHelper.queryById('orders', widget.orderId);
    if (_order != null) {
      if (_order!['items'] is String) {
        _items = jsonDecode(_order!['items']).cast<Map<String, dynamic>>();
      } else {
        _items = (_order!['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      }
      var allAssignments = await _dbHelper.query('order_assignments');
      _assignments = allAssignments.where((a) => a['orderId'] == widget.orderId).toList();
      var allEmployees = await _dbHelper.query('users');
      _employees = allEmployees.where((e) => e['status'] == 'active').toList();
      var allCommissions = await _dbHelper.query('commissions');
      _commissions = allCommissions.where((c) => c['orderId'] == widget.orderId).toList();
      var allPayments = await _dbHelper.query('payment_transaction'); // assuming you have a payments table
      _payments = allPayments.where((p) => p['orderId'] == widget.orderId).toList();
      var allProducts = await _dbHelper.query('products');
      _products = allProducts;
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_order == null) return;
    setState(() => _isLoading = true);
    _order!['status'] = newStatus;
    await _dbHelper.update('orders', _order!);

    if (newStatus == 'delivered') {
      await _calculateAllCommissions();
    } else if (newStatus == 'cancelled') {
      await _reverseOrderEffects();
    }

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
      _syncService.syncAll();
    }
    _loadData();
  }

  Future<void> _reverseOrderEffects() async {
    // 1. Void any pending commissions
    for (var comm in _commissions) {
      if (comm['status'] == 'pending') {
        comm['status'] = 'voided';
        await _dbHelper.update('commissions', comm);
      }
    }

    // 2. Reverse payments (if any)
    if (_payments.isNotEmpty) {
      // Create refund transactions (optional) – for now, just delete or mark as refunded
      for (var payment in _payments) {
        // Option: create a refund record or just mark as refunded
        // For simplicity, we'll delete the payment record (but you might want to keep history)
        await _dbHelper.delete('payment_transaction', payment['id']);
      }
      if (mounted) ErrorHandler.showSuccess(context, 'Payments reversed');
    }

    // 3. Restore stock for product items
    for (var item in _items) {
      if (item['productId'] != null) {
        var product = _products.firstWhere((p) => p['id'] == item['productId'], orElse: () => <String, dynamic>{});
        if (product.isNotEmpty) {
          product['stock'] = (product['stock'] ?? 0) + item['quantity'];
          await _dbHelper.update('products', product);
        }
      }
    }

    if (mounted) ErrorHandler.showSuccess(context, 'Order cancelled. Stock restored.');
  }

  Future<void> _calculateAllCommissions() async {
    for (var assignment in _assignments) {
      double commission = 0;
      if (assignment['commission_amount'] != null && (assignment['commission_amount'] as num) > 0) {
        commission = (assignment['commission_amount'] as num).toDouble();
      } else {
        var employee = _employees.firstWhere((e) => e['id'] == assignment['employeeId'], orElse: () => <String, dynamic>{});
        if (employee.isEmpty) continue;

        if (assignment['role'] == 'delivery') {
          String type = employee['delivery_commission_type'] ?? 'fixed';
          double value = (employee['delivery_commission_value'] as num?)?.toDouble() ?? 0;
          double deliveryFee = (_order!['delivery_fee'] as num?)?.toDouble() ?? 0;
          if (type == 'percentage') {
            commission = deliveryFee * value / 100;
          } else {
            commission = value;
          }
        } else if (assignment['role'] == 'tailor') {
          commission = (employee['tailorCut'] as num?)?.toDouble() ?? 0;
        } else if (assignment['role'] == 'sales') {
          // Sales commission based on profit – not yet implemented
        }
      }

      if (commission > 0) {
        await _dbHelper.insert('commissions', {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'orderId': widget.orderId,
          'employeeId': assignment['employeeId'],
          'employeeName': assignment['employeeName'],
          'amount': commission,
          'type': assignment['role'],
          'status': 'pending',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
  }

  Future<void> _assignDelivery() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EmployeeSelectorDialog(
        employees: _employees.where((e) => e['role'] == 'delivery').toList(),
        title: 'Select Delivery Person',
      ),
    );
    if (selected != null) {
      double? customAmount = await _showCustomCommissionDialog();
      var existing = _assignments.firstWhere(
        (a) => a['role'] == 'delivery',
        orElse: () => <String, dynamic>{},
      );
      
      Map<String, dynamic> assignmentData = {
        'orderId': widget.orderId,
        'employeeId': selected['id'],
        'employeeName': selected['name'],
        'role': 'delivery',
        'assignedAt': DateTime.now().millisecondsSinceEpoch,
        'commission_amount': customAmount ?? 0,
      };

      if (existing.isNotEmpty) {
        assignmentData['id'] = existing['id'];
        await _dbHelper.update('order_assignments', assignmentData);
      } else {
        assignmentData['id'] = DateTime.now().millisecondsSinceEpoch.toString();
        await _dbHelper.insert('order_assignments', assignmentData);
      }
      _loadData();
    }
  }

  Future<double?> _showCustomCommissionDialog() async {
    final controller = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom Commission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a custom commission amount for this assignment (optional). Leave blank to use default.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (ETB)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true && controller.text.isNotEmpty) {
      return double.tryParse(controller.text) ?? 0;
    }
    return null;
  }

  Future<void> _editCommission(Map<String, dynamic> assignment) async {
    final controller = TextEditingController(text: (assignment['commission_amount'] ?? 0).toString());
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom Commission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a custom commission amount for this assignment. Leave blank to use default.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (ETB)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      double amount = double.tryParse(controller.text) ?? 0;
      assignment['commission_amount'] = amount;
      await _dbHelper.update('order_assignments', assignment);
      _loadData();
    }
  }

  double _calculateDiscountAmount() {
    if (_order == null) return 0;
    double subtotal = (_order!['totalAmount'] as num?)?.toDouble() ?? 0;
    double deliveryFee = (_order!['delivery_fee'] as num?)?.toDouble() ?? 0;
    double discountValue = (_order!['discount_value'] as num?)?.toDouble() ?? 0;
    String discountType = _order!['discount_type'] ?? 'none';
    
    if (discountType == 'percentage') {
      return (subtotal + deliveryFee) * discountValue / 100;
    } else if (discountType == 'fixed') {
      return discountValue;
    }
    return 0;
  }

  String _formatDate(int timestamp) {
    if (timestamp == null) return 'Unknown';
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }

  Future<void> _showCancelDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order'),
        content: const Text('Are you sure you want to cancel this order? This will void commissions, reverse payments, and restore stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _updateStatus('cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    double discountAmount = _calculateDiscountAmount();
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
                ? const Center(child: Text('Order not found', style: TextStyle(color: AppColors.white)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Order header
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Order ID: ${_order!['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text('Customer: ${_order!['customerName'] ?? 'Unknown'}'),
                                Text('Date: ${_formatDate(_order!['createdAt'])}'),
                                Text('Status: ${_order!['status']}'),
                                if (_order!['delivery_fee'] != null)
                                  Text('Delivery Fee: ETB ${(_order!['delivery_fee'] as num).toStringAsFixed(2)}'),
                                if (discountAmount > 0)
                                  Text('Discount: -ETB ${discountAmount.toStringAsFixed(2)} (${_order!['discount_type']})'),
                                Text('Total: ETB ${(_order!['totalAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Items list
                        const Text('Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
                        const SizedBox(height: 8),
                        ..._items.map((item) => Card(
                          child: ListTile(
                            title: Text(item['description'] ?? 'Item'),
                            subtitle: Text('Qty: ${item['quantity']} @ ETB ${(item['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
                            trailing: Text('ETB ${((item['quantity'] as num?)?.toDouble() ?? 0) * ((item['price'] as num?)?.toDouble() ?? 0)}'),
                          ),
                        )),

                        const SizedBox(height: 16),

                        // Assignments section
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Assignments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                ..._assignments.map((a) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text('${a['role']}: ${a['employeeName']}'),
                                      ),
                                      if (a['commission_amount'] != null && (a['commission_amount'] as num) > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: Chip(
                                            label: Text('ETB ${(a['commission_amount'] as num).toStringAsFixed(0)}'),
                                            backgroundColor: AppColors.info,
                                          ),
                                        ),
                                      if (_isAdminOrManager)
                                        IconButton(
                                          icon: const Icon(Icons.monetization_on, size: 16),
                                          onPressed: () => _editCommission(a),
                                        ),
                                      if (_isAdminOrManager && a['role'] == 'delivery')
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 16),
                                          onPressed: () => _assignDelivery(),
                                        ),
                                    ],
                                  ),
                                )),
                                if (_assignments.isEmpty)
                                  const Text('No assignments yet.'),
                                if (_isAdminOrManager)
                                  Center(
                                    child: TextButton.icon(
                                      onPressed: _assignDelivery,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Assign Delivery'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Status update buttons
                        if (_isAdminOrManager && _order!['status'] != 'cancelled' && _order!['status'] != 'completed')
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _order!['status'] == 'pending' ? () => _updateStatus('processing') : null,
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
                                  onPressed: _order!['status'] == 'processing' ? () => _updateStatus('out_for_delivery') : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.warning,
                                    foregroundColor: AppColors.white,
                                  ),
                                  child: const Text('Out for Delivery'),
                                ),
                              ),
                            ],
                          ),
                        if (_isAdminOrManager && _order!['status'] == 'out_for_delivery')
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
                              child: const Text('Cancel Order', style: TextStyle(color: AppColors.error)),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}