import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class CheckoutEquipmentScreen extends StatefulWidget {
  final String equipmentId;
  final String equipmentName;
  const CheckoutEquipmentScreen({
    super.key,
    required this.equipmentId,
    required this.equipmentName,
  });

  @override
  _CheckoutEquipmentScreenState createState() =>
      _CheckoutEquipmentScreenState();
}

class _CheckoutEquipmentScreenState extends State<CheckoutEquipmentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  String? _selectedEmployeeId;
  String _selectedEmployeeName = '';
  List<Map<String, dynamic>> _employees = [];
  DateTime _checkoutDate = DateTime.now();
  DateTime? _expectedReturnDate;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    var employees = await _dbHelper.query('users');
    setState(() {
      _employees = employees.where((e) => e['status'] == 'active').toList();
    });
  }

  Future<void> _selectCheckoutDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _checkoutDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked != null) {
      setState(() => _checkoutDate = picked);
    }
  }

  Future<void> _selectExpectedDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _expectedReturnDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked != null) {
      setState(() => _expectedReturnDate = picked);
    }
  }

  Future<void> _checkout() async {
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an employee')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      String id = DateTime.now().millisecondsSinceEpoch.toString();
      Map<String, dynamic> data = {
        'id': id,
        'equipmentId': widget.equipmentId,
        'equipmentName': widget.equipmentName,
        'employeeId': _selectedEmployeeId,
        'employeeName': _selectedEmployeeName,
        'checkoutDate': _checkoutDate.millisecondsSinceEpoch,
        'expectedReturnDate': _expectedReturnDate?.millisecondsSinceEpoch,
        'notes': _notesController.text.trim(),
      };
      await _dbHelper.insert('checkout_logs', data);
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Checkout ${widget.equipmentName}'),
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
                // Employee dropdown
                DropdownButtonFormField<String>(
                  initialValue: null,
                  dropdownColor: AppColors.backgroundStart,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    labelText: 'Select Employee *',
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
                  items: _employees
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e['id'],
                          child: Text(e['name'] ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    var selected = _employees.firstWhere(
                      (e) => e['id'] == value,
                    );
                    setState(() {
                      _selectedEmployeeId = value;
                      _selectedEmployeeName = selected['name'] ?? '';
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Checkout date
                ListTile(
                  title: Text(
                    'Checkout Date: ${_checkoutDate.day}/${_checkoutDate.month}/${_checkoutDate.year}',
                    style: const TextStyle(color: AppColors.white),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.calendar_today,
                      color: AppColors.white,
                    ),
                    onPressed: () => _selectCheckoutDate(context),
                  ),
                ),
                const SizedBox(height: 8),

                // Expected return date (optional)
                ListTile(
                  title: Text(
                    _expectedReturnDate == null
                        ? 'Expected Return: (optional)'
                        : 'Expected: ${_expectedReturnDate!.day}/${_expectedReturnDate!.month}/${_expectedReturnDate!.year}',
                    style: const TextStyle(color: AppColors.white),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.calendar_today,
                      color: AppColors.white,
                    ),
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

                // Checkout button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _checkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: AppColors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: AppColors.white,
                          )
                        : const Text('Checkout'),
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
