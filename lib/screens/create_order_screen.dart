import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  String? _customerId;
  String _customerName = '';
  List<Map<String, dynamic>> _items = [];
  double _total = 0.0;
  double _deliveryFee = 0.0;
  String _discountType = 'none';
  double _discountValue = 0.0;
  double _grandTotal = 0.0;
  bool _isLoading = false;
  String? _currentUserId;
  String? _currentBranchId;

  final TextEditingController _deliveryFeeController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();

  // Store products to check stock (optional, can query on the fly)
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _loadProducts();
  }

  Future<void> _getCurrentUser() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      var userData = await _dbHelper.queryById('users', user.uid);
      if (userData != null) {
        _currentBranchId = userData['branchId'];
      }
    }
  }

  Future<void> _loadProducts() async {
    var products = await _dbHelper.query('products');
    setState(() {
      _products = products;
    });
  }

  void _addItem() {
    setState(() {
      _items.add({'description': '', 'quantity': 1, 'price': 0.0, 'productId': null});
    });
  }

  void _addProduct(Map<String, dynamic> product) async {
    // Check stock
    int stock = product['stock'] ?? 0;
    if (stock < 1) {
      ErrorHandler.showError(context, 'Product out of stock');
      return;
    }

    // Deduct stock immediately (optimistic update)
    product['stock'] = stock - 1;
    await _dbHelper.update('products', product);

    setState(() {
      _items.add({
        'description': product['name'],
        'quantity': 1,
        'price': (product['sellingPrice'] as num?)?.toDouble() ?? 0.0,
        'productId': product['id'],
      });
      _calculateTotal();
    });
  }

  void _removeItem(int index) {
    var item = _items[index];
    // If it's a product, restore stock
    if (item['productId'] != null) {
      // Find the product and increment stock
      var product = _products.firstWhere((p) => p['id'] == item['productId'], orElse: () => <String, dynamic>{});
      if (product.isNotEmpty) {
        product['stock'] = (product['stock'] ?? 0) + item['quantity'];
        _dbHelper.update('products', product); // fire and forget
      }
    }
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

  void _updateDeliveryFee(String value) {
    setState(() {
      _deliveryFee = double.tryParse(value) ?? 0.0;
      _calculateGrandTotal();
    });
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
    double subtotal = _total + _deliveryFee;
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
    if (_items.isEmpty) {
      ErrorHandler.showError(context, 'Add at least one item');
      return;
    }
    if (_currentUserId == null) {
      ErrorHandler.showError(context, 'User not authenticated');
      return;
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
        'delivery_fee': _deliveryFee,
        'discount_type': _discountType == 'none' ? null : _discountType,
        'discount_value': _discountType == 'none' ? 0 : _discountValue,
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdBy': _currentUserId,
        'branchId': _currentBranchId,
      };

      await _dbHelper.insert('orders', orderData);

      // Sync if online
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      if (mounted) {
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

                    // Product selector
                    ProductSelector(
                      onProductSelected: _addProduct,
                    ),
                    const SizedBox(height: 16),

                    // Manual add item button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Or add custom item', style: TextStyle(color: AppColors.white)),
                        IconButton(
                          icon: const Icon(Icons.add, color: AppColors.white),
                          onPressed: _addItem,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Items list
                    _items.isEmpty
                        ? const Center(child: Text('No items added', style: TextStyle(color: AppColors.white)))
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
                                        style: const TextStyle(color: AppColors.black),
                                        decoration: const InputDecoration(
                                          labelText: 'Description',
                                          labelStyle: TextStyle(color: AppColors.mediumGrey),
                                        ),
                                        enabled: !isProduct, // can't edit product description
                                        onChanged: (value) => _updateItem(index, 'description', value),
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: item['quantity'].toString(),
                                              keyboardType: TextInputType.number,
                                              style: const TextStyle(color: AppColors.black),
                                              decoration: const InputDecoration(
                                                labelText: 'Qty',
                                                labelStyle: TextStyle(color: AppColors.mediumGrey),
                                              ),
                                              onChanged: (value) {
                                                int qty = int.tryParse(value) ?? 1;
                                                _updateItem(index, 'quantity', qty);
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: item['price'].toString(),
                                              keyboardType: TextInputType.number,
                                              style: const TextStyle(color: AppColors.black),
                                              decoration: const InputDecoration(
                                                labelText: 'Price',
                                                labelStyle: TextStyle(color: AppColors.mediumGrey),
                                              ),
                                              onChanged: (value) {
                                                double price = double.tryParse(value) ?? 0.0;
                                                _updateItem(index, 'price', price);
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: AppColors.error),
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

                    // Delivery fee
                    TextFormField(
                      controller: _deliveryFeeController,
                      style: const TextStyle(color: AppColors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Delivery Fee (ETB)',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                      onChanged: _updateDeliveryFee,
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
                              labelStyle: const TextStyle(color: AppColors.white),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.white),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'none', child: Text('None')),
                              DropdownMenuItem(value: 'percentage', child: Text('Percentage (%)')),
                              DropdownMenuItem(value: 'fixed', child: Text('Fixed (ETB)')),
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
                                labelText: _discountType == 'percentage' ? 'Percentage' : 'Amount',
                                labelStyle: const TextStyle(color: AppColors.white),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.white),
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
                                const Text('Subtotal:', style: TextStyle(fontSize: 16)),
                                Text('ETB ${_total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Delivery Fee:', style: TextStyle(fontSize: 16)),
                                Text('ETB ${_deliveryFee.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
                              ],
                            ),
                            if (_discountType != 'none') ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _discountType == 'percentage'
                                        ? 'Discount ($_discountValue%):'
                                        : 'Discount:',
                                    style: const TextStyle(fontSize: 16, color: AppColors.success),
                                  ),
                                  Text(
                                    '- ETB ${(_discountType == 'percentage' ? (_total + _deliveryFee) * _discountValue / 100 : _discountValue).toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 16, color: AppColors.success),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Grand Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text('ETB ${_grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryRed)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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