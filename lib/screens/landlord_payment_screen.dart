import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class LandlordPaymentScreen extends StatefulWidget {
  final String propertyId;
  final String propertyName;
  final String landlordName;
  final double monthlyRent;

  const LandlordPaymentScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
    required this.landlordName,
    required this.monthlyRent,
  });

  @override
  State<LandlordPaymentScreen> createState() => _LandlordPaymentScreenState();
}

class _LandlordPaymentScreenState extends State<LandlordPaymentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _monthController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.monthlyRent.toString();
    final now = DateTime.now();
    _monthController.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final paymentAmount = double.tryParse(_amountController.text) ?? 0;
      final paymentMonth = _monthController.text.trim();
      final data = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'propertyId': widget.propertyId,
        'landlordName': widget.landlordName,
        'amount': paymentAmount,
        'month': paymentMonth,
        'paidAt': DateTime.now().millisecondsSinceEpoch,
        'notes': _notesController.text.trim(),
      };
      await _dbHelper.insert('landlord_payments', data);

      if (paymentAmount > 0) {
        final matchingDues = await _dbHelper.queryWhere(
          'landlord_dues',
          'propertyId = ? AND dueMonth = ? AND status = ?',
          [widget.propertyId, paymentMonth, 'pending'],
        );

        for (final due in matchingDues) {
          final dueId = due['id']?.toString();
          if (dueId == null || dueId.isEmpty) continue;
          await _dbHelper.update('landlord_dues', {
            'id': dueId,
            'status': 'paid',
          });
        }
      }

      _syncService.triggerBackgroundSync();
      if (mounted) {
        ErrorHandler.showSuccess(context, 'Landlord payment recorded');
        Navigator.pop(context, true);
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
        title: Text('Pay Landlord - ${widget.propertyName}'),
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
                  controller: _monthController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    labelText: 'Month (YYYY-MM) *',
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
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  style: const TextStyle(color: AppColors.white),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount Paid (ETB) *',
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
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  style: const TextStyle(color: AppColors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
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
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: AppColors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: AppColors.white,
                          )
                        : const Text('Record Payment'),
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
