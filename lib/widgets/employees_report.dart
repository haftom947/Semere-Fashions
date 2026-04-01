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
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _commissions = [];
  bool _isLoading = true;

  int _activeEmployees = 0;
  double _totalCommissions = 0;
  double _paidCommissions = 0;
  double _pendingCommissions = 0;

  @override
  void initState() {
    super.initState();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _loadData();
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    setState(() {
      _calculateMetrics();
    });
  }

  Future<void> _loadData() async {
    var employees = await _dbHelper.query('users');
    var commissions = await _dbHelper.query('commissions');
    setState(() {
      _employees = employees;
      _commissions = commissions;
      _calculateMetrics();
      _isLoading = false;
    });
  }

  void _calculateMetrics() {
    _activeEmployees = _employees.where((e) => e['status'] == 'active').length;
    _totalCommissions = 0;
    _paidCommissions = 0;
    _pendingCommissions = 0;
    for (var c in _filteredCommissions()) {
      double amt = (c['amount'] as num?)?.toDouble() ?? 0;
      _totalCommissions += amt;
      if (c['status'] == 'paid') {
        _paidCommissions += amt;
      } else {
        _pendingCommissions += amt;
      }
    }
  }

  List<Map<String, dynamic>> _filteredCommissions() {
    final range = AppDateFilter.instance.range;
    if (range == null) return _commissions;
    final start = DateTime(range.start.year, range.start.month, range.start.day)
        .millisecondsSinceEpoch;
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
    return _commissions.where((commission) {
      final paidAt = (commission['paidAt'] as num?)?.toInt();
      final createdAt = (commission['createdAt'] as num?)?.toInt();
      final date = paidAt ?? createdAt ?? 0;
      return date >= start && date <= end;
    }).toList();
  }

  Future<void> _exportPDF() async {
    try {
      final pdf = await PdfGenerator.generateEmployeesReport(
        _employees.length,
        _activeEmployees,
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
      final excel = ExcelGenerator.generateEmployeesReport(
        _employees.length,
        _activeEmployees,
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
                        ? 'All dates'
                        : 'Global filter: ${range.start.day}/${range.start.month}/${range.start.year} - ${range.end.day}/${range.end.month}/${range.end.year}',
                    style: const TextStyle(color: AppColors.white),
                  );
                },
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Total',
                        _employees.length.toString(),
                        Icons.people,
                      ),
                      _buildStatItem(
                        'Active',
                        _activeEmployees.toString(),
                        Icons.person,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Commission Summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSummaryRow('Total', _totalCommissions),
                      _buildSummaryRow(
                        'Paid',
                        _paidCommissions,
                        color: AppColors.success,
                      ),
                      _buildSummaryRow(
                        'Pending',
                        _pendingCommissions,
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Export card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Export Report',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
              ),
            ],
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

  Widget _buildSummaryRow(
    String label,
    double amount, {
    Color color = AppColors.white,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color)),
          Text(
            'ETB ${amount.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
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
              color: color.withOpacity(0.1),
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
