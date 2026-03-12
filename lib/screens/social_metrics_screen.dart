import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import 'add_edit_metrics_screen.dart';

class SocialMetricsScreen extends StatefulWidget {
  final String accountId;
  final String accountName;
  const SocialMetricsScreen({Key? key, required this.accountId, required this.accountName}) : super(key: key);

  @override
  _SocialMetricsScreenState createState() => _SocialMetricsScreenState();
}

class _SocialMetricsScreenState extends State<SocialMetricsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _metrics = [];
  List<Map<String, dynamic>> _filteredMetrics = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    _syncService.dataChangedStream.listen((_) {
      _loadMetrics();
    });
  }

  Future<void> _loadMetrics() async {
    setState(() => _isLoading = true);
    var allMetrics = await _dbHelper.query('social_metrics');
    var filtered = allMetrics.where((m) => m['accountId'] == widget.accountId).toList();
    filtered.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
    setState(() {
      _metrics = filtered;
      _filteredMetrics = filtered;
      _isLoading = false;
    });
  }

  void _filterMetrics(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredMetrics = _metrics;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredMetrics = _metrics.where((m) {
        final dateStr = DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(m['date']));
        return dateStr.contains(query) ||
               (m['followers']?.toString() ?? '').contains(query) ||
               (m['likes']?.toString() ?? '').contains(query);
      }).toList();
    });
  }

  Future<void> _deleteMetric(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this metrics entry?'),
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
      await _dbHelper.delete('social_metrics', id);
      _loadMetrics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Metrics - ${widget.accountName}'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddEditMetricsScreen(accountId: widget.accountId),
                ),
              ).then((_) => _loadMetrics());
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
                hintText: 'Search by date or numbers...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterMetrics,
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
        child: RefreshIndicator(
          onRefresh: _loadMetrics,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredMetrics.isEmpty
                  ? const Center(
                      child: Text('No metrics found.', style: TextStyle(color: AppColors.white)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filteredMetrics.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var m = _filteredMetrics[index];
                        DateTime date = DateTime.fromMillisecondsSinceEpoch(m['date']);
                        String dateStr = DateFormat('dd/MM/yy').format(date);
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      dateStr,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                                      onPressed: () => _deleteMetric(m['id']),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  children: [
                                    _buildMetricChip('👥', m['followers'] ?? 0),
                                    _buildMetricChip('📝', m['posts'] ?? 0),
                                    _buildMetricChip('❤️', m['likes'] ?? 0),
                                    _buildMetricChip('💬', m['comments'] ?? 0),
                                    _buildMetricChip('🔄', m['shares'] ?? 0),
                                    _buildMetricChip('👀', m['views'] ?? 0),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildMetricChip(String icon, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}