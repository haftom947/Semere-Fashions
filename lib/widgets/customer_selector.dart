import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class CustomerSelector extends StatefulWidget {
  final Function(String customerId, String customerName) onCustomerSelected;
  const CustomerSelector({Key? key, required this.onCustomerSelected}) : super(key: key);

  @override
  _CustomerSelectorState createState() => _CustomerSelectorState();
}

class _CustomerSelectorState extends State<CustomerSelector> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  String? _selectedCustomerId;
  String _selectedCustomerName = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newNameController = TextEditingController();
  final TextEditingController _newPhoneController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recentCustomers = [];

  @override
  void initState() {
    super.initState();
    _loadRecentCustomers();
  }

  Future<void> _loadRecentCustomers() async {
    var allCustomers = await _dbHelper.query('customers');
    allCustomers.sort((a, b) => (b['createdAt'] ?? 0).compareTo(a['createdAt'] ?? 0));
    setState(() {
      _recentCustomers = allCustomers.take(2).toList(); // Show only 2 recent customers
    });
  }

  void _filterCustomers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    var allCustomers = await _dbHelper.query('customers');
    setState(() {
      _searchResults = allCustomers.where((c) =>
        (c['name'] ?? '').toLowerCase().contains(query.toLowerCase()) ||
        (c['phone'] ?? '').contains(query)
      ).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Customer', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_selectedCustomerId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedCustomerName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedCustomerId = null;
                      _selectedCustomerName = '';
                    });
                    widget.onCustomerSelected('', '');
                  },
                  child: const Text('Change', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.white.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                // Search field
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      hintText: 'Search customer...',
                      hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.search, color: AppColors.white, size: 20),
                      border: InputBorder.none,
                    ),
                    onChanged: _filterCustomers,
                  ),
                ),

                // Recent customers (only if search is empty)
                if (_searchController.text.isEmpty && _recentCustomers.isNotEmpty) ...[
                  const Divider(color: AppColors.white, height: 1, thickness: 0.5),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Recent', style: TextStyle(color: AppColors.white, fontSize: 12)),
                  ),
                  ..._recentCustomers.map((c) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primaryRed,
                      child: Text(
                        (c['name'] ?? '?')[0].toUpperCase(),
                        style: const TextStyle(color: AppColors.white, fontSize: 12),
                      ),
                    ),
                    title: Text(c['name'] ?? '', style: const TextStyle(color: AppColors.white, fontSize: 14)),
                    subtitle: c['phone'] != null
                        ? Text(c['phone'], style: TextStyle(color: AppColors.white.withOpacity(0.7), fontSize: 12))
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedCustomerId = c['id'];
                        _selectedCustomerName = c['name'] ?? '';
                      });
                      widget.onCustomerSelected(c['id'], c['name'] ?? '');
                    },
                  )),
                ],

                // Search results
                if (_searchResults.isNotEmpty)
                  ..._searchResults.map((c) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primaryRed,
                      child: Text(
                        (c['name'] ?? '?')[0].toUpperCase(),
                        style: const TextStyle(color: AppColors.white, fontSize: 12),
                      ),
                    ),
                    title: Text(c['name'] ?? '', style: const TextStyle(color: AppColors.white, fontSize: 14)),
                    subtitle: c['phone'] != null
                        ? Text(c['phone'], style: TextStyle(color: AppColors.white.withOpacity(0.7), fontSize: 12))
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedCustomerId = c['id'];
                        _selectedCustomerName = c['name'] ?? '';
                      });
                      widget.onCustomerSelected(c['id'], c['name'] ?? '');
                    },
                  )),

                // Add new customer button
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextButton.icon(
                    onPressed: _showAddCustomerDialog,
                    icon: const Icon(Icons.add, color: AppColors.white, size: 18),
                    label: const Text('Add new customer', style: TextStyle(color: AppColors.white)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showAddCustomerDialog() {
    _newNameController.clear();
    _newPhoneController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newNameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                hintText: 'Enter customer name',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPhoneController,
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: 'Enter phone number',
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_newNameController.text.trim().isEmpty) return;
              try {
                String id = DateTime.now().millisecondsSinceEpoch.toString();
                Map<String, dynamic> data = {
                  'id': id,
                  'name': _newNameController.text.trim(),
                  'phone': _newPhoneController.text.trim(),
                  'createdAt': DateTime.now().millisecondsSinceEpoch,
                };
                await _dbHelper.insert('customers', data);
                var connectivityResult = await Connectivity().checkConnectivity();
                if (connectivityResult != ConnectivityResult.none) {
                  _syncService.syncAll();
                }
                setState(() {
                  _selectedCustomerId = id;
                  _selectedCustomerName = _newNameController.text.trim();
                });
                widget.onCustomerSelected(id, _newNameController.text.trim());
                Navigator.pop(context);
                _loadRecentCustomers(); // refresh recent list
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}