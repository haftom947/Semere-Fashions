import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_helper.dart';
import '../services/excel_generator.dart';
import '../services/pdf_generator.dart';
import '../utils/app_date_filter.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class SalesReport extends StatefulWidget {
  const SalesReport({Key? key}) : super(key: key);

  @override
  _SalesReportState createState() => _SalesReportState();
}

class _SalesReportState extends State<SalesReport> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _salesPeople = [];

  bool _isLoading = true;
  bool _compareMode = false;
  String _selectedBranchId = 'all';
  String _selectedSalesPersonId = 'all';
  String _selectedCurrency = 'all';

  _SalesMetrics _metrics = _SalesMetrics.empty();
  _SalesMetrics? _previousMetrics;
  List<_SalesSection> _currencySections = [];

  @override
  void initState() {
    super.initState();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _loadData();
    _loadBranches();
    _loadSalesPeople();
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    setState(() {
      _recalculateReport();
    });
  }

  Future<void> _loadData() async {
    final orders = await _dbHelper.query('orders');
    final payments = await _dbHelper.query('payment_transaction');
    if (!mounted) return;
    setState(() {
      _orders = List<Map<String, dynamic>>.from(orders);
      _payments = List<Map<String, dynamic>>.from(payments);
      _recalculateReport();
      _isLoading = false;
    });
  }

  List<String> _availableCurrencies() {
    final currencies = _orders
        .map((order) => order['currency']?.toString().trim() ?? '')
        .where((currency) => currency.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return currencies;
  }

  Future<void> _loadBranches() async {
    final branches = await _dbHelper.query('branches');
    if (!mounted) return;
    setState(() {
      _branches = List<Map<String, dynamic>>.from(branches);
    });
  }

  Future<void> _loadSalesPeople() async {
    final users = await _dbHelper.query('users');
    if (!mounted) return;
    setState(() {
      _salesPeople = List<Map<String, dynamic>>.from(
        users.where((user) => user['role'] == 'sales'),
      );
    });
  }

  void _recalculateReport() {
    final range = AppDateFilter.instance.range;
    final currentRange = _resolveRangeBounds(range);
    if (_selectedCurrency == 'all') {
      final currencies = _availableCurrencies();
      _currencySections = currencies
          .map(
            (currency) => _SalesSection(
              currency: currency,
              metrics: _fetchSalesData(
                currentRange.$1,
                currentRange.$2,
                _selectedBranchId,
                _selectedSalesPersonId,
                currency: currency,
              ),
            ),
          )
          .toList();
      _metrics = _SalesMetrics.empty();
      _previousMetrics = null;
      return;
    }

    _currencySections = [];
    _metrics = _fetchSalesData(
      currentRange.$1,
      currentRange.$2,
      _selectedBranchId,
      _selectedSalesPersonId,
      currency: _selectedCurrency,
    );

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
      _previousMetrics = _fetchSalesData(
        previousStart.millisecondsSinceEpoch,
        previousEnd.millisecondsSinceEpoch,
        _selectedBranchId,
        _selectedSalesPersonId,
        currency: _selectedCurrency,
      );
    }
  }

  (int, int) _resolveRangeBounds(DateTimeRange? range) {
    if (range == null) {
      return (0, DateTime.now().millisecondsSinceEpoch);
    }
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    ).millisecondsSinceEpoch;
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
    return (start, end);
  }

  _SalesMetrics _fetchSalesData(
    int startMillis,
    int endMillis,
    String branchId,
    String salesPersonId,
    {String? currency,}
  ) {
    final filteredOrders = _orders.where((order) {
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      if (status == 'cancelled') return false;
      if (branchId != 'all' && order['branchId'] != branchId) return false;
      if (salesPersonId != 'all' && order['salesPersonId'] != salesPersonId) {
        return false;
      }
      if (currency != null && order['currency']?.toString() != currency) {
        return false;
      }
      final createdAt = (order['createdAt'] as num?)?.toInt() ?? 0;
      return createdAt >= startMillis && createdAt <= endMillis;
    }).toList();

    final orderIds = filteredOrders
        .map((order) => order['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final filteredPayments = _payments.where((payment) {
      final orderId = payment['orderId']?.toString() ?? '';
      if (!orderIds.contains(orderId)) return false;
      final date = (payment['date'] as num?)?.toInt() ?? 0;
      return date >= startMillis && date <= endMillis;
    }).toList();

    double totalRevenue = 0.0;
    for (final payment in filteredPayments) {
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      if (payment['type'] == 'payment') {
        totalRevenue += amount;
      } else {
        totalRevenue -= amount;
      }
    }

    final totalOrders = filteredOrders.length;
    final totalOrderValue = filteredOrders.fold<double>(
      0.0,
      (sum, order) => sum + ((order['totalAmount'] as num?)?.toDouble() ?? 0.0),
    );
    final unpaidAmount = totalOrderValue - totalRevenue;
    final avgOrderValue = totalOrders > 0 ? totalOrderValue / totalOrders : 0.0;

    final orderCountByDay = <String, int>{};
    for (final order in filteredOrders) {
      final createdAt = (order['createdAt'] as num?)?.toInt() ?? 0;
      final key = DateFormat(
        'dd/MM/yy',
      ).format(DateTime.fromMillisecondsSinceEpoch(createdAt));
      orderCountByDay[key] = (orderCountByDay[key] ?? 0) + 1;
    }

    final revenueByDay = <String, double>{};
    if (startMillis > 0 || AppDateFilter.instance.range != null) {
      DateTime day = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final endDay = DateTime.fromMillisecondsSinceEpoch(endMillis);
      day = DateTime(day.year, day.month, day.day);
      final normalizedEnd = DateTime(endDay.year, endDay.month, endDay.day);
      while (!day.isAfter(normalizedEnd)) {
        revenueByDay[DateFormat('dd/MM/yy').format(day)] = 0.0;
        day = day.add(const Duration(days: 1));
      }
    }

    for (final payment in filteredPayments) {
      final date = (payment['date'] as num?)?.toInt() ?? 0;
      final key = DateFormat(
        'dd/MM/yy',
      ).format(DateTime.fromMillisecondsSinceEpoch(date));
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      final signedAmount = payment['type'] == 'payment' ? amount : -amount;
      revenueByDay[key] = (revenueByDay[key] ?? 0.0) + signedAmount;
    }

    final dailyData = revenueByDay.entries
        .map(
          (entry) => {
            'date': entry.key,
            'revenue': entry.value,
            'orders': orderCountByDay[entry.key] ?? 0,
          },
        )
        .toList()
      ..sort(
        (a, b) => DateFormat(
          'dd/MM/yy',
        ).parse(a['date'] as String).compareTo(
          DateFormat('dd/MM/yy').parse(b['date'] as String),
        ),
      );

    return _SalesMetrics(
      totalRevenue: totalRevenue,
      totalOrders: totalOrders,
      totalOrderValue: totalOrderValue,
      avgOrderValue: avgOrderValue,
      unpaidAmount: unpaidAmount < 0 ? 0.0 : unpaidAmount,
      dailyData: dailyData,
      orders: filteredOrders,
    );
  }

  double _getMaxRevenue({_SalesMetrics? metrics}) {
    final activeMetrics = metrics ?? _metrics;
    if (activeMetrics.dailyData.isEmpty) return 0.0;
    return activeMetrics.dailyData
        .map((row) => (row['revenue'] as num?)?.toDouble() ?? 0.0)
        .fold<double>(0.0, (max, value) => value > max ? value : max);
  }

  String _formatCompactAmount(double value) {
    if (value.abs() >= 1000) {
      final code = _selectedCurrency == 'all' ? '' : '$_selectedCurrency ';
      return '$code${NumberFormat.compact().format(value)}';
    }
    final code = _selectedCurrency == 'all' ? '' : '$_selectedCurrency ';
    return '$code${value.toStringAsFixed(0)}';
  }

  int _chartLabelInterval({_SalesMetrics? metrics}) {
    final activeMetrics = metrics ?? _metrics;
    final count = activeMetrics.dailyData.length;
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    if (count <= 21) return 3;
    return 4;
  }

  double _averageDailyRevenue({_SalesMetrics? metrics}) {
    final activeMetrics = metrics ?? _metrics;
    if (activeMetrics.dailyData.isEmpty) return 0.0;
    final total = activeMetrics.dailyData.fold<double>(
      0.0,
      (sum, row) => sum + ((row['revenue'] as num?)?.toDouble() ?? 0.0),
    );
    return total / activeMetrics.dailyData.length;
  }

  Map<String, dynamic>? _peakRevenueDay({_SalesMetrics? metrics}) {
    final activeMetrics = metrics ?? _metrics;
    if (activeMetrics.dailyData.isEmpty) return null;
    Map<String, dynamic>? peak;
    for (final row in activeMetrics.dailyData) {
      final revenue = (row['revenue'] as num?)?.toDouble() ?? 0.0;
      if (peak == null ||
          revenue > ((peak['revenue'] as num?)?.toDouble() ?? 0.0)) {
        peak = row;
      }
    }
    return peak;
  }

  String? _percentageChange(double current, double previous) {
    if (!_compareMode || _previousMetrics == null) return null;
    if (previous == 0 && current == 0) return '0%';
    if (previous == 0) return '+100%';
    final change = ((current - previous) / previous) * 100;
    final prefix = change > 0 ? '+' : '';
    return '$prefix${change.toStringAsFixed(0)}%';
  }

  Color _changeColor(String? change) {
    if (change == null) return AppColors.mediumGrey;
    if (change.startsWith('-')) return AppColors.error;
    if (change == '0%') return AppColors.mediumGrey;
    return AppColors.success;
  }

  Future<void> _exportPDF() async {
    try {
      final pdf = await PdfGenerator.generateSalesReport(
        _metrics.orders,
        _metrics.totalRevenue,
        _metrics.totalOrders,
        _metrics.avgOrderValue,
        _metrics.dailyData
            .map((row) => {'date': row['date'], 'amount': row['revenue']})
            .toList(),
      );
      await Printing.sharePdf(bytes: pdf, filename: 'sales_report.pdf');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'PDF export failed: $e');
    }
  }

  Future<void> _exportExcel() async {
    try {
      final excel = ExcelGenerator.generateSalesReport(
        _metrics.orders,
        _metrics.totalRevenue,
        _metrics.totalOrders,
        _metrics.avgOrderValue,
        _metrics.dailyData
            .map((row) => {'date': row['date'], 'amount': row['revenue']})
            .toList(),
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
              _buildFilterCard(),
              const SizedBox(height: 16),
              _buildKpiGrid(),
              const SizedBox(height: 16),
              _buildRevenueChart(),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<DateTimeRange?>(
                  valueListenable: AppDateFilter.instance.rangeNotifier,
                  builder: (context, range, _) {
                    return Text(
                      range == null
                          ? 'Global filter: All dates'
                          : 'Global filter: ${range.start.day}/${range.start.month}/${range.start.year} - ${range.end.day}/${range.end.month}/${range.end.year}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mediumGrey,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
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
                            _recalculateReport();
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSalesPersonId,
                        decoration: const InputDecoration(
                          labelText: 'Salesperson',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All Sales'),
                          ),
                          ..._salesPeople.map(
                            (sales) => DropdownMenuItem<String>(
                              value: sales['id']?.toString() ?? '',
                              child: Text(
                                sales['name']?.toString() ??
                                    sales['id']?.toString() ??
                                    'Sales',
                              ),
                            ),
                          ),
                        ],
                    onChanged: (value) {
                      setState(() {
                        _selectedSalesPersonId = value ?? 'all';
                        _recalculateReport();
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
                        _recalculateReport();
                      });
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
                              _recalculateReport();
                            });
                          },
                        ),
                        const Text('Compare'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiGrid() {
    if (_selectedCurrency == 'all') {
      return Column(
        children: _currencySections
            .map((section) => _buildSalesSection(section))
            .toList(),
      );
    }
    final revenueChange = _percentageChange(
      _metrics.totalRevenue,
      _previousMetrics?.totalRevenue ?? 0.0,
    );
    final ordersChange = _percentageChange(
      _metrics.totalOrders.toDouble(),
      (_previousMetrics?.totalOrders ?? 0).toDouble(),
    );
    final avgChange = _percentageChange(
      _metrics.avgOrderValue,
      _previousMetrics?.avgOrderValue ?? 0.0,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isNarrow ? 1 : 2,
          childAspectRatio: isNarrow ? 2.0 : 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _buildKpiCard(
              'Revenue',
              'ETB ${_metrics.totalRevenue.toStringAsFixed(0)}',
              Icons.attach_money,
              AppColors.success,
              revenueChange,
            ),
            _buildKpiCard(
              'Orders',
              _metrics.totalOrders.toString(),
              Icons.shopping_bag,
              AppColors.primaryRed,
              ordersChange,
            ),
            _buildKpiCard(
              'Avg Order Value',
              'ETB ${_metrics.avgOrderValue.toStringAsFixed(0)}',
              Icons.analytics,
              AppColors.info,
              avgChange,
            ),
            _buildKpiCard(
              'Paid / Unpaid',
              'ETB ${_metrics.totalRevenue.toStringAsFixed(0)} / ${_metrics.unpaidAmount.toStringAsFixed(0)}',
              Icons.account_balance_wallet,
              AppColors.warning,
              null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSalesSection(_SalesSection section) {
    final metrics = section.metrics;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              section.currency,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _buildKpiCard(
                'Revenue',
                '${section.currency} ${metrics.totalRevenue.toStringAsFixed(0)}',
                Icons.attach_money,
                AppColors.success,
                null,
              ),
              _buildKpiCard(
                'Orders',
                metrics.totalOrders.toString(),
                Icons.shopping_bag,
                AppColors.primaryRed,
                null,
              ),
              _buildKpiCard(
                'Avg Order Value',
                '${section.currency} ${metrics.avgOrderValue.toStringAsFixed(0)}',
                Icons.analytics,
                AppColors.info,
                null,
              ),
              _buildKpiCard(
                'Paid / Unpaid',
                '${section.currency} ${metrics.totalRevenue.toStringAsFixed(0)} / ${metrics.unpaidAmount.toStringAsFixed(0)}',
                Icons.account_balance_wallet,
                AppColors.warning,
                null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRevenueChart(metrics: metrics, currency: section.currency),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String? change,
  ) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 155 || constraints.maxWidth < 360;
          return Padding(
            padding: EdgeInsets.all(isCompact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: isCompact ? 20 : 24),
                SizedBox(height: isCompact ? 8 : 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    color: AppColors.mediumGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: isCompact ? 4 : 6),
                Text(
                  value,
                  maxLines: isCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompact ? 15 : 16,
                    fontWeight: FontWeight.bold,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: isCompact ? 4 : 6),
                Text(
                  change == null
                      ? _compareMode && AppDateFilter.instance.range == null
                            ? 'Comparison needs a date range'
                            : 'Current period'
                      : 'vs previous: $change',
                  maxLines: isCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompact ? 10 : 11,
                    color:
                        change == null ? AppColors.mediumGrey : _changeColor(change),
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRevenueChart({_SalesMetrics? metrics, String? currency}) {
    final activeMetrics = metrics ?? _metrics;
    final peakDay = _peakRevenueDay(metrics: activeMetrics);
    final labelInterval = _chartLabelInterval(metrics: activeMetrics);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue Trend',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Revenue from recorded payments for active orders only.',
              style: const TextStyle(fontSize: 12, color: AppColors.mediumGrey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChartInsightChip(
                  'Peak Day',
                  peakDay == null
                      ? '-'
                      : '${peakDay['date']}  ${_formatCompactAmountForCurrency((peakDay['revenue'] as num?)?.toDouble() ?? 0.0, currency)}',
                ),
                _buildChartInsightChip(
                  'Daily Average',
                  _formatCompactAmountForCurrency(
                    _averageDailyRevenue(metrics: activeMetrics),
                    currency,
                  ),
                ),
                _buildChartInsightChip(
                  'Collected',
                  _formatCompactAmountForCurrency(
                    activeMetrics.totalRevenue,
                    currency,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (activeMetrics.dailyData.isEmpty)
              const SizedBox(
                height: 200,
                child: Center(child: Text('No sales data for the selected filters.')),
              )
            else
              SizedBox(
                height: 260,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceBetween,
                    maxY: _getMaxRevenue(metrics: activeMetrics) <= 0
                        ? 100
                        : _getMaxRevenue(metrics: activeMetrics) * 1.15,
                    minY: 0,
                    groupsSpace: 10,
                    barGroups: activeMetrics.dailyData.asMap().entries.map((entry) {
                      return BarChartGroupData(
                        x: entry.key,
                        barRods: [
                          BarChartRodData(
                            toY:
                                (entry.value['revenue'] as num?)?.toDouble() ??
                                0.0,
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                AppColors.primaryRed,
                                AppColors.primaryRed.withValues(alpha: 0.65),
                              ],
                            ),
                            width: 18,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(6),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => AppColors.black,
                        tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final row = activeMetrics.dailyData[group.x.toInt()];
                          final date = row['date'] as String? ?? '-';
                          final revenue =
                              (row['revenue'] as num?)?.toDouble() ?? 0.0;
                          final orders =
                              (row['orders'] as num?)?.toInt() ?? 0;
                          return BarTooltipItem(
                            '$date\n${_formatCompactAmountForCurrency(revenue, currency)}\n$orders order${orders == 1 ? '' : 's'}',
                            const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 ||
                                index >= activeMetrics.dailyData.length ||
                                index % labelInterval != 0) {
                              return const SizedBox.shrink();
                            }
                            final date = DateFormat(
                              'dd/MM/yy',
                            ).parse(activeMetrics.dailyData[index]['date'] as String);
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                DateFormat('dd MMM').format(date),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.mediumGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 52,
                          interval: _getMaxRevenue(metrics: activeMetrics) <= 0
                              ? 25
                              : _getMaxRevenue(metrics: activeMetrics) / 4,
                          getTitlesWidget: (value, meta) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              NumberFormat.compact().format(value),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.mediumGrey,
                                fontWeight: FontWeight.w500,
                              ),
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
                        color: AppColors.mediumGrey.withValues(alpha: 0.14),
                        strokeWidth: 1,
                      ),
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        left: BorderSide(
                          color: AppColors.mediumGrey.withValues(alpha: 0.15),
                        ),
                        bottom: BorderSide(
                          color: AppColors.mediumGrey.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatCompactAmountForCurrency(double value, String? currency) {
    final code = currency == null ? '' : '$currency ';
    if (value.abs() >= 1000) {
      return '$code${NumberFormat.compact().format(value)}';
    }
    return '$code${value.toStringAsFixed(0)}';
  }

  Widget _buildChartInsightChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: AppColors.mediumGrey,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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

class _SalesMetrics {
  const _SalesMetrics({
    required this.totalRevenue,
    required this.totalOrders,
    required this.totalOrderValue,
    required this.avgOrderValue,
    required this.unpaidAmount,
    required this.dailyData,
    required this.orders,
  });

  factory _SalesMetrics.empty() => const _SalesMetrics(
    totalRevenue: 0.0,
    totalOrders: 0,
    totalOrderValue: 0.0,
    avgOrderValue: 0.0,
    unpaidAmount: 0.0,
    dailyData: [],
    orders: [],
  );

  final double totalRevenue;
  final int totalOrders;
  final double totalOrderValue;
  final double avgOrderValue;
  final double unpaidAmount;
  final List<Map<String, dynamic>> dailyData;
  final List<Map<String, dynamic>> orders;
}

class _SalesSection {
  const _SalesSection({
    required this.currency,
    required this.metrics,
  });

  final String currency;
  final _SalesMetrics metrics;
}
