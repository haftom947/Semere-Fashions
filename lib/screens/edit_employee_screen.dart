import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class EditEmployeeScreen extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  const EditEmployeeScreen({super.key, required this.employeeData});

  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
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
  final _monthlySalaryController = TextEditingController();

  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _selectedRole;
  int? _selectedRoleId;
  String? _selectedBranchId;
  bool _isLoading = false;
  String _deliveryCommissionType = 'fixed';
  bool _isActive = true;

  String get _selectedSalaryType =>
      (_selectedRole?['salary_type'] ?? 'commission').toString();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.employeeData['name']?.toString() ?? '';
    _phoneController.text = widget.employeeData['phone']?.toString() ?? '';
    _commissionRateController.text =
        widget.employeeData['commissionRate']?.toString() ?? '';
    _tailorCutController.text =
        widget.employeeData['tailorCut']?.toString() ?? '';
    _deliveryCommissionController.text =
        widget.employeeData['delivery_commission_value']?.toString() ?? '';
    _monthlySalaryController.text =
        widget.employeeData['monthly_salary']?.toString() ?? '';
    _selectedBranchId = widget.employeeData['branchId']?.toString();
    _deliveryCommissionType =
        widget.employeeData['delivery_commission_type']?.toString() ?? 'fixed';
    _isActive = widget.employeeData['status'] == 'active';
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final roles = await _dbHelper.query('roles');
    final branches = await _dbHelper.query('branches');
    roles.sort(
      (a, b) => (a['name'] ?? '').toString().compareTo(
        (b['name'] ?? '').toString(),
      ),
    );

    Map<String, dynamic>? matchedRole;
    final storedRoleId = widget.employeeData['role_id'];
    if (storedRoleId != null) {
      for (final role in roles) {
        if (role['id'].toString() == storedRoleId.toString()) {
          matchedRole = role;
          break;
        }
      }
    }
    matchedRole ??= roles.cast<Map<String, dynamic>?>().firstWhere(
      (role) =>
          role != null &&
          (role['name'] ?? '').toString().toLowerCase() ==
              (widget.employeeData['role'] ?? '').toString().toLowerCase(),
      orElse: () => roles.isNotEmpty ? roles.first : null,
    );

    if (!mounted) return;
    setState(() {
      _roles = roles;
      _branches = branches
          .map((b) => {'id': b['id'], 'name': b['name']})
          .toList();
      _selectedRole = matchedRole;
      _selectedRoleId = matchedRole?['id'] as int?;
      if (_selectedSalaryType == 'monthly' &&
          _monthlySalaryController.text.trim().isEmpty &&
          _selectedRole?['default_monthly_salary'] != null) {
        _monthlySalaryController.text =
            _selectedRole!['default_monthly_salary'].toString();
      }
    });
  }

  void _setSelectedRole(Map<String, dynamic> role) {
    setState(() {
      _selectedRole = role;
      if ((role['salary_type'] ?? 'commission') == 'monthly') {
        if (_monthlySalaryController.text.trim().isEmpty &&
            role['default_monthly_salary'] != null) {
          _monthlySalaryController.text =
              role['default_monthly_salary'].toString();
        }
      } else {
        _monthlySalaryController.clear();
      }
    });
  }

  String _legacyRoleValue(Map<String, dynamic> role) {
    return (role['name'] ?? '').toString().trim().toLowerCase();
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.white),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.white),
      ),
    );
  }

  Future<void> _update() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == null) return;

    setState(() => _isLoading = true);
    try {
      final isMonthly = _selectedSalaryType == 'monthly';
      final data = <String, dynamic>{
        'id': widget.employeeData['id'],
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _legacyRoleValue(_selectedRole!),
        'role_id': _selectedRole!['id'],
        'monthly_salary': isMonthly
            ? double.tryParse(_monthlySalaryController.text.trim())
            : null,
        'branchId': _selectedBranchId,
        'employmentType': widget.employeeData['employmentType'] ?? 'permanent',
        'status': _isActive ? 'active' : 'inactive',
        'createdAt': widget.employeeData['createdAt'],
        'commissionRate': isMonthly
            ? null
            : double.tryParse(_commissionRateController.text.trim()) ?? 0.0,
        'tailorCut': isMonthly
            ? null
            : double.tryParse(_tailorCutController.text.trim()) ?? 0.0,
        'delivery_commission_type':
            isMonthly ? null : _deliveryCommissionType,
        'delivery_commission_value': isMonthly
            ? null
            : double.tryParse(_deliveryCommissionController.text.trim()) ?? 0.0,
      };

      await _dbHelper.update('users', data);
      final userId = widget.employeeData['id']?.toString() ?? '';
      if (userId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .set(data, SetOptions(merge: true));
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: _inputDecoration('Full Name *'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: _inputDecoration('Phone'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedRoleId,
                  dropdownColor: AppColors.backgroundStart,
                  style: const TextStyle(color: AppColors.white),
                  decoration: _inputDecoration('Role *'),
                  items: _roles
                      .map(
                        (role) => DropdownMenuItem<int>(
                          value: role['id'] as int,
                          child: Text(role['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedRoleId = value);
                    final role = _roles.firstWhere((r) => r['id'] == value);
                    _setSelectedRole(role);
                  },
                  validator: (value) =>
                      value == null ? 'Select a role' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedBranchId,
                  dropdownColor: AppColors.backgroundStart,
                  style: const TextStyle(color: AppColors.white),
                  decoration: _inputDecoration('Branch *'),
                  items: _branches
                      .map(
                        (b) => DropdownMenuItem<String>(
                          value: b['id']?.toString(),
                          child: Text(b['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedBranchId = value),
                  validator: (value) => value == null ? 'Select branch' : null,
                ),
                const SizedBox(height: 16),
                if (_selectedSalaryType == 'monthly') ...[
                  TextFormField(
                    controller: _monthlySalaryController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inputDecoration('Monthly Salary (ETB)'),
                  ),
                  const SizedBox(height: 16),
                ],
                // Employee Status Toggle
                Card(
                  color: AppColors.white.withOpacity(0.08),
                  child: SwitchListTile(
                    title: const Text(
                      'Active Employee',
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      _isActive ? 'Employee is active' : 'Employee is inactive',
                      style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                    ),
                    value: _isActive,
                    activeColor: AppColors.success,
                    onChanged: (value) {
                      setState(() => _isActive = value);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (_selectedSalaryType == 'commission') ...[
                  TextFormField(
                    controller: _commissionRateController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inputDecoration(
                      'Commission Rate (% of Gross Profit)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _tailorCutController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inputDecoration('Default Tailor Cut (ETB)'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _deliveryCommissionType,
                    dropdownColor: AppColors.backgroundStart,
                    style: const TextStyle(color: AppColors.white),
                    decoration: _inputDecoration('Delivery Commission Type'),
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
                      DropdownMenuItem(
                        value: 'percentage',
                        child: Text('Percentage'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _deliveryCommissionType = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _deliveryCommissionController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inputDecoration('Delivery Commission Value'),
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 24),
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
                        ? const CircularProgressIndicator(
                            color: AppColors.white,
                          )
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
