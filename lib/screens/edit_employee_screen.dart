import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class EditEmployeeScreen extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  const EditEmployeeScreen({Key? key, required this.employeeData}) : super(key: key);

  @override
  _EditEmployeeScreenState createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _commissionRateController = TextEditingController();
  final _tailorCutController = TextEditingController();
  final _deliveryCommissionController = TextEditingController();

  String _selectedRole = 'sales';
  String? _selectedBranchId;
  bool _isLoading = false;
  String _deliveryCommissionType = 'fixed';

  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _nameController.text = widget.employeeData['name'] ?? '';
    _phoneController.text = widget.employeeData['phone'] ?? '';
    _selectedRole = widget.employeeData['role'] ?? 'sales';
    _selectedBranchId = widget.employeeData['branchId'];
    if (widget.employeeData['commissionRate'] != null) {
      _commissionRateController.text = widget.employeeData['commissionRate'].toString();
    }
    if (widget.employeeData['tailorCut'] != null) {
      _tailorCutController.text = widget.employeeData['tailorCut'].toString();
    }
    if (widget.employeeData['delivery_commission_type'] != null) {
      _deliveryCommissionType = widget.employeeData['delivery_commission_type'];
    }
    if (widget.employeeData['delivery_commission_value'] != null) {
      _deliveryCommissionController.text = widget.employeeData['delivery_commission_value'].toString();
    }
  }

  Future<void> _loadBranches() async {
    var branches = await _dbHelper.query('branches');
    setState(() {
      _branches = branches.map((b) => {'id': b['id'], 'name': b['name']}).toList();
    });
  }

  Future<void> _update() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id': widget.employeeData['id'],
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _selectedRole,
        'branchId': _selectedBranchId,
        'employmentType': widget.employeeData['employmentType'] ?? 'permanent',
        'status': widget.employeeData['status'] ?? 'active',
        'createdAt': widget.employeeData['createdAt'],
      };

      if (_selectedRole == 'sales') {
        data['commissionRate'] = double.tryParse(_commissionRateController.text) ?? 0.0;
      } else if (_selectedRole == 'tailor') {
        data['tailorCut'] = double.tryParse(_tailorCutController.text) ?? 0.0;
      } else if (_selectedRole == 'delivery') {
        data['delivery_commission_type'] = _deliveryCommissionType;
        data['delivery_commission_value'] = double.tryParse(_deliveryCommissionController.text) ?? 0.0;
      }

      await _dbHelper.update('users', data);

      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      if (mounted) Navigator.pop(context);
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
        title: const Text('Edit Employee'),
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
        child: Padding(
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
                    labelText: 'Full Name *',
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

                // Phone
                TextFormField(
                  controller: _phoneController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    labelText: 'Phone',
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

                // Role dropdown
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  dropdownColor: AppColors.backgroundStart,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    labelText: 'Role *',
                    labelStyle: const TextStyle(color: AppColors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'sales', child: Text('Sales')),
                    DropdownMenuItem(value: 'tailor', child: Text('Tailor')),
                    DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                  ],
                  onChanged: (value) => setState(() => _selectedRole = value!),
                ),
                const SizedBox(height: 16),

                // Branch dropdown
                DropdownButtonFormField<String>(
                  value: _selectedBranchId,
                  dropdownColor: AppColors.backgroundStart,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    labelText: 'Branch *',
                    labelStyle: const TextStyle(color: AppColors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                  items: _branches.map<DropdownMenuItem<String>>((b) => DropdownMenuItem<String>(
                    value: b['id'] as String,
                    child: Text(b['name'] ?? ''),
                  )).toList(),
                  onChanged: (value) => setState(() => _selectedBranchId = value),
                  validator: (value) => value == null ? 'Select branch' : null,
                ),
                const SizedBox(height: 16),

                // Commission rate (only for sales)
                if (_selectedRole == 'sales') ...[
                  TextFormField(
                    controller: _commissionRateController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Commission Rate (%)',
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
                ],

                // Tailor cut (only for tailor)
                if (_selectedRole == 'tailor') ...[
                  TextFormField(
                    controller: _tailorCutController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Default Tailor Cut (ETB)',
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
                ],

                // Delivery commission fields (only for delivery)
                if (_selectedRole == 'delivery') ...[
                  DropdownButtonFormField<String>(
                    value: _deliveryCommissionType,
                    dropdownColor: AppColors.backgroundStart,
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      labelText: 'Commission Type',
                      labelStyle: const TextStyle(color: AppColors.white),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.white),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
                      DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                    ],
                    onChanged: (value) => setState(() => _deliveryCommissionType = value!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _deliveryCommissionController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Commission Value',
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
                ],

                const SizedBox(height: 24),

                // Update button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _update,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: AppColors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: AppColors.white)
                        : const Text('Update Employee'),
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