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
  const EmployeePaymentsScreen({
    Key? key,
    required this.employeeId,
    required this.employeeName,
  }) : super(key: key);

  @override
  _EmployeePaymentsScreenState createState() => _EmployeePaymentsScreenState();
}

class _EmployeePaymentsScreenState extends State<EmployeePaymentsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _filteredPayments = [];
  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _loadPayments();
    _syncService.dataChangedStream.listen((_) {
      _loadPayments();
    });
  }

  Future<void> _loadEmployees() async {
    var employees = await _dbHelper.query('users');
    setState(() {
      _employees = employees;
    });
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    var allPayments = List<Map<String, dynamic>>.from(
      await _dbHelper.query('employee_payments'),
    );
    allPayments.sort(
      (a, b) => (b['datePaid'] as int).compareTo(a['datePaid'] as int),
    );
    setState(() {
      _payments = allPayments;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    var filtered = _payments;

    // Filter by selected employee (if any)
    if (_selectedEmployeeId != null && _selectedEmployeeId!.isNotEmpty) {
      filtered = filtered
          .where((p) => p['employeeId'] == _selectedEmployeeId)
          .toList();
    }

    // Search filter (optional)
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((p) {
        return (p['employeeName'] ?? '').toLowerCase().contains(query) ||
            (p['type'] ?? '').toLowerCase().contains(query) ||
            (p['month'] ?? '').toLowerCase().contains(query);
      }).toList();
    }

    setState(() {
      _filteredPayments = filtered;
    });
  }

  void _filterByEmployee(String? employeeId) {
    setState(() {
      _selectedEmployeeId = employeeId;
      _applyFilters();
    });
  }

  void _search(String query) {
    _applyFilters();
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'salary':
        return AppColors.success;
      case 'advance':
        return AppColors.info;
      case 'bonus':
        return AppColors.accent;
      case 'deduction':
        return AppColors.error;
      default:
        return AppColors.mediumGrey;
    }
  }

  Future<void> _deletePayment(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Delete Payment'),
          content: const Text('Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await _dbHelper.delete('employee_payments', id);
      _loadPayments();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.employeeId.isEmpty
            ? const Text('All Employee Payments')
            : Text('Payments - ${widget.employeeName}'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // Employee selector (only shown when no specific employee is passed)
              if (widget.employeeId.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedEmployeeId,
                    dropdownColor: AppColors.backgroundStart,
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      labelText: 'Filter by Employee',
                      labelStyle: const TextStyle(color: AppColors.white),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.white.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.white),
                      ),
                      filled: true,
                      fillColor: AppColors.white.withOpacity(0.1),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'All Employees',
                          style: TextStyle(color: AppColors.white),
                        ),
                      ),
                      ..._employees.map(
                        (e) => DropdownMenuItem(
                          value: e['id'],
                          child: Text(
                            e['name'] ?? 'Unknown',
                            style: const TextStyle(color: AppColors.white),
                          ),
                        ),
                      ),
                    ],
                    onChanged: _filterByEmployee,
                  ),
                ),
              ],
              // Search field
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by employee, type, or month...',
                    hintStyle: TextStyle(
                      color: AppColors.white.withOpacity(0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.white,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.white.withOpacity(0.1),
                  ),
                  onChanged: _search,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadPayments,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredPayments.isEmpty
              ? const Center(
                  child: Text(
                    'No payment records.',
                    style: TextStyle(color: AppColors.white),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _filteredPayments.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.white, height: 0.5),
                  itemBuilder: (context, index) {
                    var p = _filteredPayments[index];
                    DateTime date = DateTime.fromMillisecondsSinceEpoch(
                      p['datePaid'],
                    );
                    String dateStr = DateFormat('dd/MM/yy').format(date);
                    bool isPositive = p['type'] != 'deduction';
                    double amount = (p['amount'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: _getTypeColor(p['type']),
                        child: Text(
                          p['type'][0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${p['type'].toUpperCase()} · ${p['employeeName']}',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (p['month'] != null)
                            Text(
                              ' · ${p['month']}',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        dateStr,
                        style: TextStyle(
                          color: AppColors.white.withOpacity(0.7),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${isPositive ? '+' : '-'} ETB ${amount.abs().toStringAsFixed(0)}',
                            style: TextStyle(
                              color: isPositive
                                  ? AppColors.success
                                  : AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () => _deletePayment(p['id']),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // When adding a payment from the global view, we need to select an employee first.
          if (widget.employeeId.isEmpty && _selectedEmployeeId == null) {
            ErrorHandler.showWarning(
              context,
              'Please select an employee first',
            );
            return;
          }
          String targetEmployeeId = widget.employeeId.isNotEmpty
              ? widget.employeeId
              : _selectedEmployeeId!;
          String targetEmployeeName = widget.employeeId.isNotEmpty
              ? widget.employeeName
              : _employees.firstWhere(
                      (e) => e['id'] == targetEmployeeId,
                    )['name'] ??
                    'Unknown';

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddEditEmployeePaymentScreen(
                employeeId: targetEmployeeId,
                employeeName: targetEmployeeName,
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
