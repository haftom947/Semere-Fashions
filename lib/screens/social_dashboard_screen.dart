import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import 'social_accounts_screen.dart';

class SocialDashboardScreen extends StatefulWidget {
  const SocialDashboardScreen({super.key});

  @override
  _SocialDashboardScreenState createState() => _SocialDashboardScreenState();
}

class _SocialDashboardScreenState extends State<SocialDashboardScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _metrics = [];
  bool _isLoading = true;
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    var accounts = await _dbHelper.query('social_accounts');
    var metrics = await _dbHelper.query('social_metrics');
    setState(() {
      _accounts = accounts;
      _metrics = metrics;
      if (accounts.isNotEmpty) {
        _selectedAccountId = accounts.first['id'];
      }
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredMetrics {
    if (_selectedAccountId == null) return [];
    return _metrics.where((m) => m['accountId'] == _selectedAccountId).toList()
      ..sort((a, b) => (a['date'] as int).compareTo(b['date'] as int));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Social Media Dashboard'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SocialAccountsScreen()),
              );
            },
          ),
        ],
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
            : _accounts.isEmpty
                ? const Center(
                    child: Text('No social accounts. Add one in settings.', style: TextStyle(color: AppColors.white)),
                  )
                : Column(
                    children: [
                      // Account selector
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedAccountId,
                          dropdownColor: AppColors.backgroundStart,
                          style: const TextStyle(color: AppColors.white),
                          decoration: InputDecoration(
                            labelText: 'Select Account',
                            labelStyle: const TextStyle(color: AppColors.white),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.white.withOpacity(0.3)),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.white),
                            ),
                          ),
                          items: _accounts.map((a) => DropdownMenuItem<String>(
                            value: a['id'],
                            child: Text('${a['platform']} - ${a['accountName']}', style: const TextStyle(color: AppColors.white)),
                          )).toList(),
                          onChanged: (value) => setState(() => _selectedAccountId = value),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Followers chart
                              if (_filteredMetrics.isNotEmpty) ...[
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Followers Growth', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          height: 200,
                                          child: LineChart(
                                            LineChartData(
                                              gridData: const FlGridData(show: true),
                                              titlesData: FlTitlesData(
                                                bottomTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    getTitlesWidget: (value, meta) {
                                                      int index = value.toInt();
                                                      if (index >= 0 && index < _filteredMetrics.length) {
                                                        var date = DateTime.fromMillisecondsSinceEpoch(_filteredMetrics[index]['date']);
                                                        return Text('${date.day}/${date.month}', style: const TextStyle(color: AppColors.white, fontSize: 10));
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
                                              borderData: FlBorderData(show: false),
                                              lineBarsData: [
                                                LineChartBarData(
                                                  spots: _filteredMetrics.asMap().entries.map((e) {
                                                    return FlSpot(e.key.toDouble(), (e.value['followers'] as num?)?.toDouble() ?? 0);
                                                  }).toList(),
                                                  isCurved: true,
                                                  color: AppColors.primaryRed,
                                                  barWidth: 3,
                                                  belowBarData: BarAreaData(show: false),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Engagement metrics (likes, comments, shares)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Engagement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          height: 200,
                                          child: LineChart(
                                            LineChartData(
                                              gridData: const FlGridData(show: true),
                                              titlesData: FlTitlesData(
                                                bottomTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    getTitlesWidget: (value, meta) {
                                                      int index = value.toInt();
                                                      if (index >= 0 && index < _filteredMetrics.length) {
                                                        var date = DateTime.fromMillisecondsSinceEpoch(_filteredMetrics[index]['date']);
                                                        return Text('${date.day}/${date.month}', style: const TextStyle(color: AppColors.white, fontSize: 10));
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
                                              borderData: FlBorderData(show: false),
                                              lineBarsData: [
                                                LineChartBarData(
                                                  spots: _filteredMetrics.asMap().entries.map((e) {
                                                    return FlSpot(e.key.toDouble(), (e.value['likes'] as num?)?.toDouble() ?? 0);
                                                  }).toList(),
                                                  isCurved: true,
                                                  color: AppColors.success,
                                                  barWidth: 2,
                                                  belowBarData: BarAreaData(show: false),
                                                ),
                                                LineChartBarData(
                                                  spots: _filteredMetrics.asMap().entries.map((e) {
                                                    return FlSpot(e.key.toDouble(), (e.value['comments'] as num?)?.toDouble() ?? 0);
                                                  }).toList(),
                                                  isCurved: true,
                                                  color: AppColors.info,
                                                  barWidth: 2,
                                                  belowBarData: BarAreaData(show: false),
                                                ),
                                                LineChartBarData(
                                                  spots: _filteredMetrics.asMap().entries.map((e) {
                                                    return FlSpot(e.key.toDouble(), (e.value['shares'] as num?)?.toDouble() ?? 0);
                                                  }).toList(),
                                                  isCurved: true,
                                                  color: AppColors.warning,
                                                  barWidth: 2,
                                                  belowBarData: BarAreaData(show: false),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: const [
                                            LegendItem(color: AppColors.success, label: 'Likes'),
                                            SizedBox(width: 16),
                                            LegendItem(color: AppColors.info, label: 'Comments'),
                                            SizedBox(width: 16),
                                            LegendItem(color: AppColors.warning, label: 'Shares'),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ] else
                                const Center(child: Text('No metrics data for this account', style: TextStyle(color: AppColors.white))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const LegendItem({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.white)),
      ],
    );
  }
}