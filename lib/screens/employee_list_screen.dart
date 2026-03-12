import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_employee_screen.dart';
import 'edit_employee_screen.dart';
import 'employee_payments_screen.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  _EmployeeListScreenState createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _syncService.dataChangedStream.listen((_) {
      _loadEmployees();
    });
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    try {
      var employees = await _dbHelper.query('users');
      employees.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
      if (mounted) {
        setState(() {
          _employees = employees;
          _filteredEmployees = employees;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, 'Failed to load employees: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterEmployees(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredEmployees = _employees;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredEmployees = _employees.where((e) {
        return (e['name'] ?? '').toLowerCase().contains(lowerQuery) ||
               (e['phone'] ?? '').contains(query) ||
               (e['role'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  Future<String> _getBranchName(String? branchId) async {
    if (branchId == null) return 'None';
    var branch = await _dbHelper.queryById('branches', branchId);
    return branch?['name'] ?? 'Unknown';
  }

  Future<void> _deactivateEmployee(Map<String, dynamic> employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate Employee'),
        content: Text('Are you sure you want to deactivate ${employee['name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deactivate', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        employee['status'] = 'inactive';
        await _dbHelper.update('users', employee);
        if (mounted) {
          _loadEmployees();
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.showError(context, 'Failed to deactivate employee: $e');
        }
      }
    }
  }

  Future<void> _reactivateEmployee(Map<String, dynamic> employee) async {
    try {
      employee['status'] = 'active';
      await _dbHelper.update('users', employee);
      if (mounted) {
        _loadEmployees();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, 'Failed to reactivate employee: $e');
      }
    }
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Are you sure you want to permanently delete ${employee['name']}? This action cannot be undone.'),
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
      try {
        await _dbHelper.delete('users', employee['id']);
        if (mounted) {
          _loadEmployees();
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.showError(context, 'Failed to delete employee: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddEmployeeScreen()),
              ).then((_) {
                if (mounted) {
                  _loadEmployees();
                }
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search employees...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterEmployees,
            ),
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _filteredEmployees.isEmpty
                ? const Center(
                    child: Text('No employees found.', style: TextStyle(color: AppColors.white)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _filteredEmployees.length,
                    separatorBuilder: (_, _) => const Divider(color: AppColors.white, height: 0.5),
                    itemBuilder: (context, index) {
                      var employee = _filteredEmployees[index];
                      return FutureBuilder<String>(
                        future: _getBranchName(employee['branchId']),
                        builder: (context, branchSnapshot) {
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: employee['status'] == 'active'
                                  ? AppColors.primaryRed
                                  : AppColors.mediumGrey,
                              child: Text(
                                (employee['name'] ?? '?')[0].toUpperCase(),
                                style: const TextStyle(color: AppColors.white, fontSize: 14),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    employee['name'] ?? 'Unnamed',
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: employee['status'] == 'active'
                                        ? AppColors.success
                                        : AppColors.error,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    employee['status'] ?? 'inactive',
                                    style: const TextStyle(color: AppColors.white, fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${employee['role']} · ${branchSnapshot.data ?? 'Loading...'}',
                              style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.payment, color: AppColors.info, size: 20),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EmployeePaymentsScreen(
                                          employeeId: employee['id'],
                                          employeeName: employee['name'] ?? '',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: AppColors.primaryRed, size: 20),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditEmployeeScreen(employeeData: employee),
                                      ),
                                    ).then((_) {
                                      if (mounted) {
                                        _loadEmployees();
                                      }
                                    });
                                  },
                                ),
                                if (employee['status'] == 'active')
                                  IconButton(
                                    icon: const Icon(Icons.block, color: AppColors.warning, size: 20),
                                    onPressed: () => _deactivateEmployee(employee),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.refresh, color: AppColors.success, size: 20),
                                    onPressed: () => _reactivateEmployee(employee),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                                  onPressed: () => _deleteEmployee(employee),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}