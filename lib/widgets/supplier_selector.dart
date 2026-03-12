import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';

class SupplierSelector extends StatefulWidget {
  final Function(String supplierId, String supplierName) onSupplierSelected;
  const SupplierSelector({super.key, required this.onSupplierSelected});

  @override
  _SupplierSelectorState createState() => _SupplierSelectorState();
}

class _SupplierSelectorState extends State<SupplierSelector> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  String? _selectedSupplierId;
  String _selectedSupplierName = '';
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    var suppliers = await _dbHelper.query('suppliers');
    setState(() {
      _suppliers = suppliers;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Supplier', style: TextStyle(color: AppColors.white)),
        const SizedBox(height: 8),
        if (_selectedSupplierId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_selectedSupplierName),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedSupplierId = null;
                      _selectedSupplierName = '';
                    });
                    widget.onSupplierSelected('', '');
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: null,
            dropdownColor: AppColors.backgroundStart,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
              labelText: 'Select Supplier',
              labelStyle: const TextStyle(color: AppColors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.white),
              ),
            ),
            items: _suppliers.map((s) => DropdownMenuItem<String>(
              value: s['id'],
              child: Text(s['name'] ?? ''),
            )).toList(),
            onChanged: (value) {
              var selected = _suppliers.firstWhere((s) => s['id'] == value);
              setState(() {
                _selectedSupplierId = value;
                _selectedSupplierName = selected['name'];
              });
              widget.onSupplierSelected(value!, selected['name']);
            },
          ),
      ],
    );
  }
}