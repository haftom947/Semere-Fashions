import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/database_helper.dart';
import '../services/excel_generator.dart';
import '../services/pdf_generator.dart';
import '../utils/colors.dart';
import '../utils/app_date_filter.dart';
import '../utils/error_handler.dart';
import 'package:printing/printing.dart';

class SalesReport extends StatefulWidget {
  const SalesReport({Key? key}) : super(key: key);

  @override
  _SalesReportState createState() => _SalesReportState();
}

class _SalesReportState extends State<SalesReport> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;

  double _totalRevenue = 0;
  int _totalOrders = 0;
  double _avgOrderValue = 0;
  List<Map<String, dynamic>> _dailyData = [];

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
      _calculateStats();
      _prepareChartData();
    });
  }

  Future<void> _loadData() async {
    final orders = await _dbHelper.query('orders');
    final payments = await _dbHelper.query('payment_transaction');
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _payments = payments;
      _calculateStats();
      _prepareChartData();
      _isLoading = false;
    });
  }

  void _calculateStats() {
    final orders = _filteredOrders();
    final payments = _filteredPayments();
    _totalOrders = orders.length;
    _totalRevenue = 0;
    for (var p in payments) {
      final amount = (p['amount'] as num?)?.toDouble() ?? 0;
      if (p['type'] == 'payment') {
        _totalRevenue += amount;
      } else {
        _totalRevenue -= amount;
      }
    }
    _avgOrderValue = _totalOrders > 0 ? _totalRevenue / _totalOrders : 0;
  }

  void _prepareChartData() {
    final range = AppDateFilter.instance.range;
    final payments = _filteredPayments().where((p) => p['type'] == 'payment').toList();
    payments.sort(
      (a, b) =>
          ((a['date'] as num?)?.toInt() ?? 0).compareTo((b['date'] as num?)?.toInt() ?? 0),
    );

    final dailyMap = <String, double>{};
    if (range != null) {
      final startDay = DateTime(range.start.year, range.start.month, range.start.day);
      final endDay = DateTime(range.end.year, range.end.month, range.end.day);
      for (DateTime day = startDay;
          !day.isAfter(endDay);
          day = day.add(const Duration(days: 1))) {
        final key = DateFormat('dd/MM/yy').format(day);
        dailyMap[key] = 0;
      }
    }

    for (var p in payments) {
      if (p['type'] != 'payment') continue;
      int dateMillis = (p['date'] as num?)?.toInt() ?? 0;
      DateTime date = DateTime.fromMillisecondsSinceEpoch(dateMillis);
      String key = DateFormat('dd/MM/yy').format(date);
      if (dailyMap.containsKey(key)) {
        dailyMap[key] =
            dailyMap[key]! + ((p['amount'] as num?)?.toDouble() ?? 0);
      } else if (range == null) {
        dailyMap[key] = (dailyMap[key] ?? 0) + ((p['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    _dailyData = dailyMap.entries
        .map((e) => {'date': e.key, 'amount': e.value})
        .toList();
  }

  double _getMaxAmount() {
    if (_dailyData.isEmpty) return 0;
    return _dailyData
        .map((d) => d['amount'] as double)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<void> _exportPDF() async {
    try {
      final filteredOrders = _filteredOrders();
      final pdf = await PdfGenerator.generateSalesReport(
        filteredOrders,
        _totalRevenue,
        _totalOrders,
        _avgOrderValue,
        _dailyData,
      );
      await Printing.sharePdf(bytes: pdf, filename: 'sales_report.pdf');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'PDF export failed: $e');
    }
  }

  List<Map<String, dynamic>> _filteredOrders() {
    final range = AppDateFilter.instance.range;
    if (range == null) return _orders;
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
    return _orders.where((o) {
      final date = (o['createdAt'] as num?)?.toInt() ?? 0;
      return date >= start && date <= end;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredPayments() {
    final range = AppDateFilter.instance.range;
    if (range == null) return _payments;
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
    return _payments.where((p) {
      final date = (p['date'] as num?)?.toInt() ?? 0;
      return date >= start && date <= end;
    }).toList();
  }

  Future<void> _exportExcel() async {
    try {
      final filteredOrders = _filteredOrders();
      final excel = ExcelGenerator.generateSalesReport(
        filteredOrders,
        _totalRevenue,
        _totalOrders,
        _avgOrderValue,
        _dailyData,
      );
      final now = DateTime.now();
      final fileName = 'sales_report_${now.millisecondsSinceEpoch}.xlsx';
      await Share.shareXFiles([
        XFile.fromData(
          excel,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: fileName,
        ),
      ], text: 'Sales Report');
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
              // Stats cards
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ValueListenableBuilder<DateTimeRange?>(
                        valueListenable: AppDateFilter.instance.rangeNotifier,
                        builder: (context, range, _) {
                          return Text(
                            range == null
                                ? 'All dates'
                                : 'Global filter: ${range.start.day}/${range.start.month}/${range.start.year} - ${range.end.day}/${range.end.month}/${range.end.year}',
                            style: const TextStyle(fontSize: 12, color: AppColors.mediumGrey),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildStatItem(
                        'Orders',
                        _totalOrders.toString(),
                        Icons.shopping_bag,
                      ),
                      _buildStatItem(
                        'Revenue',
                        'ETB ${_totalRevenue.toStringAsFixed(0)}',
                        Icons.attach_money,
                      ),
                      _buildStatItem(
                        'Avg Order',
                        'ETB ${_avgOrderValue.toStringAsFixed(0)}',
                        Icons.analytics,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sales chart
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Payments (Global Range)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: _getMaxAmount() * 1.1,
                            barGroups: _dailyData.asMap().entries.map((e) {
                              return BarChartGroupData(
                                x: e.key,
                                barRods: [
                                  BarChartRodData(
                                    toY:
                                        (e.value['amount'] as num?)
                                            ?.toDouble() ??
                                        0.0,
                                    color: AppColors.primaryRed,
                                    width: 16,
                                  ),
                                ],
                              );
                            }).toList(),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    int index = value.toInt();
                                  if (index >= 0 && index < _dailyData.length) {
                                      return Text(
                                        _dailyData[index]['date'],
                                        style: const TextStyle(
                                          color: AppColors.darkGrey,
                                          fontSize: 10,
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) => Text(
                                    value.toInt().toString(),
                                    style: const TextStyle(
                                      color: AppColors.mediumGrey,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: AppColors.mediumGrey.withOpacity(0.2),
                                strokeWidth: 1,
                              ),
                              getDrawingVerticalLine: (value) => FlLine(
                                color: AppColors.mediumGrey.withOpacity(0.1),
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                          ),
                        ),
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
