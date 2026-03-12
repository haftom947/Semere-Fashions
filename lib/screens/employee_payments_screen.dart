import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_edit_employee_payment_screen.dart';

class EmployeePaymentsScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const EmployeePaymentsScreen({Key? key, required this.employeeId, required this.employeeName}) : super(key: key);

  @override
  _EmployeePaymentsScreenState createState() => _EmployeePaymentsScreenState();
}

class _EmployeePaymentsScreenState extends State<EmployeePaymentsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPayments();
    _syncService.dataChangedStream.listen((_) {
      _loadPayments();
    });
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    var allPayments = await _dbHelper.query('employee_payments');
    var filtered = allPayments.where((p) => p['employeeId'] == widget.employeeId).toList();
    filtered.sort((a, b) => (b['datePaid'] as int).compareTo(a['datePaid'] as int));
    setState(() {
      _payments = filtered;
      _isLoading = false;
    });
  }

  Future<void> _deletePayment(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Payment'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _dbHelper.delete('employee_payments', id);
      _loadPayments();
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'salary': return AppColors.success;
      case 'advance': return AppColors.info;
      case 'bonus': return AppColors.accent;
      case 'deduction': return AppColors.error;
      default: return AppColors.mediumGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Payments - ${widget.employeeName}'),
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
            : _payments.isEmpty
                ? const Center(
                    child: Text('No payment records.', style: TextStyle(color: AppColors.white)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _payments.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                    itemBuilder: (context, index) {
                      var p = _payments[index];
                      DateTime date = DateTime.fromMillisecondsSinceEpoch(p['datePaid']);
                      String dateStr = DateFormat('dd/MM/yy').format(date);
                      bool isPositive = p['type'] != 'deduction';
                      double amount = (p['amount'] as num?)?.toDouble() ?? 0;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: _getTypeColor(p['type']),
                          child: Text(
                            p['type'][0].toUpperCase(),
                            style: const TextStyle(color: AppColors.white, fontSize: 14),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p['type'].toUpperCase(),
                                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (p['month'] != null)
                              Text(
                                ' · ${p['month']}',
                                style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          dateStr,
                          style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${isPositive ? '+' : '-'} ETB ${amount.abs().toStringAsFixed(0)}',
                              style: TextStyle(
                                color: isPositive ? AppColors.success : AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                              onPressed: () => _deletePayment(p['id']),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddEditEmployeePaymentScreen(
                employeeId: widget.employeeId,
                employeeName: widget.employeeName,
              ),
            ),
          ).then((_) => _loadPayments());
        },
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add),
      ),
    );
  }
}