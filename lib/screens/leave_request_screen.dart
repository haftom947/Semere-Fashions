import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({Key? key}) : super(key: key);

  @override
  _LeaveRequestScreenState createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  String? _employeeId;
  String? _employeeName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  Future<void> _loadEmployeeData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var employee = await _dbHelper.queryById('users', user.uid);
      if (employee != null) {
        setState(() {
          _employeeId = user.uid;
          _employeeName = employee['name'];
        });
      }
    }
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    if (_startDate == null) {
      ErrorHandler.showError(context, 'Please select start date first');
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate!.add(const Duration(days: 1)),
      firstDate: _startDate!.add(const Duration(days: 1)),
      lastDate: _startDate!.add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_employeeId == null) {
      ErrorHandler.showError(context, 'User not authenticated');
      return;
    }
    if (_startDate == null || _endDate == null) {
      ErrorHandler.showError(context, 'Please select dates');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _dbHelper.insert('leave_requests', {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'employeeId': _employeeId,
        'employeeName': _employeeName,
        'startDate': _startDate!.millisecondsSinceEpoch,
        'endDate': _endDate!.millisecondsSinceEpoch,
        'reason': _reasonController.text.trim(),
        'notes': _notesController.text.trim(),
        'status': 'pending',
      });

      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        _syncService.syncAll();
      }

      if (mounted) {
        ErrorHandler.showSuccess(context, 'Leave request submitted');
        Navigator.pop(context);
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
        title: const Text('Request Leave'),
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
                      // Start date
                      ListTile(
                        title: Text(
                          _startDate == null
                              ? 'Start Date *'
                              : 'Start: ${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                          style: const TextStyle(color: AppColors.white),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_today, color: AppColors.white),
                          onPressed: () => _selectStartDate(context),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // End date
                      ListTile(
                        title: Text(
                          _endDate == null
                              ? 'End Date *'
                              : 'End: ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                          style: const TextStyle(color: AppColors.white),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_today, color: AppColors.white),
                          onPressed: () => _selectEndDate(context),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reason
                      TextFormField(
                        controller: _reasonController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Reason *',
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

                      // Notes (optional)
                      TextFormField(
                        controller: _notesController,
                        style: const TextStyle(color: AppColors.white),
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Additional Notes',
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

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: AppColors.white,
                          ),
                          child: const Text('Submit Request'),
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