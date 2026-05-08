import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/barcode_service.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';
import 'order_details_screen.dart';
import 'scanner_screen.dart';

class ShipmentDashboardScreen extends StatefulWidget {
  const ShipmentDashboardScreen({
    super.key,
    this.initialBranchId,
    this.lockBranchFilter = false,
  });

  final String? initialBranchId;
  final bool lockBranchFilter;

  @override
  State<ShipmentDashboardScreen> createState() =>
      _ShipmentDashboardScreenState();
}

class _ShipmentDashboardScreenState extends State<ShipmentDashboardScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _branches = [];
  Map<String, String> _branchNamesById = {};
  String _selectedBranchId = 'all';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.initialBranchId ?? 'all';
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final orders = await _dbHelper.query('orders');
    final branches = await _dbHelper.query('branches');
    if (!mounted) return;
    final branchList = List<Map<String, dynamic>>.from(branches);
    setState(() {
      _orders = List<Map<String, dynamic>>.from(orders)
        ..sort(
          (a, b) => ((b['createdAt'] as num?)?.toInt() ?? 0).compareTo(
            (a['createdAt'] as num?)?.toInt() ?? 0,
          ),
        );
      _branches = branchList;
      _branchNamesById = {
        for (final branch in branchList)
          if ((branch['id']?.toString() ?? '').isNotEmpty)
            branch['id'].toString():
                branch['name']?.toString() ?? branch['id'].toString(),
      };
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final query = _searchController.text.trim().toLowerCase();
    return _orders.where((order) {
      final branchId = order['branchId']?.toString() ?? '';
      if (_selectedBranchId != 'all' && branchId != _selectedBranchId) {
        return false;
      }
      if (query.isEmpty) return true;
      final searchable = [
        order['id'],
        order['customerName'],
        order['status'],
        order['tracking_number'],
        order['courier_name'],
        _branchNamesById[branchId],
      ].whereType<Object>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'delivered':
      case 'completed':
        return AppColors.success;
      case 'out_for_delivery':
        return AppColors.info;
      case 'processing':
        return AppColors.warning;
      case 'cancelled':
      case 'returned':
        return AppColors.error;
      default:
        return AppColors.mediumGrey;
    }
  }

  String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

  String _branchNameFor(Map<String, dynamic> order) {
    final branchId = order['branchId']?.toString() ?? '';
    if (branchId.isEmpty) return 'No branch';
    return _branchNamesById[branchId] ?? branchId;
  }

  void _openOrder(String orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(orderId: orderId),
      ),
    );
  }

  Future<void> _lookupTypedOrder() async {
    final input = _searchController.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (input.isEmpty) return;
    final match = _orders.firstWhere(
      (order) => order['id']?.toString() == input,
      orElse: () => <String, dynamic>{},
    );
    if (match.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No order found for that number')),
      );
      return;
    }
    await BarcodeService.openTrackingUrl(input);
  }

  Future<void> _copyLink(String orderId) async {
    final url = BarcodeService.trackingUrlForOrder(orderId);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tracking link copied')),
    );
  }

  Future<void> _printLabel(Map<String, dynamic> order) async {
    await BarcodeService.printLabel(
      orderId: order['id']?.toString() ?? '',
      customerName: order['customerName']?.toString(),
      status: order['status']?.toString(),
      branchName: _branchNameFor(order),
    );
  }

  Future<void> _shareLabel(Map<String, dynamic> order) async {
    await BarcodeService.shareLabel(
      orderId: order['id']?.toString() ?? '',
      customerName: order['customerName']?.toString(),
      status: order['status']?.toString(),
      branchName: _branchNameFor(order),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id']?.toString() ?? '';
    final status = order['status']?.toString() ?? 'pending';
    final color = _statusColor(status);
    final actionStyle = TextButton.styleFrom(
      foregroundColor: AppColors.primaryRed,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.18),
                  child: Icon(Icons.local_shipping, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order['customerName']?.toString() ?? 'Unknown customer',
                        style: const TextStyle(
                          color: AppColors.darkGrey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${_shortId(orderId)} - ${_branchNameFor(order)}',
                        style: const TextStyle(color: AppColors.mediumGrey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              BarcodeService.trackingUrlForOrder(orderId),
              style: const TextStyle(color: AppColors.mediumGrey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  style: actionStyle,
                  onPressed: () => BarcodeService.openTrackingUrl(orderId),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open link'),
                ),
                TextButton.icon(
                  style: actionStyle,
                  onPressed: () => _copyLink(orderId),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
                TextButton.icon(
                  style: actionStyle,
                  onPressed: () => _printLabel(order),
                  icon: const Icon(Icons.print),
                  label: const Text('Print'),
                ),
                TextButton.icon(
                  style: actionStyle,
                  onPressed: () => _shareLabel(order),
                  icon: const Icon(Icons.share),
                  label: const Text('Share PDF'),
                ),
                TextButton.icon(
                  style: actionStyle,
                  onPressed: () => _openOrder(orderId),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orders = _filteredOrders;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shipment Tracking'),
        actions: [
          IconButton(
            tooltip: 'Scan barcode / QR',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScannerScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
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
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Find shipment',
                            style: TextStyle(
                              color: AppColors.darkGrey,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _searchController,
                            style: const TextStyle(color: AppColors.darkGrey),
                            decoration: const InputDecoration(
                              labelText: 'Enter order number or customer',
                              labelStyle: TextStyle(
                                color: AppColors.mediumGrey,
                              ),
                              prefixIcon: Icon(Icons.search),
                              prefixIconColor: AppColors.mediumGrey,
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _lookupTypedOrder(),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedBranchId,
                                  decoration: const InputDecoration(
                                    labelText: 'Branch',
                                    labelStyle: TextStyle(
                                      color: AppColors.mediumGrey,
                                    ),
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.darkGrey,
                                  ),
                                  items: [
                                    if (!widget.lockBranchFilter)
                                      const DropdownMenuItem(
                                        value: 'all',
                                        child: Text('All branches'),
                                      ),
                                    if (_selectedBranchId != 'all' &&
                                        !_branches.any(
                                          (branch) =>
                                              branch['id']?.toString() ==
                                              _selectedBranchId,
                                        ))
                                      DropdownMenuItem(
                                        value: _selectedBranchId,
                                        child: Text(_selectedBranchId),
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
                                  onChanged: widget.lockBranchFilter
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _selectedBranchId = value ?? 'all';
                                          });
                                        },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _lookupTypedOrder,
                                icon: const Icon(Icons.login),
                                label: const Text('Open'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${orders.length} shipment${orders.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (orders.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No shipments found.',
                          style: TextStyle(color: AppColors.mediumGrey),
                        ),
                      ),
                    )
                  else
                    ...orders.map(_buildOrderCard),
                ],
              ),
      ),
    );
  }
}
