import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/error_handler.dart';

class RentPaymentScreen extends StatefulWidget {
  final String tenantId;
  final String tenantName;
  final double monthlyRent;
  const RentPaymentScreen({
    super.key,
    required this.tenantId,
    required this.tenantName,
    required this.monthlyRent,
  });

  @override
  _RentPaymentScreenState createState() => _RentPaymentScreenState();
}

class _RentPaymentScreenState extends State<RentPaymentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _monthController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.monthlyRent.toString();
    DateTime now = DateTime.now();
    _monthController.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'tenantId': widget.tenantId,
        'tenantName': widget.tenantName,
        'amount': double.tryParse(_amountController.text) ?? 0,
        'month': _monthController.text.trim(),
        'paidAt': DateTime.now().millisecondsSinceEpoch,
      };
      await _dbHelper.insert('rent_payments', data);
      if (mounted) {
        _syncService.triggerBackgroundSync();
        ErrorHandler.showSuccess(context, 'Rent payment recorded');
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
        title: Text('Record Payment - ${widget.tenantName}'),
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
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
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
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
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
