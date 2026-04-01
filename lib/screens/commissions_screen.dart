import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class CommissionsScreen extends StatefulWidget {
  const CommissionsScreen({Key? key}) : super(key: key);

  @override
  _CommissionsScreenState createState() => _CommissionsScreenState();
}

class _CommissionsScreenState extends State<CommissionsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _dataChangedSubscription;
  List<Map<String, dynamic>> _commissions = [];
  List<Map<String, dynamic>> _uiCommissions = [];
  bool _isLoading = true;
  String _filterStatus = 'pending';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCommissions();
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      _loadCommissions();
    });
  }

  Future<void> _loadCommissions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    var commissions = await _dbHelper.query('commissions');
    if (!mounted) return;
    var mutable = List<Map<String, dynamic>>.from(commissions);
    mutable.sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    if (!mounted) return;
    setState(() {
      _commissions = mutable;
      _applyFilters();
      _isLoading = false;
    });
  }
  void _applyFilters() {
    var filtered = _commissions;

    // Apply status filter
    if (_filterStatus != 'all') {
      filtered = filtered.where((c) => c['status'] == _filterStatus).toList();
    }

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((c) {
        return (c['employeeName'] ?? '').toLowerCase().contains(query) ||
            (c['orderId'] ?? '').toLowerCase().contains(query) ||
            (c['type'] ?? '').toLowerCase().contains(query);
      }).toList();
    }

    if (!mounted) {
      _uiCommissions = filtered;
      return;
    }
    setState(() {
      _uiCommissions = filtered;
    });
  }

  void _filterByStatus(String? value) {
    setState(() {
      _filterStatus = value ?? 'all';
      _applyFilters();
    });
  }

  void _search(String query) {
    _applyFilters();
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'paid':
        return AppColors.success;
      default:
        return AppColors.mediumGrey;
    }
  }

  Future<void> _markAsPaid(String commissionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Paid'),
        content: const Text('Confirm that this commission has been paid?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: AppColors.success)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // Find the commission from the original list (not the filtered one)
      var commission = _commissions.firstWhere((c) => c['id'] == commissionId);
      // Create a mutable copy
      var updatedCommission = Map<String, dynamic>.from(commission);
      updatedCommission['status'] = 'paid';
      updatedCommission['paidAt'] = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.update('commissions', updatedCommission);
      await _loadCommissions();
    }
  }

  @override
  void dispose() {
    _dataChangedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commissions'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by employee or order...',
                    hintStyle: TextStyle(
                      color: AppColors.white.withOpacity(0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.white,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.white.withOpacity(0.1),
                  ),
                  onChanged: _search,
                ),
              ),
              Container(
                color: AppColors.primaryRedDark,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Text(
                      'Status:',
                      style: TextStyle(color: AppColors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
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
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pending'),
                          ),
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                        ],
                        onChanged: _filterByStatus,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
          onRefresh: _loadCommissions,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiCommissions.isEmpty
              ? const Center(
                  child: Text(
                    'No commissions found.',
                    style: TextStyle(color: AppColors.white),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _uiCommissions.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.white, height: 0.5),
                  itemBuilder: (context, index) {
                    var comm = _uiCommissions[index];
                    DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(
                      comm['createdAt'],
                    );
                    String dateStr = DateFormat('dd/MM/yy').format(createdAt);
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: _getStatusColor(comm['status']),
                        child: Text(
                          (comm['type'] ?? '?')[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              comm['employeeName'] ?? 'Unknown',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(
                                comm['status'],
                              ).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              comm['status'] ?? 'pending',
                              style: TextStyle(
                                color: _getStatusColor(comm['status']),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            '${comm['type']} · Order: ${comm['orderId']?.substring(0, 6)} · $dateStr',
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ETB ${(comm['amount'] ?? 0).toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (comm['status'] == 'pending')
                            IconButton(
                              icon: const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 20,
                              ),
                              onPressed: () => _markAsPaid(comm['id']),
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
