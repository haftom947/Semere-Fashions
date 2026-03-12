import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({Key? key}) : super(key: key);

  @override
  _AddEmployeeScreenState createState() => _AddEmployeeScreenState();
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

  String _selectedRole = 'sales';
  String? _selectedBranchId;
  bool _isLoading = false;
  bool _obscurePin = true;

  String _deliveryCommissionType = 'fixed';

  final List<String> _roles = ['admin', 'manager', 'sales', 'tailor', 'delivery'];
  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    var branches = await _dbHelper.query('branches');
    setState(() {
      _branches = branches.map((b) => {'id': b['id'], 'name': b['name']}).toList();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String pin = _pinController.text.trim();
      String email = 'pin$pin@semere.local';

      // Create Firebase Auth account
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pin);

      String uid = userCredential.user!.uid;

      Map<String, dynamic> userData = {
        'id': uid,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _selectedRole,
        'branchId': _selectedBranchId,
        'employmentType': 'permanent',
        'status': 'active',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };

      // Add role-specific fields
      if (_selectedRole == 'sales') {
        userData['commissionRate'] = double.tryParse(_commissionRateController.text) ?? 0.0;
      } else if (_selectedRole == 'tailor') {
        userData['tailorCut'] = double.tryParse(_tailorCutController.text) ?? 0.0;
      } else if (_selectedRole == 'delivery') {
        userData['delivery_commission_type'] = _deliveryCommissionType;
        userData['delivery_commission_value'] = double.tryParse(_deliveryCommissionController.text) ?? 0.0;
      }

      await _dbHelper.insert('users', userData);

      // Trigger sync if online
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee added successfully!')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to create employee';
      if (e.code == 'email-already-in-use') {
        message = 'PIN already in use';
      } else if (e.code == 'weak-password') {
        message = 'PIN too weak (use 6 digits)';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        items: _roles.map<DropdownMenuItem<String>>((role) => DropdownMenuItem<String>(
                          value: role,
                          child: Text(role.toUpperCase()),
                        )).toList(),
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
                        items: _branches.map<DropdownMenuItem<String>>((branch) => DropdownMenuItem<String>(
                          value: branch['id'] as String,
                          child: Text(branch['name']),
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

                      // PIN field
                      TextFormField(
                        controller: _pinController,
                        obscureText: _obscurePin,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: '6-digit PIN *',
                          labelStyle: const TextStyle(color: AppColors.white),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePin ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.white,
                            ),
                            onPressed: () => setState(() => _obscurePin = !_obscurePin),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter PIN';
                          if (value.length != 6) return 'PIN must be 6 digits';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Submit button
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
                              ? const CircularProgressIndicator(color: AppColors.white)
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