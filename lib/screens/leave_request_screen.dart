import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({Key? key}) : super(key: key);

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? now)
          : (_endDate ?? _startDate ?? now),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both dates')),
      );
      return;
    }
    if (_startDate!.isAfter(_endDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start date must be before end date')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? 'unknown';
      final userName = prefs.getString('userName') ?? 'Employee';

      await DatabaseHelper().insertLeaveRequest(
        employeeId: userId,
        employeeName: userName,
        startDate: _startDate!.millisecondsSinceEpoch,
        endDate: _endDate!.millisecondsSinceEpoch,
        reason: _reasonController.text.trim(),
        notes: _notesController.text.trim(),
      );

      await SyncService().syncAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leave request submitted')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // Start date
                ListTile(
                  title: const Text('Start Date',
                      style: TextStyle(color: AppColors.white)),
                  subtitle: Text(
                    _startDate == null
                        ? 'Tap to select'
                        : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                    style: const TextStyle(color: AppColors.white70),
                  ),
                  trailing: const Icon(Icons.calendar_today,
                      color: AppColors.white),
                  onTap: () => _pickDate(true),
                ),
                const SizedBox(height: 12),
                // End date
                ListTile(
                  title: const Text('End Date',
                      style: TextStyle(color: AppColors.white)),
                  subtitle: Text(
                    _endDate == null
                        ? 'Tap to select'
                        : '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                    style: const TextStyle(color: AppColors.white70),
                  ),
                  trailing: const Icon(Icons.calendar_today,
                      color: AppColors.white),
                  onTap: () => _pickDate(false),
                ),
                const SizedBox(height: 16),
                // Reason
                TextFormField(
                  controller: _reasonController,
                  maxLines: 3,
                  style: const TextStyle(color: AppColors.white),
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    labelStyle: TextStyle(color: AppColors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                // Notes
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.white),
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    labelStyle: TextStyle(color: AppColors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Submit button
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: AppColors.white)
                      : const Text('Submit Request',
                          style: TextStyle(color: AppColors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


