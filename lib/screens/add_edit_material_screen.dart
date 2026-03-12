import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class AddEditMaterialScreen extends StatefulWidget {
  final Map<String, dynamic>? materialData;
  const AddEditMaterialScreen({Key? key, this.materialData}) : super(key: key);

  @override
  _AddEditMaterialScreenState createState() => _AddEditMaterialScreenState();
}

class _AddEditMaterialScreenState extends State<AddEditMaterialScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _unitController = TextEditingController();
  final _stockController = TextEditingController();
  final _minLevelController = TextEditingController();
  bool _isLoading = false;

  final List<String> _unitOptions = ['meter', 'piece', 'box', 'kg', 'liter'];

  @override
  void initState() {
    super.initState();
    if (widget.materialData != null) {
      _nameController.text = widget.materialData!['name'] ?? '';
      _categoryController.text = widget.materialData!['category'] ?? '';
      _unitController.text = widget.materialData!['unit'] ?? 'piece';
      _stockController.text = widget.materialData!['stock']?.toString() ?? '';
      _minLevelController.text = widget.materialData!['minimumLevel']?.toString() ?? '';
    } else {
      _unitController.text = 'piece';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id': widget.materialData?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'name': _nameController.text.trim(),
        'category': _categoryController.text.trim(),
        'unit': _unitController.text,
        'stock': int.tryParse(_stockController.text) ?? 0,
        'minimumLevel': int.tryParse(_minLevelController.text) ?? 5,
      };
      if (widget.materialData == null) {
        await _dbHelper.insert('materials', data);
      } else {
        await _dbHelper.update('materials', data);
      }
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }
      if (mounted) ErrorHandler.safePop(context);
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
        title: Text(widget.materialData == null ? 'Add Material' : 'Edit Material'),
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
                          labelText: 'Material Name *',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Required' : null,
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
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Unit dropdown
                      DropdownButtonFormField<String>(
                        value: _unitController.text.isEmpty ? null : _unitController.text,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Unit *',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: _unitOptions.map((unit) => DropdownMenuItem<String>(
                          value: unit,
                          child: Text(unit),
                        )).toList(),
                        onChanged: (value) {
                          setState(() {
                            _unitController.text = value ?? 'piece';
                          });
                        },
                        validator: (value) => value == null ? 'Select unit' : null,
                      ),
                      const SizedBox(height: 16),

                      // Stock
                      TextFormField(
                        controller: _stockController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Current Stock',
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

                      // Minimum Level
                      TextFormField(
                        controller: _minLevelController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Minimum Level',
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
                              ? const CircularProgressIndicator(color: AppColors.white)
                              : Text(widget.materialData == null ? 'Add Material' : 'Update Material'),
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