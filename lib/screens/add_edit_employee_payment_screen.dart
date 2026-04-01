import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class AddEditEmployeePaymentScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final Map<String, dynamic>? paymentData;
  const AddEditEmployeePaymentScreen({
    Key? key,
    required this.employeeId,
    required this.employeeName,
    this.paymentData,
  }) : super(key: key);

  @override
  _AddEditEmployeePaymentScreenState createState() =>
      _AddEditEmployeePaymentScreenState();
}

class _AddEditEmployeePaymentScreenState
    extends State<AddEditEmployeePaymentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _monthController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedType = 'salary';
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  final List<String> _types = ['salary', 'advance', 'bonus', 'deduction'];

  @override
  void initState() {
    super.initState();
    if (widget.paymentData != null) {
      _selectedType = widget.paymentData!['type'] ?? 'salary';
      _amountController.text = widget.paymentData!['amount']?.toString() ?? '';
      _monthController.text = widget.paymentData!['month'] ?? '';
      _notesController.text = widget.paymentData!['notes'] ?? '';
      _selectedDate = DateTime.fromMillisecondsSinceEpoch(
        widget.paymentData!['datePaid'],
      );
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id':
            widget.paymentData?['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'employeeId': widget.employeeId,
        'employeeName': widget.employeeName,
        'type': _selectedType,
        'amount': double.tryParse(_amountController.text) ?? 0,
        'month': _monthController.text.trim().isEmpty
            ? null
            : _monthController.text.trim(),
        'datePaid': _selectedDate.millisecondsSinceEpoch,
        'notes': _notesController.text.trim(),
      };
      if (widget.paymentData == null) {
        await _dbHelper.insert('employee_payments', data);
      } else {
        await _dbHelper.update('employee_payments', data);
      }
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }
      if (mounted) Navigator.pop(context);
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
          widget.paymentData == null ? 'Add Payment' : 'Edit Payment',
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
                      // Type dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Payment Type *',
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
                        items: _types
                            .map(
                              (type) => DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedType = value!),
                      ),
                      const SizedBox(height: 16),

                      // Amount
                      TextFormField(
                        controller: _amountController,
                        style: const TextStyle(color: AppColors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Amount (ETB) *',
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

                      // Month (for salary)
                      if (_selectedType == 'salary')
                        TextFormField(
                          controller: _monthController,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Month (YYYY-MM)',
                            labelStyle: const TextStyle(color: AppColors.white),
                            hintText: 'e.g., 2025-03',
                            hintStyle: TextStyle(
                              color: AppColors.white.withOpacity(0.5),
                            ),
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

                      // Date picker
                      ListTile(
                        title: Text(
                          'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                          style: const TextStyle(color: AppColors.white),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.calendar_today,
                            color: AppColors.white,
                          ),
                          onPressed: () => _selectDate(context),
                        ),
                      ),
                      const SizedBox(height: 8),

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
                                  widget.paymentData == null
                                      ? 'Add Payment'
                                      : 'Update Payment',
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
