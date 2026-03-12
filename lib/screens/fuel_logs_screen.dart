import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_edit_fuel_log_screen.dart';

class FuelLogsScreen extends StatefulWidget {
  final String vehicleId;
  const FuelLogsScreen({Key? key, required this.vehicleId}) : super(key: key);

  @override
  _FuelLogsScreenState createState() => _FuelLogsScreenState();
}

class _FuelLogsScreenState extends State<FuelLogsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _uiLogs = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _syncService.dataChangedStream.listen((_) {
      _loadLogs();
    });
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    var allLogs = await _dbHelper.query('fuel_logs');
    var filtered = allLogs.where((l) => l['vehicleId'] == widget.vehicleId).toList();
    filtered.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
    setState(() {
      _logs = filtered;
      _uiLogs = filtered;
      _isLoading = false;
    });
  }

  void _filterLogs(String query) {
    if (query.isEmpty) {
      setState(() {
        _uiLogs = _logs;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _uiLogs = _logs.where((l) {
        return (l['notes'] ?? '').toLowerCase().contains(lowerQuery) ||
               DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(l['date'])).contains(query);
      }).toList();
    });
  }

  Future<void> _deleteLog(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Log'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Optimistic update
    setState(() {
      _uiLogs.removeWhere((l) => l['id'] == id);
    });

    try {
      await _dbHelper.delete('fuel_logs', id);
      _logs.removeWhere((l) => l['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Log deleted');
    } catch (e) {
      setState(() {
        _uiLogs = List.from(_logs);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel Logs'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddEditFuelLogScreen(vehicleId: widget.vehicleId),
                ),
              ).then((_) => _loadLogs());
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
                hintText: 'Search logs...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterLogs,
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
          onRefresh: _loadLogs,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiLogs.isEmpty
                  ? const Center(
                      child: Text('No fuel logs found.', style: TextStyle(color: AppColors.white)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _uiLogs.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var log = _uiLogs[index];
                        DateTime date = DateTime.fromMillisecondsSinceEpoch(log['date']);
                        String dateStr = DateFormat('dd/MM/yy HH:mm').format(date);
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.info,
                            child: const Icon(Icons.local_gas_station, color: AppColors.white, size: 16),
                          ),
                          title: Text(
                            '${log['liters']} L · ETB ${(log['cost'] ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            'Odometer: ${log['odometer'] ?? 0} km · $dateStr',
                            style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                            onPressed: () => _deleteLog(log['id']),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}