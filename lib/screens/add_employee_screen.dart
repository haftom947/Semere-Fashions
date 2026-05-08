import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({Key? key}) : super(key: key);

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _commissionRateController = TextEditingController();
  final _tailorCutController = TextEditingController();
  final _deliveryCommissionController = TextEditingController();
  final _monthlySalaryController = TextEditingController();

  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _selectedRole;
  int? _selectedRoleId;      // ← NEW: tracks dropdown value
  String? _selectedBranchId;
  bool _isLoading = false;
  bool _obscurePin = true;
  bool _showCommissionRate = false;
  bool _showTailorCut = false;
  bool _showDeliveryFields = false;
  bool _showMonthlySalary = false;
  String _deliveryCommissionType = 'fixed';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  String _safeName(dynamic row) {
    if (row is Map) {
      return (row['name'] ?? '').toString().trim().toLowerCase();
    }
    return '';
  }

  List<Map<String, dynamic>> _normalizeRows(List<Map<String, dynamic>> rows) {
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _loadInitialData() async {
    await _dbHelper.ensureDefaultRoles();
    var roles = _normalizeRows(await _dbHelper.queryAll('roles'));
    var branches = _normalizeRows(await _dbHelper.queryAll('branches'));

    if (roles.isEmpty || branches.isEmpty) {
      debugPrint('AddEmployeeScreen found empty local data. Trying sync...');
      try {
        await _syncService.syncAll();
      } catch (e) {
        debugPrint('AddEmployeeScreen sync fallback failed: $e');
      }
      roles = _normalizeRows(await _dbHelper.queryAll('roles'));
      branches = _normalizeRows(await _dbHelper.queryAll('branches'));
    }

    try {
      roles.sort((a, b) => _safeName(a).compareTo(_safeName(b)));
      branches.sort((a, b) => _safeName(a).compareTo(_safeName(b)));
    } catch (e) {
      debugPrint('AddEmployeeScreen sort failed: $e');
    }

    debugPrint('Roles loaded: $roles');
    debugPrint('Branches loaded: $branches');

    if (!mounted) return;
    setState(() {
      _roles = roles;
      _branches = branches;
      _selectedRoleId = null;
      _selectedRole = null;
      _resetFieldVisibility();
    });
  }

  void _resetFieldVisibility() {
    _showCommissionRate = false;
    _showTailorCut = false;
    _showDeliveryFields = false;
    _showMonthlySalary = false;
  }

  void _applyRoleSelection(Map<String, dynamic>? role) {
    final apply = () {
      _selectedRole = role;
      _resetFieldVisibility();

      if (role == null) {
        _clearAllControllers();
        return;
      }

      final salaryType = (role['salary_type'] ?? '').toString();
      final name = (role['name'] ?? '').toString().toLowerCase();

      // Monthly salary
      if (salaryType == 'monthly') {
        _showMonthlySalary = true;
        final defaultSalary = role['default_monthly_salary'];
        _monthlySalaryController.text =
            defaultSalary != null ? defaultSalary.toString() : '';
      }

      // Commission fields ONLY for the three classic roles
      if (salaryType == 'commission') {
        if (name == 'sales') {
          _showCommissionRate = true;
        } else if (name == 'tailor') {
          _showTailorCut = true;
        } else if (name == 'delivery') {
          _showDeliveryFields = true;
        }
        // Admin, Manager, and any future custom commission roles show nothing extra
      }

      // Clear controllers that are now hidden
      if (!_showMonthlySalary) _monthlySalaryController.clear();
      if (!_showCommissionRate) _commissionRateController.clear();
      if (!_showTailorCut) _tailorCutController.clear();
      if (!_showDeliveryFields) {
        _deliveryCommissionController.clear();
        _deliveryCommissionType = 'fixed';
      }
    };

    setState(apply);
  }

  void _clearAllControllers() {
    _monthlySalaryController.clear();
    _commissionRateController.clear();
    _tailorCutController.clear();
    _deliveryCommissionController.clear();
    _deliveryCommissionType = 'fixed';
  }

  Future<void> _onRoleChanged(int? roleId) async {
    _selectedRoleId = roleId;

    if (roleId == null) {
      _applyRoleSelection(null);
      return;
    }

    final role = await _dbHelper.getRoleById(roleId);
    if (!mounted) return;

    if (role == null) {
      debugPrint('AddEmployeeScreen could not find role for id=$roleId');
      _applyRoleSelection(null);
      return;
    }

    _applyRoleSelection(role);
    debugPrint(
        'AddEmployeeScreen selected role: ${role['name']} (${role['salary_type']})');
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select a branch')));
      return;
    }
    if (_selectedRole == null) {
      ErrorHandler.showWarning(context, 'Please create or select a role first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final pin = _pinController.text.trim();
      final email = 'pin$pin@semere.local';

      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pin);

      final uid = userCredential.user!.uid;
      final isMonthly = _showMonthlySalary;
      final monthlySalary = isMonthly
          ? double.tryParse(_monthlySalaryController.text.trim())
          : null;

      final userData = <String, dynamic>{
        'id': uid,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _legacyRoleValue(_selectedRole!),
        'role_id': _selectedRole!['id'],
        'monthly_salary': monthlySalary,
        'branchId': _selectedBranchId,
        'employmentType': 'permanent',
        'status': 'active',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };

      // Only attach commission fields if the role specifically uses them
      if (_showCommissionRate) {
        userData['commissionRate'] =
            double.tryParse(_commissionRateController.text.trim()) ?? 0.0;
      }
      if (_showTailorCut) {
        userData['tailorCut'] =
            double.tryParse(_tailorCutController.text.trim()) ?? 0.0;
      }
      if (_showDeliveryFields) {
        userData['delivery_commission_type'] = _deliveryCommissionType;
        userData['delivery_commission_value'] =
            double.tryParse(_deliveryCommissionController.text.trim()) ?? 0.0;
      }

      await _dbHelper.insert('users', userData);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData, SetOptions(merge: true));

      if (!mounted) return;
      _syncService.triggerBackgroundSync();
      ErrorHandler.showSuccess(context, 'Employee added successfully!');
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      var message = 'Failed to create employee';
      if (e.code == 'email-already-in-use') {
        message = 'PIN already in use';
      } else if (e.code == 'weak-password') {
        message = 'PIN too weak (use 6 digits)';
      }
      if (mounted) ErrorHandler.showError(context, message);
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        'AddEmployeeScreen build: roles=${_roles.length}, branches=${_branches.length}, selectedRoleId=$_selectedRoleId');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Employee'),
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
                padding: const EdgeInsets.all(16.0),
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

                      // ---- ROLE DROPDOWN (FIXED) ----
                      DropdownButtonFormField<int>(
                        value: _selectedRoleId, // ← CHANGED from initialValue to value
                        isExpanded: true,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: _inputDecoration('Role *'),
                        hint: const Text(
                          'Select a role',
                          style: TextStyle(color: Colors.white70),
                        ),
                        items: _roles
                            .map(
                              (role) => DropdownMenuItem<int>(
                                value: role['id'] as int,
                                child: Text(role['name']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: _onRoleChanged,
                        validator: (value) =>
                            value == null ? 'Select a role' : null,
                      ),
                      if (_roles.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Debug: no roles loaded for dropdown',
                          style: TextStyle(color: Colors.amberAccent),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // ---- BRANCH DROPDOWN (FIXED) ----
                      DropdownButtonFormField<String>(
                        value: _selectedBranchId, // ← CHANGED from initialValue to value
                        isExpanded: true,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: _inputDecoration('Branch *'),
                        hint: const Text(
                          'Select a branch',
                          style: TextStyle(color: Colors.white70),
                        ),
                        items: _branches
                            .map(
                              (branch) => DropdownMenuItem<String>(
                                value: branch['id']?.toString(),
                                child: Text(branch['name']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedBranchId = value),
                        validator: (value) =>
                            value == null ? 'Select branch' : null,
                      ),
                      if (_branches.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Debug: no branches loaded for dropdown',
                          style: TextStyle(color: Colors.amberAccent),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // ---- MONTHLY SALARY FIELD ----
                      if (_showMonthlySalary) ...[
                        TextFormField(
                          controller: _monthlySalaryController,
                          style: const TextStyle(color: AppColors.white),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration('Monthly Salary (ETB)'),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ---- SALES COMMISSION RATE ----
                      if (_showCommissionRate) ...[
                        TextFormField(
                          controller: _commissionRateController,
                          style: const TextStyle(color: AppColors.white),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration(
                              'Commission Rate (% of Gross Profit)'),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ---- TAILOR CUT ----
                      if (_showTailorCut) ...[
                        TextFormField(
                          controller: _tailorCutController,
                          style: const TextStyle(color: AppColors.white),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration('Default Tailor Cut (ETB)'),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ---- DELIVERY COMMISSION FIELDS ----
                      if (_showDeliveryFields) ...[
                        DropdownButtonFormField<String>(
                          value: _deliveryCommissionType,
                          dropdownColor: AppColors.backgroundStart,
                          style: const TextStyle(color: AppColors.white),
                          decoration:
                              _inputDecoration('Delivery Commission Type'),
                          items: const [
                            DropdownMenuItem(
                                value: 'fixed', child: Text('Fixed')),
                            DropdownMenuItem(
                                value: 'percentage', child: Text('Percentage')),
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
                              decimal: true),
                          decoration:
                              _inputDecoration('Delivery Commission Value'),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ---- PIN ----
                      TextFormField(
                        controller: _pinController,
                        obscureText: _obscurePin,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.white),
                        decoration: _inputDecoration('6-digit PIN *').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePin
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppColors.white,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePin = !_obscurePin),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter PIN';
                          if (value.length != 6) return 'PIN must be 6 digits';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: AppColors.white,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: AppColors.white)
                              : const Text('Add Employee'),
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