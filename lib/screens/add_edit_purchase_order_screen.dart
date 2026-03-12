import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../widgets/supplier_selector.dart';

class CreatePurchaseOrderScreen extends StatefulWidget {
  const CreatePurchaseOrderScreen({Key? key}) : super(key: key);

  @override
  _CreatePurchaseOrderScreenState createState() => _CreatePurchaseOrderScreenState();
}

class _CreatePurchaseOrderScreenState extends State<CreatePurchaseOrderScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  String? _supplierId;
  String _supplierName = '';
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDate;
  final _notesController = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  double _total = 0.0;
  bool _isLoading = false;
  String? _currentUserId;

  // For adding items
  String _itemType = 'product';
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  Future<void> _getCurrentUser() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
    }
  }

  void _addItem() {
    if (_itemNameController.text.isEmpty ||
        _quantityController.text.isEmpty ||
        _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all item fields')),
      );
      return;
    }
    setState(() {
      _items.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'itemType': _itemType,
        'itemName': _itemNameController.text.trim(),
        'quantity': int.tryParse(_quantityController.text) ?? 0,
        'unitPrice': double.tryParse(_priceController.text) ?? 0.0,
      });
      _calculateTotal();
      // Clear item fields
      _itemNameController.clear();
      _quantityController.clear();
      _priceController.clear();
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    _total = 0;
    for (var item in _items) {
      _total += (item['quantity'] as int) * (item['unitPrice'] as double);
    }
  }

  Future<void> _selectOrderDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _orderDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _orderDate = picked);
    }
  }

  Future<void> _selectExpectedDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _expectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a supplier')),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      String poId = DateTime.now().millisecondsSinceEpoch.toString();
      Map<String, dynamic> poData = {
        'id': poId,
        'supplierId': _supplierId,
        'supplierName': _supplierName,
        'orderDate': _orderDate.millisecondsSinceEpoch,
        'expectedDate': _expectedDate?.millisecondsSinceEpoch,
        'status': 'ordered',
        'notes': _notesController.text.trim(),
        'totalAmount': _total,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdBy': _currentUserId,
      };
      await _dbHelper.insert('purchase_orders', poData);

      // Insert items
      for (var item in _items) {
        item['poId'] = poId;
        await _dbHelper.insert('purchase_order_items', item);
      }

      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase order created')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Purchase Order'),
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
                    // Supplier selector
                    SupplierSelector(
                      onSupplierSelected: (id, name) {
                        setState(() {
                          _supplierId = id;
                          _supplierName = name;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Order date
                    ListTile(
                      title: Text(
                        'Order Date: ${_orderDate.day}/${_orderDate.month}/${_orderDate.year}',
                        style: const TextStyle(color: AppColors.white),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_today, color: AppColors.white),
                        onPressed: () => _selectOrderDate(context),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Expected date (optional)
                    ListTile(
                      title: Text(
                        _expectedDate == null
                            ? 'Expected Date: (optional)'
                            : 'Expected: ${_expectedDate!.day}/${_expectedDate!.month}/${_expectedDate!.year}',
                        style: const TextStyle(color: AppColors.white),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_today, color: AppColors.white),
                        onPressed: () => _selectExpectedDate(context),
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

                    // Add items section
                    const Text('Add Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
                    const SizedBox(height: 8),

                    // Item type toggle
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Product', style: TextStyle(color: AppColors.white)),
                            value: 'product',
                            groupValue: _itemType,
                            onChanged: (value) => setState(() => _itemType = value!),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Material', style: TextStyle(color: AppColors.white)),
                            value: 'material',
                            groupValue: _itemType,
                            onChanged: (value) => setState(() => _itemType = value!),
                          ),
                        ),
                      ],
                    ),

                    // Item name
                    TextFormField(
                      controller: _itemNameController,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        labelText: 'Item Name',
                        labelStyle: const TextStyle(color: AppColors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _quantityController,
                            style: const TextStyle(color: AppColors.white),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Quantity',
                              labelStyle: const TextStyle(color: AppColors.white),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.white),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _priceController,
                            style: const TextStyle(color: AppColors.white),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Unit Price',
                              labelStyle: const TextStyle(color: AppColors.white),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.white),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: AppColors.success),
                          onPressed: _addItem,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Items list
                    _items.isEmpty
                        ? const Center(child: Text('No items added', style: TextStyle(color: AppColors.white)))
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              var item = _items[index];
                              return Card(
                                child: ListTile(
                                  title: Text(item['itemName']),
                                  subtitle: Text('Qty: ${item['quantity']} @ ${item['unitPrice']}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('ETB ${(item['quantity'] * item['unitPrice']).toStringAsFixed(0)}'),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: AppColors.error),
                                        onPressed: () => _removeItem(index),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                    const SizedBox(height: 16),

                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
                        Text('ETB ${_total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
                      ],
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
                        child: const Text('Create Purchase Order'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}