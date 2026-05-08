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
  State<EmployeePaymentsScreen> createState() => _EmployeePaymentsScreenState();
}

class _EmployeePaymentsScreenState extends State<EmployeePaymentsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _filteredPayments = [];
  List<Map<String, dynamic>> _employees = [];
  String? _selectedEmployeeId;
  bool _isLoading = true;
  DateTime _selectedSalaryMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

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
    final employees = await _dbHelper.query('users');
    if (!mounted) return;
    setState(() {
      _employees = employees;
    });
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    final allPayments = List<Map<String, dynamic>>.from(
      await _dbHelper.query('employee_payments'),
    )..sort(
        (a, b) => ((b['datePaid'] as num?)?.toInt() ?? 0).compareTo(
          (a['datePaid'] as num?)?.toInt() ?? 0,
        ),
      );
    if (!mounted) return;
    setState(() {
      _payments = allPayments;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    var filtered = _payments;

    if (_selectedEmployeeId != null && _selectedEmployeeId!.isNotEmpty) {
      filtered = filtered
          .where((p) => p['employeeId']?.toString() == _selectedEmployeeId)
          .toList();
    }

    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((p) {
        return (p['employeeName'] ?? '').toString().toLowerCase().contains(
                  query,
                ) ||
            (p['type'] ?? '').toString().toLowerCase().contains(query) ||
            (p['month'] ?? '').toString().toLowerCase().contains(query) ||
            (p['for_month'] ?? '').toString().toLowerCase().contains(query) ||
            (p['status'] ?? '').toString().toLowerCase().contains(query);
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

  Future<void> _pickSalaryMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedSalaryMonth,
      firstDate: DateTime(2020, 1),
      lastDate: DateTime(2100, 12),
      builder: (context, child) =>
          Theme(data: ThemeData.light(), child: child!),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedSalaryMonth = DateTime(picked.year, picked.month);
    });
  }

  Future<void> _generateMonthlySalaries() async {
    await _pickSalaryMonth();
    if (!mounted) return;

    final monthKey = DateFormat('yyyy-MM').format(_selectedSalaryMonth);
    try {
      final employees = await _dbHelper.generateMonthlySalaries(monthKey);
      await _loadPayments();
      _syncService.triggerBackgroundSync();
      if (!mounted) return;
      final monthLabel = DateFormat('MMMM y').format(_selectedSalaryMonth);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Generated ${employees.length} salary entr${employees.length == 1 ? 'y' : 'ies'} for $monthLabel.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(context, 'Failed to generate salaries: $e');
    }
  }

  void _openPaymentEditor({
    required String employeeId,
    required String employeeName,
    Map<String, dynamic>? paymentData,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditEmployeePaymentScreen(
          employeeId: employeeId,
          employeeName: employeeName,
          paymentData: paymentData,
        ),
      ),
    ).then((_) => _loadPayments());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.employeeId.isEmpty
            ? const Text('All Employee Payments')
            : Text('Payments - ${widget.employeeName}'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Generate monthly salaries',
            onPressed: _generateMonthlySalaries,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(148),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Salary month: ${DateFormat('MMMM y').format(_selectedSalaryMonth)}',
                        style: const TextStyle(color: AppColors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: _pickSalaryMonth,
                      child: const Text('Change Month'),
                    ),
                  ],
                ),
              ),
              if (widget.employeeId.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedEmployeeId,
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
                          value: e['id']?.toString(),
                          child: Text(
                            e['name']?.toString() ?? 'Unknown',
                            style: const TextStyle(color: AppColors.white),
                          ),
                        ),
                      ),
                    ],
                    onChanged: _filterByEmployee,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by employee, type, month, or status...',
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
                    final payment = _filteredPayments[index];
                    final date = DateTime.fromMillisecondsSinceEpoch(
                      (payment['datePaid'] as num?)?.toInt() ?? 0,
                    );
                    final dateStr = DateFormat('dd/MM/yy').format(date);
                    final isPositive = payment['type'] != 'deduction';
                    final amount =
                        (payment['amount'] as num?)?.toDouble() ?? 0.0;
                    final monthLabel =
                        payment['for_month']?.toString() ??
                        payment['month']?.toString();
                    final status = (payment['status'] ?? 'paid').toString();

                    return ListTile(
                      onTap: () => _openPaymentEditor(
                        employeeId: payment['employeeId']?.toString() ?? '',
                        employeeName:
                            payment['employeeName']?.toString() ?? 'Unknown',
                        paymentData: payment,
                      ),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: _getTypeColor(
                          payment['type']?.toString() ?? '',
                        ),
                        child: Text(
                          (payment['type']?.toString().isNotEmpty ?? false)
                              ? payment['type']
                                  .toString()[0]
                                  .toUpperCase()
                              : '?',
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
                              '${(payment['type'] ?? '').toString().toUpperCase()} • ${payment['employeeName']}',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (monthLabel != null && monthLabel.isNotEmpty)
                            Text(
                              ' • $monthLabel',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            dateStr,
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: status == 'pending'
                                  ? AppColors.warning
                                  : AppColors.success,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
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
                            onPressed: () =>
                                _deletePayment(payment['id'].toString()),
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
          if (widget.employeeId.isEmpty && _selectedEmployeeId == null) {
            ErrorHandler.showWarning(
              context,
              'Please select an employee first',
            );
            return;
          }
          final targetEmployeeId = widget.employeeId.isNotEmpty
              ? widget.employeeId
              : _selectedEmployeeId!;
          final targetEmployeeName = widget.employeeId.isNotEmpty
              ? widget.employeeName
              : _employees.firstWhere(
                      (e) => e['id']?.toString() == targetEmployeeId,
                    )['name'] ??
                    'Unknown';

          _openPaymentEditor(
            employeeId: targetEmployeeId,
            employeeName: targetEmployeeName.toString(),
          );
        },
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add),
      ),
    );
  }
}
