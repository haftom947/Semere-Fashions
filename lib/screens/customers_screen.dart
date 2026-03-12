import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'customer_details_screen.dart';
import 'add_edit_customer_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({Key? key}) : super(key: key);

  @override
  _CustomersScreenState createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _uiCustomers = []; // for optimistic UI
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _syncService.dataChangedStream.listen((_) {
      _loadCustomers();
    });
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    var customers = await _dbHelper.query('customers');
    customers.sort((a, b) => (b['createdAt'] ?? 0).compareTo(a['createdAt'] ?? 0));
    setState(() {
      _customers = customers;
      _uiCustomers = customers;
      _isLoading = false;
    });
  }

  void _filterCustomers(String query) {
    if (query.isEmpty) {
      setState(() {
        _uiCustomers = _customers;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _uiCustomers = _customers.where((c) {
        return (c['name'] ?? '').toLowerCase().contains(lowerQuery) ||
               (c['phone'] ?? '').contains(query);
      }).toList();
    });
  }

  Future<void> _deleteCustomer(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Are you sure you want to delete $name?'),
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

    // Optimistic update: remove from UI immediately
    setState(() {
      _uiCustomers.removeWhere((c) => c['id'] == id);
    });

    try {
      await _dbHelper.delete('customers', id);
      // Remove from original list as well
      _customers.removeWhere((c) => c['id'] == id);
      _syncService.syncAll(); // background sync
      if (mounted) ErrorHandler.showSuccess(context, 'Customer deleted');
    } catch (e) {
      // Revert on error
      setState(() {
        _uiCustomers = List.from(_customers);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search customers...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterCustomers,
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
            : _uiCustomers.isEmpty
                ? const Center(
                    child: Text('No customers found.', style: TextStyle(color: AppColors.white)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _uiCustomers.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                    itemBuilder: (context, index) {
                      var customer = _uiCustomers[index];
                      return ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CustomerDetailsScreen(
                                customerId: customer['id'],
                                customerName: customer['name'] ?? '',
                              ),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.primaryRed,
                          child: Text(
                            (customer['name'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(color: AppColors.white, fontSize: 14),
                          ),
                        ),
                        title: Text(
                          customer['name'] ?? 'Unnamed',
                          style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                        ),
                        subtitle: customer['phone'] != null
                            ? Text(customer['phone'], style: TextStyle(color: AppColors.white.withOpacity(0.7)))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: AppColors.primaryRed, size: 20),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AddEditCustomerScreen(customerData: customer),
                                  ),
                                ).then((_) => _loadCustomers());
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                              onPressed: () => _deleteCustomer(customer['id'], customer['name'] ?? ''),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}