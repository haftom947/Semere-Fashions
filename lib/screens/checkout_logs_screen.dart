import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class CheckoutLogsScreen extends StatefulWidget {
  final String equipmentId;
  final String equipmentName;
  const CheckoutLogsScreen({
    Key? key,
    required this.equipmentId,
    required this.equipmentName,
  }) : super(key: key);

  @override
  _CheckoutLogsScreenState createState() => _CheckoutLogsScreenState();
}

class _CheckoutLogsScreenState extends State<CheckoutLogsScreen> {
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
    var allLogs = List<Map<String, dynamic>>.from(
      await _dbHelper.query('checkout_logs'),
    );
    var filtered = allLogs
        .where((l) => l['equipmentId'] == widget.equipmentId)
        .toList();
    filtered.sort(
      (a, b) => (b['checkoutDate'] as int).compareTo(a['checkoutDate'] as int),
    );
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
        return (l['employeeName'] ?? '').toLowerCase().contains(lowerQuery) ||
            (l['notes'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _returnEquipment(String logId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Return Equipment'),
          content: const Text('Mark this item as returned?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Return',
                style: TextStyle(color: AppColors.success),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      var log = _logs.firstWhere((l) => l['id'] == logId);
      log['actualReturnDate'] = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.update('checkout_logs', log);
      _loadLogs();
    }
  }

  Future<void> _deleteLog(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Delete Log'),
          content: const Text(
            'Are you sure you want to delete this checkout record?',
          ),
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
    if (confirm != true) return;

    // Optimistic update
    setState(() {
      _uiLogs.removeWhere((l) => l['id'] == id);
    });

    try {
      await _dbHelper.delete('checkout_logs', id);
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
        title: Text('Checkout Logs - ${widget.equipmentName}'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search by employee...',
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
                  child: Text(
                    'No checkout logs found.',
                    style: TextStyle(color: AppColors.white),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _uiLogs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.white, height: 0.5),
                  itemBuilder: (context, index) {
                    var log = _uiLogs[index];
                    DateTime checkoutDate = DateTime.fromMillisecondsSinceEpoch(
                      log['checkoutDate'],
                    );
                    String checkoutStr = DateFormat(
                      'dd/MM/yy HH:mm',
                    ).format(checkoutDate);
                    bool isOut = log['actualReturnDate'] == null;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: isOut
                            ? AppColors.warning
                            : AppColors.success,
                        child: Icon(
                          isOut ? Icons.logout : Icons.login,
                          color: AppColors.white,
                          size: 16,
                        ),
                      ),
                      title: Text(
                        log['employeeName'] ?? 'Unknown',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Checked out: $checkoutStr',
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.7),
                            ),
                          ),
                          if (log['expectedReturnDate'] != null)
                            Text(
                              'Expected: ${DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(log['expectedReturnDate']))}',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.7),
                              ),
                            ),
                          if (log['actualReturnDate'] != null)
                            Text(
                              'Returned: ${DateFormat('dd/MM/yy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(log['actualReturnDate']))}',
                              style: const TextStyle(color: AppColors.success),
                            ),
                          if (log['notes'] != null)
                            Text(
                              log['notes'],
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOut)
                            IconButton(
                              icon: const Icon(
                                Icons.assignment_return,
                                color: AppColors.success,
                                size: 20,
                              ),
                              onPressed: () => _returnEquipment(log['id']),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () => _deleteLog(log['id']),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
