import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class LeaveRequestsListScreen extends StatefulWidget {
  const LeaveRequestsListScreen({Key? key}) : super(key: key);

  @override
  _LeaveRequestsListScreenState createState() =>
      _LeaveRequestsListScreenState();
}

class _LeaveRequestsListScreenState extends State<LeaveRequestsListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String _filterStatus = 'pending';

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _syncService.dataChangedStream.listen((_) {
      _loadRequests();
    });
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    var requests = List<Map<String, dynamic>>.from(
      await _dbHelper.query('leave_requests'),
    );
    requests.sort(
      (a, b) => (b['startDate'] as int).compareTo(a['startDate'] as int),
    );
    setState(() {
      _requests = requests;
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredRequests {
    if (_filterStatus == 'all') return _requests;
    return _requests.where((r) => r['status'] == _filterStatus).toList();
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    try {
      var request = _requests.firstWhere((r) => r['id'] == id);
      request['status'] = newStatus;
      await _dbHelper.update('leave_requests', request);
      _syncService.syncAll();
      _loadRequests();
      if (mounted) ErrorHandler.showSuccess(context, 'Request $newStatus');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Error: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.mediumGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    var filtered = _filteredRequests;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Requests'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: AppColors.primaryRedDark,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Text('Status:', style: TextStyle(color: AppColors.white)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _filterStatus,
                  dropdownColor: AppColors.backgroundStart,
                  style: const TextStyle(color: AppColors.white),
                  underline: Container(),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.white,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _filterStatus = value!),
                ),
              ],
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
            : filtered.isEmpty
            ? const Center(
                child: Text(
                  'No leave requests found.',
                  style: TextStyle(color: AppColors.white),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  var req = filtered[index];
                  DateTime start = DateTime.fromMillisecondsSinceEpoch(
                    req['startDate'],
                  );
                  DateTime end = DateTime.fromMillisecondsSinceEpoch(
                    req['endDate'],
                  );
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                req['employeeName'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(
                                    req['status'],
                                  ).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  req['status'],
                                  style: TextStyle(
                                    color: _getStatusColor(req['status']),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}',
                          ),
                          Text('Reason: ${req['reason']}'),
                          if (req['notes']?.isNotEmpty == true)
                            Text(
                              'Notes: ${req['notes']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (req['status'] == 'pending')
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _updateStatus(req['id'], 'approved'),
                                  child: const Text(
                                    'Approve',
                                    style: TextStyle(color: AppColors.success),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () =>
                                      _updateStatus(req['id'], 'rejected'),
                                  child: const Text(
                                    'Reject',
                                    style: TextStyle(color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
