import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'purchase_order_details_screen.dart';
import 'create_purchase_order_screen.dart';

class PurchaseOrdersListScreen extends StatefulWidget {
  final String? initialStatus;
  const PurchaseOrdersListScreen({Key? key, this.initialStatus})
    : super(key: key);

  @override
  _PurchaseOrdersListScreenState createState() =>
      _PurchaseOrdersListScreenState();
}

class _PurchaseOrdersListScreenState extends State<PurchaseOrdersListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _dataChangedSubscription;
  List<Map<String, dynamic>> _purchaseOrders = [];
  List<Map<String, dynamic>> _uiPurchaseOrders = [];
  bool _isLoading = true;
  String _filterStatus = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterStatus = widget.initialStatus ?? 'all';
    _loadPurchaseOrders();
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      if (mounted) _loadPurchaseOrders();
    });
  }

  @override
  void dispose() {
    _dataChangedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPurchaseOrders() async {
    if (mounted) setState(() => _isLoading = true);
    var pos = List<Map<String, dynamic>>.from(
      await _dbHelper.query('purchase_orders'),
    );
    pos.sort(
      (a, b) => (b['orderDate'] as int).compareTo(a['orderDate'] as int),
    );
    if (mounted) {
      setState(() {
        _purchaseOrders = pos;
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    var filtered = _purchaseOrders;

    // Apply status filter
    if (_filterStatus != 'all') {
      filtered = filtered.where((po) => po['status'] == _filterStatus).toList();
    }

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((po) {
        return (po['supplierName'] ?? '').toLowerCase().contains(query) ||
            (po['id'] ?? '').toLowerCase().contains(query);
      }).toList();
    }

    setState(() {
      _uiPurchaseOrders = filtered;
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
      case 'draft':
        return AppColors.mediumGrey;
      case 'ordered':
        return AppColors.info;
      case 'received':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.mediumGrey;
    }
  }

  Future<void> _deletePurchaseOrder(String id, String supplierName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Delete Purchase Order'),
          content: Text(
            'Are you sure you want to delete order from $supplierName?',
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
      _uiPurchaseOrders.removeWhere((po) => po['id'] == id);
    });

    try {
      await _dbHelper.delete('purchase_orders', id);
      _purchaseOrders.removeWhere((po) => po['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Purchase order deleted');
    } catch (e) {
      setState(() {
        _uiPurchaseOrders = List.from(_purchaseOrders);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Orders'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreatePurchaseOrderScreen(),
                ),
              ).then((_) => _loadPurchaseOrders());
            },
          ),
        ],
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
                    hintText: 'Search by supplier or PO number...',
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
                            value: 'draft',
                            child: Text('Draft'),
                          ),
                          DropdownMenuItem(
                            value: 'ordered',
                            child: Text('Ordered'),
                          ),
                          DropdownMenuItem(
                            value: 'received',
                            child: Text('Received'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelled'),
                          ),
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
          onRefresh: _loadPurchaseOrders,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiPurchaseOrders.isEmpty
              ? const Center(
                  child: Text(
                    'No purchase orders found.',
                    style: TextStyle(color: AppColors.white),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _uiPurchaseOrders.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.white, height: 0.5),
                  itemBuilder: (context, index) {
                    var po = _uiPurchaseOrders[index];
                    DateTime orderDate = DateTime.fromMillisecondsSinceEpoch(
                      po['orderDate'],
                    );
                    String dateStr = DateFormat('dd/MM/yy').format(orderDate);
                    return ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                PurchaseOrderDetailsScreen(poId: po['id']),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: _getStatusColor(po['status']),
                        child: Text(
                          (po['id']?.substring(0, 1) ?? '#'),
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
                              po['supplierName'] ?? 'Unknown',
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
                                po['status'],
                              ).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              po['status'] ?? 'draft',
                              style: TextStyle(
                                color: _getStatusColor(po['status']),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            'PO-${po['id']?.substring(0, 6)} · $dateStr',
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
                            'ETB ${(po['totalAmount'] ?? 0).toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () => _deletePurchaseOrder(
                              po['id'],
                              po['supplierName'] ?? '',
                            ),
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
