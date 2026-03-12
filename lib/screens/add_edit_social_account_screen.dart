import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class AddEditSocialAccountScreen extends StatefulWidget {
  final Map<String, dynamic>? accountData;
  const AddEditSocialAccountScreen({Key? key, this.accountData}) : super(key: key);

  @override
  _AddEditSocialAccountScreenState createState() => _AddEditSocialAccountScreenState();
}

class _AddEditSocialAccountScreenState extends State<AddEditSocialAccountScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _accountUrlController = TextEditingController();

  String _selectedPlatform = 'TikTok';
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;
  bool _isLoading = false;

  final List<String> _platforms = ['TikTok', 'Instagram', 'Facebook', 'YouTube'];
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    if (widget.accountData != null) {
      _accountNameController.text = widget.accountData!['accountName'] ?? '';
      _accountUrlController.text = widget.accountData!['accountUrl'] ?? '';
      _selectedPlatform = widget.accountData!['platform'] ?? 'TikTok';
      _selectedEmployeeId = widget.accountData!['employeeId'];
      _selectedEmployeeName = widget.accountData!['employeeName'];
    }
  }

  Future<void> _loadEmployees() async {
    var employees = await _dbHelper.query('users');
    setState(() {
      _employees = employees.where((e) => e['status'] == 'active').toList();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id': widget.accountData?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'platform': _selectedPlatform,
        'accountName': _accountNameController.text.trim(),
        'accountUrl': _accountUrlController.text.trim(),
        'employeeId': _selectedEmployeeId,
        'employeeName': _selectedEmployeeName,
      };
      if (widget.accountData == null) {
        await _dbHelper.insert('social_accounts', data);
      } else {
        await _dbHelper.update('social_accounts', data);
      }
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
        title: Text(widget.accountData == null ? 'Add Social Account' : 'Edit Social Account'),
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
                      // Platform dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedPlatform,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Platform *',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: _platforms.map((p) => DropdownMenuItem<String>(
                          value: p,
                          child: Text(p),
                        )).toList(),
                        onChanged: (value) => setState(() => _selectedPlatform = value!),
                      ),
                      const SizedBox(height: 16),

                      // Account Name
                      TextFormField(
                        controller: _accountNameController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Account Name/Handle *',
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

                      // Account URL
                      TextFormField(
                        controller: _accountUrlController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Profile URL',
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

                      // Employee assignment (optional)
                      DropdownButtonFormField<String>(
                        value: _selectedEmployeeId,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Assigned Employee',
                          labelStyle: const TextStyle(color: AppColors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.white),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None (unassigned)'),
                          ),
                          ..._employees.map((e) => DropdownMenuItem<String>(
                            value: e['id'],
                            child: Text(e['name'] ?? 'Unknown'),
                          )),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            setState(() {
                              _selectedEmployeeId = null;
                              _selectedEmployeeName = null;
                            });
                          } else {
                            var emp = _employees.firstWhere((e) => e['id'] == value);
                            setState(() {
                              _selectedEmployeeId = value;
                              _selectedEmployeeName = emp['name'];
                            });
                          }
                        },
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
                              : Text(widget.accountData == null ? 'Add Account' : 'Update Account'),
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