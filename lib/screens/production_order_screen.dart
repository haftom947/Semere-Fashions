import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import '../widgets/employee_selector_dialog.dart';

class ProductionOrderScreen extends StatefulWidget {
  const ProductionOrderScreen({Key? key}) : super(key: key);

  @override
  _ProductionOrderScreenState createState() => _ProductionOrderScreenState();
}

class _ProductionOrderScreenState extends State<ProductionOrderScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _productNameController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _notesController = TextEditingController();

  String? _tailorId;
  String? _tailorName;
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _allMaterials = [];
  Map<String, TextEditingController> _quantityControllers = {};
  bool _isLoading = false;

  double _totalMaterialCost = 0;
  double _tailorCommission = 0;
  double _totalCost = 0;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    var materials = await _dbHelper.query('materials');
    if (mounted) setState(() {
      _allMaterials = materials;
      for (var mat in materials) {
        _quantityControllers[mat['id']] = TextEditingController();
      }
    });
  }

  void _calculateTotals() {
    _totalMaterialCost = 0;
    for (var mat in _allMaterials) {
      var qtyStr = _quantityControllers[mat['id']]?.text;
      if (qtyStr != null && qtyStr.isNotEmpty) {
        double qty = double.tryParse(qtyStr) ?? 0;
        _totalMaterialCost += qty * ((mat['cost'] as num?)?.toDouble() ?? 0);
      }
    }
    _totalCost = _totalMaterialCost + _tailorCommission;
    setState(() {});
  }

  Future<void> _selectTailor() async {
    var employees = await _dbHelper.query('users');
    var tailors = employees.where((e) => e['role'] == 'tailor' && e['status'] == 'active').toList();
    if (tailors.isEmpty) {
      ErrorHandler.showError(context, 'No active tailors found.');
      return;
    }
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EmployeeSelectorDialog(
        employees: tailors,
        title: 'Select Tailor',
      ),
    );
    if (selected != null) {
      if (mounted) {
        setState(() {
          _tailorId = selected['id'];
          _tailorName = selected['name'];
          // Optionally use tailor's default cut from their record
          _tailorCommission = (selected['tailorCut'] as num?)?.toDouble() ?? 0;
          _calculateTotals();
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_tailorId == null) {
      ErrorHandler.showError(context, 'Please select a tailor');
      return;
    }
    if (_materials.isEmpty) {
      ErrorHandler.showError(context, 'Use at least one material');
      return;
    }
    if (_productNameController.text.isEmpty) {
      ErrorHandler.showError(context, 'Enter product name');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Prepare materials used list
      List<Map<String, dynamic>> materialsUsed = [];
      for (var mat in _allMaterials) {
        var qtyStr = _quantityControllers[mat['id']]?.text;
        if (qtyStr != null && qtyStr.isNotEmpty) {
          double qty = double.tryParse(qtyStr) ?? 0;
          if (qty > 0) {
            materialsUsed.add({
              'materialId': mat['id'],
              'name': mat['name'],
              'quantity': qty,
              'costPerUnit': mat['cost'] ?? 0,
            });
            // Deduct stock
            mat['stock'] = (mat['stock'] as int) - qty.round();
            await _dbHelper.update('materials', mat);
          }
        }
      }

      String poId = DateTime.now().millisecondsSinceEpoch.toString();
      double sellingPrice = double.tryParse(_sellingPriceController.text) ?? 0;

      // Create production order
      Map<String, dynamic> prodOrder = {
        'id': poId,
        'productName': _productNameController.text.trim(),
        'tailorId': _tailorId,
        'tailorName': _tailorName,
        'materialsUsed': jsonEncode(materialsUsed),
        'totalMaterialCost': _totalMaterialCost,
        'tailorCommission': _tailorCommission,
        'totalCost': _totalCost,
        'sellingPrice': sellingPrice,
        'status': 'completed', // or 'in_progress' if you want a multi-step
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'completedAt': DateTime.now().millisecondsSinceEpoch,
        'notes': _notesController.text.trim(),
      };
      await _dbHelper.insert('production_orders', prodOrder);

      // Create a product from this production
      String productId = DateTime.now().millisecondsSinceEpoch.toString() + 'p';
      Map<String, dynamic> product = {
        'id': productId,
        'name': _productNameController.text.trim(),
        'category': 'promotional',
        'costPrice': _totalCost,
        'sellingPrice': sellingPrice,
        'stock': 1,
        'minimumLevel': 0,
        'productionOrderId': poId,
      };
      await _dbHelper.insert('products', product);

      // Create commission for tailor
      if (_tailorCommission > 0) {
        await _dbHelper.insert('commissions', {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'orderId': poId,
          'employeeId': _tailorId,
          'employeeName': _tailorName,
          'amount': _tailorCommission,
          'type': 'tailor',
          'status': 'pending',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Sync if online
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      if (mounted) {
        ErrorHandler.showSuccess(context, 'Production order created');
        ErrorHandler.safePop(context);
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
        title: const Text('Production Order'),
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
                    // Product name
                    TextFormField(
                      controller: _productNameController,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        labelText: 'Product Name *',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tailor selection
                    ListTile(
                      title: Text(
                        _tailorName ?? 'Select Tailor *',
                        style: const TextStyle(color: AppColors.white),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.person, color: AppColors.white),
                        onPressed: _selectTailor,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Materials list with quantity fields
                    const Text('Materials Used', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.white)),
                    ..._allMaterials.map((mat) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(mat['name'], style: const TextStyle(color: AppColors.white))),
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                controller: _quantityControllers[mat['id']],
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: AppColors.white),
                                decoration: InputDecoration(
                                  hintText: 'Qty',
                                  hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                                  ),
                                ),
                                onChanged: (_) => _calculateTotals(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 16),

                    // Tailor commission (could be a separate field)
                    TextFormField(
                      initialValue: _tailorCommission.toString(),
                      style: const TextStyle(color: AppColors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Tailor Commission (ETB)',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _tailorCommission = double.tryParse(value) ?? 0;
                          _calculateTotals();
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Selling price
                    TextFormField(
                      controller: _sellingPriceController,
                      style: const TextStyle(color: AppColors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Selling Price (ETB)',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Cost summary
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _buildSummaryRow('Material Cost', _totalMaterialCost),
                            _buildSummaryRow('Tailor Commission', _tailorCommission),
                            const Divider(),
                            _buildSummaryRow('Total Cost', _totalCost, bold: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Notes
                    TextFormField(
                      controller: _notesController,
                      style: const TextStyle(color: AppColors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Notes',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: AppColors.white,
                        ),
                        child: const Text('Create Production Order'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text('ETB ${amount.toStringAsFixed(2)}', style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}