import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/currency_helper.dart';
import '../utils/error_handler.dart';

class RetailProductsScreen extends StatefulWidget {
  const RetailProductsScreen({super.key});

  @override
  State<RetailProductsScreen> createState() => _RetailProductsScreenState();
}

class _RetailProductsScreenState extends State<RetailProductsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final Uuid _uuid = const Uuid();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _tailors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final products = await _dbHelper.query('retail_products');
    final users = await _dbHelper.query('users');
    if (!mounted) return;
    setState(() {
      _products = List<Map<String, dynamic>>.from(products);
      _tailors = users.where((u) => (u['role'] == 'tailor' && u['status'] == 'active')).toList();
      _isLoading = false;
    });
  }

  Future<void> _openAddEdit({Map<String, dynamic>? product}) async {
    final isEdit = product != null;
    final _nameController = TextEditingController(text: product?['name']?.toString() ?? '');
    final _descController = TextEditingController(text: product?['description']?.toString() ?? '');
    String _selectedCategory = product?['category']?.toString() ?? 'other';
    final _costController = TextEditingController(text: (product?['costPrice']?.toString() ?? ''));
    final _priceController = TextEditingController(text: (product?['sellingPrice']?.toString() ?? ''));
    final _stockController = TextEditingController(text: (product?['stock']?.toString() ?? '0'));
    String? _editingId = product?['id']?.toString();
    String? _selectedTailorId = product?['tailorId']?.toString();
    final _tailorCutController = TextEditingController(text: (product?['tailorCommission']?.toString() ?? ''));
    String? _selectedBranchId = product?['branchId']?.toString();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Theme(
          data: ThemeData.light(),
          child: AlertDialog(
            title: Text(isEdit ? 'Edit Retail Product' : 'Add Retail Product'),
            content: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                      TextFormField(
                        controller: _descController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          labelStyle: TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        items: [
                          'watch',
                          'perfume',
                          'pre-made chiffon',
                          'other'
                        ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (v) => setState(() => _selectedCategory = v ?? 'other'),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          labelStyle: TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                      TextFormField(
                        controller: _costController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Cost Price',
                          labelStyle: TextStyle(color: AppColors.textPrimary),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      TextFormField(
                        controller: _priceController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Selling Price',
                          labelStyle: TextStyle(color: AppColors.textPrimary),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      TextFormField(
                        controller: _stockController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Stock',
                          labelStyle: TextStyle(color: AppColors.textPrimary),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      if (_selectedCategory == 'pre-made chiffon') ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedTailorId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Select tailor')),
                            ..._tailors.map((t) => DropdownMenuItem(value: t['id']?.toString(), child: Text(t['name']?.toString() ?? ''))),
                          ],
                          onChanged: (v) => setState(() => _selectedTailorId = v),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Tailor',
                            labelStyle: TextStyle(color: AppColors.textPrimary),
                          ),
                        ),
                        TextFormField(
                          controller: _tailorCutController,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Tailor Commission',
                            labelStyle: TextStyle(color: AppColors.textPrimary),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final isPreMade = _selectedCategory == 'pre-made chiffon';
                  final now = DateTime.now().millisecondsSinceEpoch;
                  final productData = {
                    'id': isEdit ? _editingId : _uuid.v4(),
                    'name': _nameController.text.trim(),
                    'description': _descController.text.trim(),
                    'category': _selectedCategory,
                    'costPrice': double.tryParse(_costController.text) ?? 0,
                    'sellingPrice': double.tryParse(_priceController.text) ?? 0,
                    'stock': int.tryParse(_stockController.text) ?? 0,
                    'branchId': _selectedBranchId,
                    'tailorId': isPreMade ? _selectedTailorId : null,
                    'tailorCommission': isPreMade ? double.tryParse(_tailorCutController.text) ?? 0 : null,
                    'createdAt': now,
                    'syncStatus': 'pending',
                    'lastModified': now,
                    'changed_fields': jsonEncode({}),
                  };
                  if (isEdit) {
                    await _dbHelper.update('retail_products', productData);
                  } else {
                    await _dbHelper.insert('retail_products', productData, markSynced: false);
                    if (isPreMade && productData['tailorId'] != null) {
                      final tailor = await _dbHelper.getUser(productData['tailorId'].toString());
                      final commission = {
                        'id': _uuid.v4(),
                        'orderId': null,
                        'employeeId': productData['tailorId'],
                        'employeeName': tailor?['name'] ?? 'Tailor',
                        'amount': productData['tailorCommission'],
                        'type': 'tailor',
                        'status': 'pending',
                        'createdAt': now,
                        'syncStatus': 'pending',
                        'lastModified': now,
                        'changed_fields': jsonEncode({}),
                      };
                      await _dbHelper.insert('commissions', commission);
                    }
                  }
                  Navigator.pop(context);
                  await _loadData();
                  _syncService.triggerBackgroundSync();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showQuickSaleDialog(Map<String, dynamic> product) async {
    final qtyController = TextEditingController(text: '1');
    String paymentMethod = 'cash';
    await showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: Text('Sell ${product['name'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  labelStyle: TextStyle(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                items: ['cash', 'card'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => paymentMethod = v ?? 'cash',
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  labelStyle: TextStyle(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyController.text) ?? 1;
                Navigator.pop(context);
                await _sellRetailProduct(product, qty, paymentMethod);
              },
              child: const Text('Sell'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sellRetailProduct(Map<String, dynamic> product, int qty, String paymentMethod) async {
    if ((product['stock'] as int?) == null || (product['stock'] as int) < qty) {
      ErrorHandler.showError(context, 'Not enough stock');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final branchId = product['branchId']?.toString();
      final branch = branchId != null ? await _dbHelper.getBranchById(branchId) : null;
      final currency = branch?['currency'] ?? 'ETB';
      final cashAccount = await _dbHelper.getCashAccountForBranch(branchId);
      final now = DateTime.now().millisecondsSinceEpoch;

      final newStock = (product['stock'] as int) - qty;
      await _dbHelper.update('retail_products', {
        'id': product['id'],
        'stock': newStock,
        'syncStatus': 'pending',
        'lastModified': now,
      });

      final orderId = _uuid.v4();
      final item = {
        'retailProductId': product['id'],
        'name': product['name'],
        'quantity': qty,
        'price': (product['sellingPrice'] as num?)?.toDouble() ?? 0.0,
      };
      final total = (item['price'] as double) * (item['quantity'] as int);
      final orderData = {
        'id': orderId,
        'customerName': 'Walk-in',
        'items': jsonEncode([item]),
        'totalAmount': total,
        'paid_amount': total,
        'status': 'delivered',
        'stock_deducted': 1,
        'cogs': ((product['costPrice'] as num?)?.toDouble() ?? 0.0) * qty,
        'currency': currency,
        'branchId': branchId,
        'createdAt': now,
        'syncStatus': 'pending',
        'lastModified': now,
        'changed_fields': jsonEncode({}),
      };
      await _dbHelper.insert('orders', orderData);

      if (cashAccount != null) {
        try {
          await _dbHelper.addPayment(
            orderId,
            total,
            paymentMethod,
            type: 'payment',
            branchId: branchId,
            receivedBy: 'Walk-in',
            accountId: cashAccount['id'],
          );
        } catch (_) {}
      }

      // Link pending tailor commission (orderId == null)
      if (product['tailorId'] != null) {
        final existingComms = await _dbHelper.queryWhere(
          'commissions',
          "employeeId = ? AND type = 'tailor' AND status = 'pending' AND orderId IS NULL",
          [product['tailorId']],
        );
        if (existingComms.isNotEmpty) {
          final comm = existingComms.first;
          await _dbHelper.update('commissions', {
            'id': comm['id'],
            'orderId': orderId,
            'syncStatus': 'pending',
            'lastModified': now,
          });
        }
      }

      _syncService.triggerBackgroundSync();
      ErrorHandler.showSuccess(context, 'Item sold successfully');
      await _loadData();
    } catch (e) {
      ErrorHandler.showError(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retail Products'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            tooltip: 'Add product',
            icon: const Icon(Icons.add),
            onPressed: () => _openAddEdit(),
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
            : ListView(
                padding: const EdgeInsets.all(16),
                children: _products.isEmpty
                    ? [
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No retail products.'),
                          ),
                        )
                      ]
                    : _products.map((p) {
                        return Card(
                          color: AppColors.cardBackground,
                          child: ListTile(
                            title: Text(p['name'] ?? '', style: const TextStyle(color: AppColors.white)),
                            subtitle: Text(
                              'Category: ${p['category'] ?? ''} • Stock: ${p['stock'] ?? 0}',
                              style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                ElevatedButton(
                                  onPressed: () => _showQuickSaleDialog(p),
                                  child: const Text('Sell Now'),
                                ),
                                OutlinedButton(
                                  onPressed: () => _openAddEdit(product: p),
                                  child: const Text('Edit'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
              ),
      ),
    );
  }
}
