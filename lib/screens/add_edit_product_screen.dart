import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class AddEditProductScreen extends StatefulWidget {
  final Map<String, dynamic>? productData;
  const AddEditProductScreen({super.key, this.productData});

  @override
  _AddEditProductScreenState createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _minLevelController = TextEditingController();
  bool _isCustom = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.productData != null) {
      _nameController.text = widget.productData!['name'] ?? '';
      _categoryController.text = widget.productData!['category'] ?? '';
      _costPriceController.text =
          widget.productData!['costPrice']?.toString() ?? '';
      _sellingPriceController.text =
          widget.productData!['sellingPrice']?.toString() ?? '';
      _stockController.text = widget.productData!['stock']?.toString() ?? '';
      _minLevelController.text =
          widget.productData!['minimumLevel']?.toString() ?? '';
      _isCustom = (widget.productData!['is_custom'] as num?)?.toInt() == 1;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id':
            widget.productData?['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'name': _nameController.text.trim(),
        'category': _categoryController.text.trim(),
        'costPrice': double.tryParse(_costPriceController.text) ?? 0,
        'sellingPrice': double.tryParse(_sellingPriceController.text) ?? 0,
        'stock': int.tryParse(_stockController.text) ?? 0,
        'minimumLevel': int.tryParse(_minLevelController.text) ?? 5,
        'is_custom': _isCustom ? 1 : 0,
      };
      if (widget.productData == null) {
        await _dbHelper.insert('products', data);
      } else {
        await _dbHelper.update('products', data);
      }
      if (mounted) {
        _syncService.triggerBackgroundSync();
        ErrorHandler.showSuccess(
          context,
          widget.productData == null ? 'Product saved' : 'Product updated',
        );
        ErrorHandler.safePop(context, true);
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
        title: Text(
          widget.productData == null ? 'Add Product' : 'Edit Product',
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // Name
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Product Name *',
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
                        validator: (value) =>
                            value == null || value.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Category
                      TextFormField(
                        controller: _categoryController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Category',
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

                      // Cost Price
                      TextFormField(
                        controller: _costPriceController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Cost Price (ETB)',
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

                      // Selling Price
                      TextFormField(
                        controller: _sellingPriceController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Selling Price (ETB)',
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

                      // Stock
                      TextFormField(
                        controller: _stockController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Stock',
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

                      CheckboxListTile(
                        value: _isCustom,
                        onChanged: (value) {
                          setState(() {
                            _isCustom = value ?? false;
                          });
                        },
                        activeColor: AppColors.primaryRed,
                        checkColor: AppColors.white,
                        title: const Text(
                          'Custom product',
                          style: TextStyle(color: AppColors.white),
                        ),
                        subtitle: const Text(
                          'Mark this when the product is made to order and may later be converted into stock.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),

                      // Minimum Level
                      TextFormField(
                        controller: _minLevelController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Minimum Level',
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
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: AppColors.white,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: AppColors.white,
                                )
                              : Text(
                                  widget.productData == null
                                      ? 'Add Product'
                                      : 'Update Product',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
