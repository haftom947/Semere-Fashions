import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_helper.dart';
import '../services/excel_generator.dart';
import '../services/pdf_generator.dart';
import '../utils/app_date_filter.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class EmployeesReport extends StatefulWidget {
  const EmployeesReport({Key? key}) : super(key: key);

  @override
  _EmployeesReportState createState() => _EmployeesReportState();
}

class _EmployeesReportState extends State<EmployeesReport> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  String _selectedBranchId = 'all';
  String _selectedRole = 'all';
  String _selectedEmployeeId = 'all';
  String _selectedCurrency = 'all';
  String _sortBy = 'commission';
  bool _compareMode = false;

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  List<Map<String, dynamic>> _commissions = [];
  List<Map<String, dynamic>> _orders = [];

  bool _isLoading = true;

  double _totalSales = 0.0;
  double _totalCommissions = 0.0;
  double _paidCommissions = 0.0;
  double _pendingCommissions = 0.0;
  List<_EmployeeSection> _currencySections = [];

  _EmployeeMetrics? _previousMetrics;

  @override
  void initState() {
    super.initState();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _loadData();
    _loadBranches();
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    setState(() {
      _loadEmployeePerformance();
    });
  }

  Future<void> _loadBranches() async {
    final branches = await _dbHelper.query('branches');
    if (!mounted) return;
    setState(() {
      _branches = List<Map<String, dynamic>>.from(branches);
    });
  }

  Future<void> _loadData() async {
    final employees = await _dbHelper.query('users');
    final commissions = await _dbHelper.query('commissions');
    final orders = await _dbHelper.query('orders');
    if (!mounted) return;
    setState(() {
      _employees = List<Map<String, dynamic>>.from(employees);
      _commissions = List<Map<String, dynamic>>.from(commissions);
      _orders = List<Map<String, dynamic>>.from(orders);
      _loadEmployeePerformance();
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> _availableEmployeesForFilter() {
    return _employees.where((employee) {
      if (_selectedRole != 'all' &&
          employee['role']?.toString() != _selectedRole) {
        return false;
      }
      if (_selectedBranchId != 'all' &&
          employee['branchId']?.toString() != _selectedBranchId) {
        return false;
      }
      return true;
    }).toList();
  }

  List<String> _availableCurrencies() {
    final orderCurrencies = _orders
        .map((order) => order['currency']?.toString().trim() ?? '')
        .where((currency) => currency.isNotEmpty);
    final commissionCurrencies = _commissions
        .map((commission) {
          final orderId = commission['orderId']?.toString();
          if (orderId == null || orderId.isEmpty) return '';
          final order = _orders.firstWhere(
            (candidate) => candidate['id']?.toString() == orderId,
            orElse: () => <String, dynamic>{},
          );
          return order['currency']?.toString().trim() ?? '';
        })
        .where((currency) => currency.isNotEmpty);
    return {...orderCurrencies, ...commissionCurrencies}.toList()..sort();
  }

  void _loadEmployeePerformance() {
    if (_selectedCurrency == 'all') {
      _currencySections = _availableCurrencies()
          .map((currency) => _buildEmployeeSection(currency))
          .toList();
      _filteredEmployees = [];
      _totalSales = 0.0;
      _totalCommissions = 0.0;
      _paidCommissions = 0.0;
      _pendingCommissions = 0.0;
      _previousMetrics = null;
      return;
    }

    _currencySections = [];
    final section = _buildEmployeeSection(_selectedCurrency);
    _filteredEmployees = section.employees;
    _totalSales = section.totalSales;
    _totalCommissions = section.totalCommissions;
    _paidCommissions = section.paidCommissions;
    _pendingCommissions = section.pendingCommissions;

    final range = AppDateFilter.instance.range;
    _previousMetrics = null;
    if (_compareMode && range != null) {
      final currentStart = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final currentEnd = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      );
      final duration = currentEnd.difference(currentStart);
      final previousEnd = currentStart.subtract(const Duration(milliseconds: 1));
      final previousStart = previousEnd.subtract(duration);
      _previousMetrics = _buildPreviousMetrics(
        previousStart.millisecondsSinceEpoch,
        previousEnd.millisecondsSinceEpoch,
        _selectedCurrency,
      );
    }
  }

  _EmployeeSection _buildEmployeeSection(String currency) {
    final range = AppDateFilter.instance.range;
    final (startMillis, endMillis) = _resolveRange(range);
    final branchNames = <String, String>{
      for (final branch in _branches)
        if ((branch['id']?.toString() ?? '').isNotEmpty)
          branch['id'].toString():
              branch['name']?.toString() ?? branch['id'].toString(),
    };

    final availableEmployees = _availableEmployeesForFilter();
    if (_selectedEmployeeId != 'all' &&
        !availableEmployees.any(
          (employee) => employee['id']?.toString() == _selectedEmployeeId,
        )) {
      _selectedEmployeeId = 'all';
    }

    debugPrint(
      'EmployeesReport selected employee filter: $_selectedEmployeeId, currency: $currency',
    );

    final relevantEmployees = availableEmployees.where((employee) {
      if (_selectedEmployeeId != 'all' &&
          employee['id']?.toString() != _selectedEmployeeId) {
        return false;
      }
      return true;
    }).map((employee) {
      final employeeBranchId = employee['branchId']?.toString() ?? '';
      return {
        ...Map<String, dynamic>.from(employee),
        'branchName': branchNames[employeeBranchId] ?? employeeBranchId,
        'totalSales': 0.0,
        'commissionEarned': 0.0,
        'commissionPaid': 0.0,
        'commissionPending': 0.0,
      };
    }).toList();

    final employeeMap = <String, Map<String, dynamic>>{
      for (final employee in relevantEmployees)
        if ((employee['id']?.toString() ?? '').isNotEmpty)
          employee['id'].toString(): employee,
    };

    for (final order in _orders) {
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      if (status == 'cancelled') continue;
      final createdAt = (order['createdAt'] as num?)?.toInt() ?? 0;
      if (createdAt < startMillis || createdAt > endMillis) continue;
      if (_selectedBranchId != 'all' &&
          order['branchId']?.toString() != _selectedBranchId) {
        continue;
      }
      if (order['currency']?.toString() != currency) continue;

      final salesPersonId = order['salesPersonId']?.toString();
      if (salesPersonId == null || salesPersonId.isEmpty) continue;
      if (_selectedEmployeeId != 'all' && salesPersonId != _selectedEmployeeId) {
        continue;
      }
      final employee = employeeMap[salesPersonId];
      if (employee == null) continue;
      employee['totalSales'] = (employee['totalSales'] as double) +
          ((order['totalAmount'] as num?)?.toDouble() ?? 0.0);
    }

    for (final commission in _commissions) {
      final status = commission['status']?.toString() ?? '';
      if (status == 'voided') continue;
      final employeeId = commission['employeeId']?.toString();
      if (employeeId == null || employeeId.isEmpty) continue;
      if (_selectedEmployeeId != 'all' && employeeId != _selectedEmployeeId) {
        continue;
      }
      final orderId = commission['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) continue;
      final order = _orders.firstWhere(
        (candidate) => candidate['id']?.toString() == orderId,
        orElse: () => <String, dynamic>{},
      );
      if (order['currency']?.toString() != currency) continue;
      final employee = employeeMap[employeeId];
      if (employee == null) continue;

      final date = ((commission['paidAt'] as num?)?.toInt()) ??
          ((commission['createdAt'] as num?)?.toInt()) ??
          0;
      if (date < startMillis || date > endMillis) continue;

      final amount = (commission['amount'] as num?)?.toDouble() ?? 0.0;
      employee['commissionEarned'] =
          (employee['commissionEarned'] as double) + amount;
      if (status == 'paid') {
        employee['commissionPaid'] =
            (employee['commissionPaid'] as double) + amount;
      } else if (status == 'pending') {
        employee['commissionPending'] =
            (employee['commissionPending'] as double) + amount;
      }
    }

    var filtered = employeeMap.values.toList();
    _sortEmployees(_sortBy, employees: filtered, updateState: false);

    final totalSales = filtered.fold<double>(
      0.0,
      (sum, employee) => sum + ((employee['totalSales'] as num?)?.toDouble() ?? 0.0),
    );
    final totalCommissions = filtered.fold<double>(
      0.0,
      (sum, employee) =>
          sum + ((employee['commissionEarned'] as num?)?.toDouble() ?? 0.0),
    );
    final paidCommissions = filtered.fold<double>(
      0.0,
      (sum, employee) =>
          sum + ((employee['commissionPaid'] as num?)?.toDouble() ?? 0.0),
    );
    final pendingCommissions = filtered.fold<double>(
      0.0,
      (sum, employee) =>
          sum + ((employee['commissionPending'] as num?)?.toDouble() ?? 0.0),
    );
    return _EmployeeSection(
      currency: currency,
      employees: filtered,
      totalSales: totalSales,
      totalCommissions: totalCommissions,
      paidCommissions: paidCommissions,
      pendingCommissions: pendingCommissions,
    );
  }

  _EmployeeMetrics _buildPreviousMetrics(
    int startMillis,
    int endMillis,
    String currency,
  ) {
    final branchNames = <String, String>{
      for (final branch in _branches)
        if ((branch['id']?.toString() ?? '').isNotEmpty)
          branch['id'].toString():
              branch['name']?.toString() ?? branch['id'].toString(),
    };
    final availableEmployees = _availableEmployeesForFilter();
    final relevantEmployees = availableEmployees.where((employee) {
      if (_selectedEmployeeId != 'all' &&
          employee['id']?.toString() != _selectedEmployeeId) {
        return false;
      }
      return true;
    }).map((employee) {
      final employeeBranchId = employee['branchId']?.toString() ?? '';
      return {
        ...Map<String, dynamic>.from(employee),
        'branchName': branchNames[employeeBranchId] ?? employeeBranchId,
        'totalSales': 0.0,
        'commissionEarned': 0.0,
        'commissionPaid': 0.0,
        'commissionPending': 0.0,
      };
    }).toList();

    final employeeMap = <String, Map<String, dynamic>>{
      for (final employee in relevantEmployees)
        if ((employee['id']?.toString() ?? '').isNotEmpty)
          employee['id'].toString(): employee,
    };

    for (final order in _orders) {
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      if (status == 'cancelled') continue;
      final createdAt = (order['createdAt'] as num?)?.toInt() ?? 0;
      if (createdAt < startMillis || createdAt > endMillis) continue;
      if (_selectedBranchId != 'all' &&
          order['branchId']?.toString() != _selectedBranchId) {
        continue;
      }
      if (order['currency']?.toString() != currency) continue;
      final salesPersonId = order['salesPersonId']?.toString();
      if (salesPersonId == null || salesPersonId.isEmpty) continue;
      if (_selectedEmployeeId != 'all' && salesPersonId != _selectedEmployeeId) {
        continue;
      }
      final employee = employeeMap[salesPersonId];
      if (employee == null) continue;
      employee['totalSales'] = (employee['totalSales'] as double) +
          ((order['totalAmount'] as num?)?.toDouble() ?? 0.0);
    }

    for (final commission in _commissions) {
      final status = commission['status']?.toString() ?? '';
      if (status == 'voided') continue;
      final employeeId = commission['employeeId']?.toString();
      if (employeeId == null || employeeId.isEmpty) continue;
      if (_selectedEmployeeId != 'all' && employeeId != _selectedEmployeeId) {
        continue;
      }
      final orderId = commission['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) continue;
      final order = _orders.firstWhere(
        (candidate) => candidate['id']?.toString() == orderId,
        orElse: () => <String, dynamic>{},
      );
      if (order['currency']?.toString() != currency) continue;
      final employee = employeeMap[employeeId];
      if (employee == null) continue;

      final date = ((commission['paidAt'] as num?)?.toInt()) ??
          ((commission['createdAt'] as num?)?.toInt()) ??
          0;
      if (date < startMillis || date > endMillis) continue;

      final amount = (commission['amount'] as num?)?.toDouble() ?? 0.0;
      employee['commissionEarned'] =
          (employee['commissionEarned'] as double) + amount;
      if (status == 'paid') {
        employee['commissionPaid'] =
            (employee['commissionPaid'] as double) + amount;
      } else if (status == 'pending') {
        employee['commissionPending'] =
            (employee['commissionPending'] as double) + amount;
      }
    }

    final employees = employeeMap.values.toList();
    return _EmployeeMetrics(
      totalSales: employees.fold<double>(
        0.0,
        (sum, employee) => sum + ((employee['totalSales'] as num?)?.toDouble() ?? 0.0),
      ),
      totalCommissions: employees.fold<double>(
        0.0,
        (sum, employee) =>
            sum + ((employee['commissionEarned'] as num?)?.toDouble() ?? 0.0),
      ),
      paidCommissions: employees.fold<double>(
        0.0,
        (sum, employee) =>
            sum + ((employee['commissionPaid'] as num?)?.toDouble() ?? 0.0),
      ),
      pendingCommissions: employees.fold<double>(
        0.0,
        (sum, employee) =>
            sum + ((employee['commissionPending'] as num?)?.toDouble() ?? 0.0),
      ),
    );
  }

  (int, int) _resolveRange(DateTimeRange? range) {
    if (range == null) {
      return (0, DateTime.now().millisecondsSinceEpoch);
    }
    return (
      DateTime(range.start.year, range.start.month, range.start.day)
          .millisecondsSinceEpoch,
      DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch,
    );
  }

  void _sortEmployees(
    String field, {
    List<Map<String, dynamic>>? employees,
    bool updateState = true,
  }) {
    final target = employees ?? List<Map<String, dynamic>>.from(_filteredEmployees);

    int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (field) {
        case 'sales':
          return ((b['totalSales'] as num?)?.toDouble() ?? 0.0).compareTo(
            (a['totalSales'] as num?)?.toDouble() ?? 0.0,
          );
        case 'paid':
          return ((b['commissionPaid'] as num?)?.toDouble() ?? 0.0).compareTo(
            (a['commissionPaid'] as num?)?.toDouble() ?? 0.0,
          );
        case 'pending':
          return ((b['commissionPending'] as num?)?.toDouble() ?? 0.0)
              .compareTo(
                (a['commissionPending'] as num?)?.toDouble() ?? 0.0,
              );
        case 'name':
          return (a['name']?.toString() ?? '').compareTo(
            b['name']?.toString() ?? '',
          );
        case 'commission':
        default:
          return ((b['commissionEarned'] as num?)?.toDouble() ?? 0.0)
              .compareTo(
                (a['commissionEarned'] as num?)?.toDouble() ?? 0.0,
              );
      }
    }

    target.sort(compare);

    if (updateState && mounted) {
      setState(() {
        _sortBy = field;
        _filteredEmployees = target;
        _totalSales = target.fold<double>(
          0.0,
          (sum, employee) =>
              sum + ((employee['totalSales'] as num?)?.toDouble() ?? 0.0),
        );
        _totalCommissions = target.fold<double>(
          0.0,
          (sum, employee) => sum +
              ((employee['commissionEarned'] as num?)?.toDouble() ?? 0.0),
        );
        _paidCommissions = target.fold<double>(
          0.0,
          (sum, employee) =>
              sum + ((employee['commissionPaid'] as num?)?.toDouble() ?? 0.0),
        );
        _pendingCommissions = target.fold<double>(
          0.0,
          (sum, employee) => sum +
              ((employee['commissionPending'] as num?)?.toDouble() ?? 0.0),
        );
      });
    }
  }

  String? _percentageChange(double current, double previous) {
    if (!_compareMode || _previousMetrics == null) return null;
    if (current == 0 && previous == 0) return '0%';
    if (previous == 0) return '+100%';
    final change = ((current - previous) / previous) * 100;
    final prefix = change > 0 ? '+' : '';
    return '$prefix${change.toStringAsFixed(0)}%';
  }

  Color _changeColor(String? change) {
    if (change == null) return AppColors.mediumGrey;
    if (change == '0%') return AppColors.mediumGrey;
    return change.startsWith('-') ? AppColors.error : AppColors.success;
  }

  Future<void> _exportPDF() async {
    try {
      final activeEmployees =
          _filteredEmployees.where((employee) => employee['status'] == 'active').length;
      final pdf = await PdfGenerator.generateEmployeesReport(
        _filteredEmployees.length,
        activeEmployees,
        _totalCommissions,
        _paidCommissions,
        _pendingCommissions,
      );
      await Printing.sharePdf(bytes: pdf, filename: 'employees_report.pdf');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'PDF export failed: $e');
    }
  }

  Future<void> _exportExcel() async {
    try {
      final activeEmployees =
          _filteredEmployees.where((employee) => employee['status'] == 'active').length;
      final excel = ExcelGenerator.generateEmployeesReport(
        _filteredEmployees.length,
        activeEmployees,
        _totalCommissions,
        _paidCommissions,
        _pendingCommissions,
      );
      final now = DateTime.now();
      final fileName = 'employees_report_${now.millisecondsSinceEpoch}.xlsx';
      await Share.shareXFiles([
        XFile.fromData(
          excel,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: fileName,
        ),
      ], text: 'Employees Report');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Excel export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ValueListenableBuilder<DateTimeRange?>(
                valueListenable: AppDateFilter.instance.rangeNotifier,
                builder: (context, range, _) {
                  return Text(
                    range == null
                        ? 'Global filter: All dates'
                        : 'Global filter: ${range.start.day}/${range.start.month}/${range.start.year} - ${range.end.day}/${range.end.month}/${range.end.year}',
                    style: const TextStyle(color: AppColors.white),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildFilterCard(),
              const SizedBox(height: 16),
              _buildKpiCard(),
              const SizedBox(height: 16),
              _buildEmployeeTable(),
              const SizedBox(height: 16),
              _buildExportCard(),
            ],
          );
  }

  Widget _buildFilterCard() {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth < 600
              ? constraints.maxWidth
              : 220.0;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBranchId,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Branches'),
                      ),
                      ..._branches.map(
                        (branch) => DropdownMenuItem<String>(
                          value: branch['id']?.toString() ?? '',
                          child: Text(
                            branch['name']?.toString() ??
                                branch['id']?.toString() ??
                                'Branch',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBranchId = value ?? 'all';
                        _loadEmployeePerformance();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Roles')),
                      DropdownMenuItem(value: 'sales', child: Text('Sales')),
                      DropdownMenuItem(value: 'tailor', child: Text('Tailor')),
                      DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value ?? 'all';
                        _loadEmployeePerformance();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedEmployeeId,
                    decoration: const InputDecoration(
                      labelText: 'Employee',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Employees'),
                      ),
                      ..._availableEmployeesForFilter().map(
                        (employee) => DropdownMenuItem<String>(
                          value: employee['id']?.toString() ?? '',
                          child: Text(
                            employee['name']?.toString() ??
                                employee['id']?.toString() ??
                                'Employee',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedEmployeeId = value ?? 'all';
                        _loadEmployeePerformance();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Currencies'),
                      ),
                      ..._availableCurrencies().map(
                        (currency) => DropdownMenuItem<String>(
                          value: currency,
                          child: Text(currency),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCurrency = value ?? 'all';
                        _loadEmployeePerformance();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _sortBy,
                    decoration: const InputDecoration(
                      labelText: 'Sort By',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'commission', child: Text('Commission')),
                      DropdownMenuItem(value: 'sales', child: Text('Sales')),
                      DropdownMenuItem(value: 'paid', child: Text('Paid')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _sortEmployees(value);
                    },
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _compareMode,
                      onChanged: (value) {
                        setState(() {
                          _compareMode = value;
                          _loadEmployeePerformance();
                        });
                      },
                    ),
                    const Text('Compare'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiCard() {
    if (_selectedCurrency == 'all') {
      return Column(
        children: _currencySections
            .map((section) => _buildEmployeeSectionView(section))
            .toList(),
      );
    }
    final salesChange =
        _percentageChange(_totalSales, _previousMetrics?.totalSales ?? 0.0);
    final commissionChange = _percentageChange(
      _totalCommissions,
      _previousMetrics?.totalCommissions ?? 0.0,
    );
    final paidChange = _percentageChange(
      _paidCommissions,
      _previousMetrics?.paidCommissions ?? 0.0,
    );
    final pendingChange = _percentageChange(
      _pendingCommissions,
      _previousMetrics?.pendingCommissions ?? 0.0,
    );

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              alignment:
                  isNarrow ? WrapAlignment.start : WrapAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Employees',
                  _filteredEmployees.length.toString(),
                  Icons.people,
                ),
                _buildMetric(
                  'Total Sales',
                  'ETB ${_totalSales.toStringAsFixed(0)}',
                  Icons.shopping_bag,
                  salesChange,
                ),
                _buildMetric(
                  'Commissions',
                  'ETB ${_totalCommissions.toStringAsFixed(0)}',
                  Icons.monetization_on,
                  commissionChange,
                ),
                _buildMetric(
                  'Paid',
                  'ETB ${_paidCommissions.toStringAsFixed(0)}',
                  Icons.check_circle,
                  paidChange,
                ),
                _buildMetric(
                  'Pending',
                  'ETB ${_pendingCommissions.toStringAsFixed(0)}',
                  Icons.pending,
                  pendingChange,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmployeeSectionView(_EmployeeSection section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.currency,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 24,
                runSpacing: 16,
                alignment: WrapAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Employees',
                    section.employees.length.toString(),
                    Icons.people,
                  ),
                  _buildMetric(
                    'Total Sales',
                    '${section.currency} ${section.totalSales.toStringAsFixed(0)}',
                    Icons.shopping_bag,
                    null,
                  ),
                  _buildMetric(
                    'Commissions',
                    '${section.currency} ${section.totalCommissions.toStringAsFixed(0)}',
                    Icons.monetization_on,
                    null,
                  ),
                  _buildMetric(
                    'Paid',
                    '${section.currency} ${section.paidCommissions.toStringAsFixed(0)}',
                    Icons.check_circle,
                    null,
                  ),
                  _buildMetric(
                    'Pending',
                    '${section.currency} ${section.pendingCommissions.toStringAsFixed(0)}',
                    Icons.pending,
                    null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildEmployeeTableForSection(section),
        ],
      ),
    );
  }

  Widget _buildMetric(
    String label,
    String value,
    IconData icon,
    String? change,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primaryRed),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          change == null ? 'Current period' : 'vs previous: $change',
          style: TextStyle(
            fontSize: 10,
            color: change == null ? AppColors.mediumGrey : _changeColor(change),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeTable() {
    if (_selectedCurrency == 'all') {
      return const SizedBox.shrink();
    }
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Employee Performance',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_filteredEmployees.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('No employees match the selected filters.'),
                    ),
                  )
                else if (isNarrow)
                  ..._filteredEmployees.map(_buildEmployeeMobileCard)
                else ...[
                  _buildHeaderRow(),
                  const Divider(height: 16),
                  ..._filteredEmployees.map(_buildEmployeeRow),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmployeeTableForSection(_EmployeeSection section) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employee Performance (${section.currency})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (section.employees.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('No employees match the selected filters.'),
                    ),
                  )
                else if (isNarrow)
                  ...section.employees.map(
                    (employee) => _buildEmployeeMobileCard(
                      employee,
                      currency: section.currency,
                    ),
                  )
                else ...[
                  _buildHeaderRow(),
                  const Divider(height: 16),
                  ...section.employees.map(
                    (employee) => _buildEmployeeRow(
                      employee,
                      currency: section.currency,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmployeeMobileCard(Map<String, dynamic> employee, {String? currency}) {
    final code =
        currency ?? (_selectedCurrency == 'all' ? 'ETB' : _selectedCurrency);
    Widget line(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.mediumGrey)),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: valueColor),
              ),
            ),
          ],
        ),
      );
    }

    final branch = employee['branchName']?.toString().isNotEmpty == true
        ? employee['branchName']?.toString() ?? '-'
        : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            employee['name']?.toString() ?? 'Employee',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${employee['role']?.toString() ?? '-'} • $branch',
            style: const TextStyle(color: AppColors.mediumGrey),
          ),
          const SizedBox(height: 8),
          line(
            'Sales',
            '$code ${((employee['totalSales'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
          ),
          line(
            'Commission',
            '$code ${((employee['commissionEarned'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
            valueColor: AppColors.info,
          ),
          line(
            'Paid',
            '$code ${((employee['commissionPaid'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
            valueColor: AppColors.success,
          ),
          line(
            'Pending',
            '$code ${((employee['commissionPending'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
            valueColor: AppColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    Widget header(String label, {int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }

    return Row(
      children: [
        header('Employee', flex: 2),
        header('Role'),
        header('Branch'),
        header('Sales'),
        header('Commission'),
        header('Paid'),
        header('Pending'),
      ],
    );
  }

  Widget _buildEmployeeRow(Map<String, dynamic> employee, {String? currency}) {
    final code =
        currency ?? (_selectedCurrency == 'all' ? 'ETB' : _selectedCurrency);
    Widget cell(String text, {int flex = 1, Color? color}) {
      return Expanded(
        flex: flex,
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          cell(employee['name']?.toString() ?? 'Employee', flex: 2),
          cell(employee['role']?.toString() ?? '-'),
          cell(employee['branchName']?.toString().isNotEmpty == true
              ? employee['branchName']?.toString() ?? '-'
              : '-'),
          cell('$code ${((employee['totalSales'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}'),
          cell(
            '$code ${((employee['commissionEarned'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
            color: AppColors.info,
          ),
          cell(
            '$code ${((employee['commissionPaid'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
            color: AppColors.success,
          ),
          cell(
            '$code ${((employee['commissionPending'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
            color: AppColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildExportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildExportButton(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  color: AppColors.error,
                  onTap: _exportPDF,
                ),
                _buildExportButton(
                  icon: Icons.table_chart,
                  label: 'Excel',
                  color: AppColors.success,
                  onTap: _exportExcel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryRed),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildExportButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _EmployeeMetrics {
  const _EmployeeMetrics({
    required this.totalSales,
    required this.totalCommissions,
    required this.paidCommissions,
    required this.pendingCommissions,
  });

  final double totalSales;
  final double totalCommissions;
  final double paidCommissions;
  final double pendingCommissions;
}

class _EmployeeSection {
  const _EmployeeSection({
    required this.currency,
    required this.employees,
    required this.totalSales,
    required this.totalCommissions,
    required this.paidCommissions,
    required this.pendingCommissions,
  });

  final String currency;
  final List<Map<String, dynamic>> employees;
  final double totalSales;
  final double totalCommissions;
  final double paidCommissions;
  final double pendingCommissions;
}
