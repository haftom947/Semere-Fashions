import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/error_handler.dart';
import 'order_details_screen.dart';

class OrdersListScreen extends StatefulWidget {
  final String? initialStatus;
  const OrdersListScreen({Key? key, this.initialStatus}) : super(key: key);

  @override
  _OrdersListScreenState createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoading = true;
  String _filterStatus = 'all';
  String _filterBranch = 'all';
  String _filterEmployee = 'all';
  String _filterRole = 'all'; // new role filter
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterStatus = widget.initialStatus ?? 'all';
    _loadOrders();
    _loadBranches();
    _loadEmployees();
    _syncService.dataChangedStream.listen((_) {
      _loadOrders();
      _loadBranches();
      _loadEmployees();
    });
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    var orders = await _dbHelper.query('orders');
    var assignments = await _dbHelper.query('order_assignments');
    orders.sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    setState(() {
      _orders = orders;
      _assignments = assignments;
      _applyFilters();
      _isLoading = false;
    });
  }

  Future<void> _loadBranches() async {
    var branches = await _dbHelper.query('branches');
    setState(() {
      _branches = branches;
    });
  }

  Future<void> _loadEmployees() async {
    var employees = await _dbHelper.query('users');
    setState(() {
      _employees = employees;
    });
  }

  void _applyFilters() {
    var filtered = _orders;
    
    // Status filter
    if (_filterStatus != 'all') {
      filtered = filtered.where((o) => o['status'] == _filterStatus).toList();
    }
    
    // Branch filter
    if (_filterBranch != 'all') {
      filtered = filtered.where((o) => o['branchId'] == _filterBranch).toList();
    }
    
    // Role filter
    if (_filterRole != 'all') {
      // Find all employee IDs with the selected role
      var roleEmployeeIds = _employees
          .where((e) => e['role'] == _filterRole)
          .map((e) => e['id'])
          .toSet();
      // Find order IDs where any assignment has an employee with that role
      var orderIds = _assignments
          .where((a) => roleEmployeeIds.contains(a['employeeId']))
          .map((a) => a['orderId'])
          .toSet();
      filtered = filtered.where((o) => orderIds.contains(o['id'])).toList();
    }
    
    // Employee filter (overrides role filter? We'll combine them: if both are set, we require the employee to be in the list and also match the role? That might be too restrictive. For simplicity, we'll treat role filter as independent; if both are set, we'll apply employee filter after role filter.)
    if (_filterEmployee != 'all') {
      // Find order IDs where this specific employee is assigned
      var orderIds = _assignments
          .where((a) => a['employeeId'] == _filterEmployee)
          .map((a) => a['orderId'])
          .toSet();
      filtered = filtered.where((o) => orderIds.contains(o['id'])).toList();
    }
    
    // Search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((o) {
        return (o['customerName'] ?? '').toLowerCase().contains(query) ||
               (o['id'] ?? '').toLowerCase().contains(query);
      }).toList();
    }
    
    setState(() {
      _filteredOrders = filtered;
    });
  }

  void _filterByStatus(String? value) {
    setState(() {
      _filterStatus = value ?? 'all';
      _applyFilters();
    });
  }

  void _filterByBranch(String? value) {
    setState(() {
      _filterBranch = value ?? 'all';
      _applyFilters();
    });
  }

  void _filterByEmployee(String? value) {
    setState(() {
      _filterEmployee = value ?? 'all';
      _applyFilters();
    });
  }

  void _filterByRole(String? value) {
    setState(() {
      _filterRole = value ?? 'all';
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
      case 'processing':
        return AppColors.info;
      case 'out_for_delivery':
        return AppColors.accent;
      case 'completed':
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.mediumGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    var filtered = _filteredOrders;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(220), // increased for 4 filters
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by customer or order ID...',
                    hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.search, color: AppColors.white),
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
              // Filters row (status, branch, role, employee)
              Container(
                color: AppColors.primaryRedDark,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // First row: status and branch
                      Row(
                        children: [
                          const Text('Status:', style: TextStyle(color: AppColors.white)),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _filterStatus,
                            dropdownColor: AppColors.backgroundStart,
                            style: const TextStyle(color: AppColors.white),
                            underline: Container(),
                            icon: const Icon(Icons.arrow_drop_down, color: AppColors.white),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All')),
                              DropdownMenuItem(value: 'pending', child: Text('Pending')),
                              DropdownMenuItem(value: 'processing', child: Text('Processing')),
                              DropdownMenuItem(value: 'out_for_delivery', child: Text('Out for Delivery')),
                              DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                              DropdownMenuItem(value: 'completed', child: Text('Completed')),
                              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                            ],
                            onChanged: _filterByStatus,
                          ),
                          const SizedBox(width: 16),
                          const Text('Branch:', style: TextStyle(color: AppColors.white)),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _filterBranch,
                            dropdownColor: AppColors.backgroundStart,
                            style: const TextStyle(color: AppColors.white),
                            underline: Container(),
                            icon: const Icon(Icons.arrow_drop_down, color: AppColors.white),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Branches')),
                              ..._branches.map((b) => DropdownMenuItem(
                                value: b['id'],
                                child: Text(b['name']),
                              )),
                            ],
                            onChanged: _filterByBranch,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Second row: role and employee
                      Row(
                        children: [
                          const Text('Role:', style: TextStyle(color: AppColors.white)),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _filterRole,
                            dropdownColor: AppColors.backgroundStart,
                            style: const TextStyle(color: AppColors.white),
                            underline: Container(),
                            icon: const Icon(Icons.arrow_drop_down, color: AppColors.white),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Roles')),
                              const DropdownMenuItem(value: 'sales', child: Text('Sales')),
                              const DropdownMenuItem(value: 'tailor', child: Text('Tailor')),
                              const DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                              const DropdownMenuItem(value: 'manager', child: Text('Manager')),
                              const DropdownMenuItem(value: 'admin', child: Text('Admin')),
                            ],
                            onChanged: _filterByRole,
                          ),
                          const SizedBox(width: 16),
                          const Text('Employee:', style: TextStyle(color: AppColors.white)),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _filterEmployee,
                            dropdownColor: AppColors.backgroundStart,
                            style: const TextStyle(color: AppColors.white),
                            underline: Container(),
                            icon: const Icon(Icons.arrow_drop_down, color: AppColors.white),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Employees')),
                              ..._employees.map((e) => DropdownMenuItem(
                                value: e['id'],
                                child: Text(e['name'] ?? 'Unknown'),
                              )),
                            ],
                            onChanged: _filterByEmployee,
                          ),
                        ],
                      ),
                    ],
                  ),
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
          onRefresh: _loadOrders,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(
                      child: Text('No orders found.', style: TextStyle(color: AppColors.white)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var order = filtered[index];
                        DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(order['createdAt']);
                        String dateStr = DateFormat('dd/MM/yy HH:mm').format(createdAt);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => OrderDetailsScreen(orderId: order['id']),
                                ),
                              );
                            },
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: _getStatusColor(order['status']),
                              child: Text(
                                (order['id']?.substring(0, 1) ?? '#'),
                                style: const TextStyle(color: AppColors.white, fontSize: 14),
                              ),
                            ),
                            title: Text(
                              order['customerName'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '#${order['id']?.substring(0, 6)} • $dateStr',
                              style: TextStyle(fontSize: 12, color: AppColors.mediumGrey),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'ETB ${(order['totalAmount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(order['status']).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    order['status'] ?? 'pending',
                                    style: TextStyle(
                                      color: _getStatusColor(order['status']),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
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
}