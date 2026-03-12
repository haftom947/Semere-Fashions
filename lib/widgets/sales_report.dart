import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/database_helper.dart';
import '../services/pdf_generator.dart';
import '../utils/colors.dart';
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
  bool _isLoading = true;

  double _totalRevenue = 0;
  int _totalOrders = 0;
  double _avgOrderValue = 0;
  List<Map<String, dynamic>> _dailyData = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    var orders = await _dbHelper.query('orders');
    setState(() {
      _orders = orders;
      _calculateStats();
      _prepareChartData();
      _isLoading = false;
    });
  }

  void _calculateStats() {
    _totalOrders = _orders.length;
    _totalRevenue = 0;
    for (var o in _orders) {
      _totalRevenue += (o['totalAmount'] as num?)?.toDouble() ?? 0;
    }
    _avgOrderValue = _totalOrders > 0 ? _totalRevenue / _totalOrders : 0;
  }

  void _prepareChartData() {
    Map<String, double> dailyMap = {};
    DateTime now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      DateTime day = now.subtract(Duration(days: i));
      String key = '${day.day}/${day.month}';
      dailyMap[key] = 0;
    }
    for (var o in _orders) {
      int createdAt = o['createdAt'] ?? 0;
      DateTime date = DateTime.fromMillisecondsSinceEpoch(createdAt);
      String key = '${date.day}/${date.month}';
      if (dailyMap.containsKey(key)) {
        dailyMap[key] = dailyMap[key]! + ((o['totalAmount'] as num?)?.toDouble() ?? 0);
      }
    }
    _dailyData = dailyMap.entries.map((e) => {'date': e.key, 'amount': e.value}).toList();
  }

  double _getMaxAmount() {
    if (_dailyData.isEmpty) return 0;
    return _dailyData.map((d) => d['amount'] as double).reduce((a, b) => a > b ? a : b);
  }

  Future<void> _exportPDF() async {
    try {
      final pdf = await PdfGenerator.generateSalesReport(
        _orders,
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

  Future<void> _exportExcel() async {
    // For now, show coming soon
    ErrorHandler.showWarning(context, 'Excel export coming soon');
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
                      _buildStatItem('Orders', _totalOrders.toString(), Icons.shopping_bag),
                      _buildStatItem('Revenue', 'ETB ${_totalRevenue.toStringAsFixed(0)}', Icons.attach_money),
                      _buildStatItem('Avg Order', 'ETB ${_avgOrderValue.toStringAsFixed(0)}', Icons.analytics),
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
                      const Text('Daily Sales (Last 7 days)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                                    toY: (e.value['amount'] as num?)?.toDouble() ?? 0.0,
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
                                      return Text(_dailyData[index]['date']);
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                              ),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: const FlGridData(show: true),
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
                      const Text('Export Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildExportButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
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
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}