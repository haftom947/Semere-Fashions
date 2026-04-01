import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/error_handler.dart';
import '../widgets/customer_selector.dart';
import '../widgets/product_selector.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({Key? key}) : super(key: key);

  @override
  _CreateOrderScreenState createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _trackingController = TextEditingController();
  final TextEditingController _courierController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  String? _customerId;
  String _customerName = '';
  List<Map<String, dynamic>> _items = [];
  double _total = 0.0;
  String _discountType = 'none';
  double _discountValue = 0.0;
  double _grandTotal = 0.0;
  double _paidAmount = 0.0;
  String _paymentMethod = 'cash';
  final List<String> _paymentMethods = ['cash', 'card', 'transfer'];
  bool _recordPayment = false;
  bool _isLoading = false;
  String? _currentUserId;
  String? _currentUserRole;
  String? _currentBranchId;
  String? _selectedBranchId;
  String? _branchCurrency;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _products = [];      // <-- missing declaration added
  bool _showProductSelector = true;               // <-- added
  bool _isAdminOrManager = false;
  List<Map<String, dynamic>> _salesPeople = [];
  String? _salesPersonId;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _loadBranches();
    _loadProducts();           // <-- call to load products
    _loadSalesPeople();
  }

  @override
  void dispose() {
    _trackingController.dispose();
    _courierController.dispose();
    _discountController.dispose();
    _paidAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    var products = await _dbHelper.query('products');
    setState(() {
      _products = products.map((p) => Map<String, dynamic>.from(p)).toList();
    });
  }

  Future<void> _loadBranches() async {
    var branches = await _dbHelper.query('branches');
    if (!mounted) return;
    setState(() {
      _branches = branches.map((b) => Map<String, dynamic>.from(b)).toList();
    });
  }

  Future<void> _getCurrentUser() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      var userData = await _dbHelper.queryById('users', user.uid);
      if (userData != null) {
        _currentUserRole = userData['role'];
        _currentBranchId = userData['branchId'];
        _isAdminOrManager = (_currentUserRole == 'admin' || _currentUserRole == 'manager');
        _selectedBranchId = _currentUserRole == 'admin' ? null : _currentBranchId;
        if (_currentBranchId != null) {
          var branch = await _dbHelper.queryById('branches', _currentBranchId!);
          setState(() {
            _branchCurrency = branch?['currency'] ?? 'ETB';
          });
        }
      }
    }
  }

  Future<void> _loadSalesPeople() async {
    var employees = await _dbHelper.query('users');
    setState(() {
      _salesPeople = employees
          .where((e) => e['role'] == 'sales' && e['status'] == 'active')
          .toList();
    });
  }

  void _addItem() {
    setState(() {
      _items.add({
        'description': '',
        'quantity': 1,
        'price': 0.0,
        'productId': null,
      });
    });
  }

  void _addProduct(Map<String, dynamic> product) async {
    int index = _products.indexWhere((p) => p['id'] == product['id']);
    if (index == -1) {
      ErrorHandler.showError(context, 'Product not found');
      return;
    }

    int stock = _products[index]['stock'] ?? 0;
    if (stock < 1) {
      ErrorHandler.showError(context, 'Product out of stock');
      return;
    }

    var productCopy = Map<String, dynamic>.from(_products[index]);
    productCopy['stock'] = stock - 1;
    await _dbHelper.update('products', productCopy);

    setState(() {
      _products[index] = productCopy;
      _items.add({
        'description': productCopy['name'],
        'quantity': 1,
        'price': (productCopy['sellingPrice'] as num?)?.toDouble() ?? 0.0,
        'productId': productCopy['id'],
      });
      _calculateTotal();
      _showProductSelector = false; // collapse the product selector
    });
    ErrorHandler.showSuccess(context, '${productCopy['name']} added to order');
  }

  void _showProductSelectorAgain() {
    setState(() {
      _showProductSelector = true;
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateTotal();
    });
  }

  void _updateItem(int index, String field, dynamic value) {
    setState(() {
      _items[index][field] = value;
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    _total = 0.0;
    for (var item in _items) {
      _total += (item['quantity'] as int) * (item['price'] as double);
    }
    _calculateGrandTotal();
  }

  void _updateDiscountType(String? value) {
    setState(() {
      _discountType = value ?? 'none';
      _discountController.clear();
      _discountValue = 0.0;
      _calculateGrandTotal();
    });
  }

  void _updateDiscountValue(String value) {
    setState(() {
      _discountValue = double.tryParse(value) ?? 0.0;
      _calculateGrandTotal();
    });
  }

  void _calculateGrandTotal() {
    double subtotal = _total;
    if (_discountType == 'percentage') {
      _grandTotal = subtotal - (subtotal * _discountValue / 100);
    } else if (_discountType == 'fixed') {
      _grandTotal = subtotal - _discountValue;
    } else {
      _grandTotal = subtotal;
    }
    if (_grandTotal < 0) _grandTotal = 0;
  }

  Future<void> _submitOrder() async {
    if (_customerId == null) {
      ErrorHandler.showError(context, 'Please select a customer');
      return;
    }
    final role = _currentUserRole ?? '';
    final orderBranchId = role == 'admin' ? _selectedBranchId : _currentBranchId;
    if (orderBranchId == null || orderBranchId.isEmpty) {
      ErrorHandler.showError(context, 'Please select a branch');
      return;
    }
    if (_items.isEmpty) {
      ErrorHandler.showError(context, 'Add at least one item');
      return;
    }
    if (_currentUserId == null) {
      ErrorHandler.showError(context, 'User not authenticated');
      return;
    }
    if (_recordPayment) {
      final paid = double.tryParse(_paidAmountController.text) ?? 0.0;
      if (paid <= 0) {
        ErrorHandler.showError(context, 'Enter a valid paid amount');
        return;
      }
      _paidAmount = paid;
    } else {
      _paidAmount = 0.0;
    }

    setState(() => _isLoading = true);
    try {
      String orderId = DateTime.now().millisecondsSinceEpoch.toString();

      Map<String, dynamic> orderData = {
        'id': orderId,
        'customerId': _customerId,
        'customerName': _customerName,
        'items': jsonEncode(_items),
        'totalAmount': _grandTotal,
        'delivery_fee': 0,
        'discount_type': _discountType == 'none' ? null : _discountType,
        'discount_value': _discountType == 'none' ? 0 : _discountValue,
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdBy': _currentUserId,
        'branchId': orderBranchId,
        'currency': _branchCurrency ?? 'ETB',
        'tracking_number': _trackingController.text.trim().isEmpty
            ? null
            : _trackingController.text.trim(),
        'courier_name': _courierController.text.trim().isEmpty
            ? null
            : _courierController.text.trim(),
        'salesPersonId': _salesPersonId,
        'stock_deducted': 0,
        'paid_amount': 0.0,
      };

      await _dbHelper.insert('orders', orderData);
      _syncService.emitDataChanged();

      if (_recordPayment && _paidAmount > 0) {
        await _dbHelper.addPayment(
          orderId,
          _paidAmount,
          _paymentMethod,
          branchId: orderBranchId,
          receivedBy: _currentUserId,
        );
      }

      if (mounted) {
        _syncService.triggerBackgroundSync();
        ErrorHandler.showSuccess(context, 'Order created successfully!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Order'),
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
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    CustomerSelector(
                      onCustomerSelected: (id, name) {
                        setState(() {
                          _customerId = id;
                          _customerName = name;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    if (_currentUserRole == 'admin') ...[
                      DropdownButtonFormField<String>(
                        value: _selectedBranchId,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Branch *',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        hint: const Text(
                          'Select branch',
                          style: TextStyle(color: Colors.white70),
                        ),
                        items: _branches
                            .where((branch) => (branch['id'] as String?)?.isNotEmpty ?? false)
                            .map(
                              (branch) => DropdownMenuItem<String>(
                                value: branch['id'].toString(),
                                child: Text(
                                  branch['name'] ?? branch['id'] ?? 'Branch',
                                  style: const TextStyle(color: AppColors.white),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) async {
                          setState(() {
                            _selectedBranchId = value;
                          });
                          if (value != null) {
                            final branch = await _dbHelper.queryById('branches', value);
                            if (!mounted) return;
                            setState(() {
                              _branchCurrency = branch?['currency'] ?? 'ETB';
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ] else if (_currentBranchId != null) ...[
                      FutureBuilder<Map<String, dynamic>?>(
                        future: _dbHelper.queryById('branches', _currentBranchId!),
                        builder: (context, snapshot) {
                          final branchName = snapshot.data?['name'] ?? _currentBranchId ?? 'Branch';
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.store, color: AppColors.primaryRed),
                              title: const Text('Branch'),
                              subtitle: Text(branchName),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Salesperson selector (only for admin/manager)
                    if (_isAdminOrManager && _salesPeople.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: _salesPersonId,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Salesperson (optional)',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text(
                              'No salesperson',
                              style: TextStyle(color: AppColors.white),
                            ),
                          ),
                          ..._salesPeople.map(
                            (sp) => DropdownMenuItem(
                              value: sp['id'],
                              child: Text(
                                sp['name'] ?? '',
                                style: const TextStyle(color: AppColors.white),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _salesPersonId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Product selector (collapsible)
                    if (_showProductSelector) ...[
                      ProductSelector(
                        onProductSelected: _addProduct,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Manual add item button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Or add custom item',
                          style: TextStyle(color: AppColors.white),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, color: AppColors.white),
                          onPressed: _addItem,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Items list
                    _items.isEmpty
                        ? const Center(
                            child: Text(
                              'No items added',
                              style: TextStyle(color: AppColors.white),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              var item = _items[index];
                              bool isProduct = item['productId'] != null;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    children: [
                                      TextFormField(
                                        initialValue: item['description'],
                                        style: const TextStyle(
                                          color: AppColors.black,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Description',
                                          labelStyle: TextStyle(
                                            color: AppColors.mediumGrey,
                                          ),
                                        ),
                                        enabled: !isProduct,
                                        onChanged: (value) => _updateItem(
                                          index,
                                          'description',
                                          value,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: item['quantity']
                                                  .toString(),
                                              keyboardType:
                                                  TextInputType.number,
                                              style: const TextStyle(
                                                color: AppColors.black,
                                              ),
                                              decoration: const InputDecoration(
                                                labelText: 'Qty',
                                                labelStyle: TextStyle(
                                                  color: AppColors.mediumGrey,
                                                ),
                                              ),
                                              onChanged: (value) {
                                                int qty =
                                                    int.tryParse(value) ?? 1;
                                                _updateItem(
                                                  index,
                                                  'quantity',
                                                  qty,
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: item['price']
                                                  .toString(),
                                              keyboardType:
                                                  TextInputType.number,
                                              style: const TextStyle(
                                                color: AppColors.black,
                                              ),
                                              decoration: const InputDecoration(
                                                labelText: 'Price',
                                                labelStyle: TextStyle(
                                                  color: AppColors.mediumGrey,
                                                ),
                                              ),
                                              onChanged: (value) {
                                                double price =
                                                    double.tryParse(value) ??
                                                    0.0;
                                                _updateItem(
                                                  index,
                                                  'price',
                                                  price,
                                                );
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: AppColors.error,
                                            ),
                                            onPressed: () => _removeItem(index),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                    const SizedBox(height: 16),

                    // Tracking fields
                    TextFormField(
                      controller: _trackingController,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        labelText: 'Tracking Number (optional)',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: AppColors.white.withOpacity(0.3),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _courierController,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        labelText: 'Courier Name (optional)',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: AppColors.white.withOpacity(0.3),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Discount section
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _discountType,
                            dropdownColor: AppColors.backgroundStart,
                            style: const TextStyle(color: AppColors.white),
                            decoration: InputDecoration(
                              labelText: 'Discount Type',
                              labelStyle: const TextStyle(
                                color: AppColors.white,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.white.withOpacity(0.3),
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.white),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'none',
                                child: Text('None'),
                              ),
                              DropdownMenuItem(
                                value: 'percentage',
                                child: Text('Percentage (%)'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text('Fixed (ETB)'),
                              ),
                            ],
                            onChanged: _updateDiscountType,
                          ),
                        ),
                        if (_discountType != 'none') ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _discountController,
                              style: const TextStyle(color: AppColors.white),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: _discountType == 'percentage'
                                    ? 'Percentage'
                                    : 'Amount',
                                labelStyle: const TextStyle(
                                  color: AppColors.white,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.white.withOpacity(0.3),
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                              onChanged: _updateDiscountValue,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Summary
                    Card(
                      color: AppColors.cardBackground,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Subtotal:',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  'ETB ${_total.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            if (_discountType != 'none') ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _discountType == 'percentage'
                                        ? 'Discount ($_discountValue%):'
                                        : 'Discount:',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: AppColors.success,
                                    ),
                                  ),
                                  Text(
                                    '- ETB ${(_discountType == 'percentage' ? _total * _discountValue / 100 : _discountValue).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Grand Total:',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'ETB ${_grandTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryRed,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Record Payment Now',
                        style: TextStyle(color: AppColors.white),
                      ),
                      value: _recordPayment,
                      activeColor: AppColors.primaryRed,
                      checkColor: AppColors.white,
                      onChanged: (value) {
                        setState(() {
                          _recordPayment = value ?? false;
                          if (!_recordPayment) {
                            _paidAmountController.clear();
                            _paidAmount = 0.0;
                          }
                        });
                      },
                    ),
                    if (_recordPayment) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _paidAmountController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount Paid (ETB)',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _paidAmount = double.tryParse(value) ?? 0.0;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _paymentMethod,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Payment Method',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.white.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: _paymentMethods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method,
                                child: Text(
                                  method,
                                  style: const TextStyle(
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _paymentMethod = value);
                        },
                      ),
                    ],
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          foregroundColor: AppColors.white,
                        ),
                        child: const Text('Create Order'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
