import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_edit_supplier_screen.dart';
import 'supplier_materials_screen.dart';

class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({Key? key}) : super(key: key);

  @override
  _SupplierListScreenState createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _uiSuppliers = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _syncService.dataChangedStream.listen((_) {
      _loadSuppliers();
    });
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    var suppliers = await _dbHelper.query('suppliers');
    suppliers.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    setState(() {
      _suppliers = suppliers;
      _uiSuppliers = suppliers;
      _isLoading = false;
    });
  }

  void _filterSuppliers(String query) {
    if (query.isEmpty) {
      setState(() {
        _uiSuppliers = _suppliers;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _uiSuppliers = _suppliers.where((s) {
        return (s['name'] ?? '').toLowerCase().contains(lowerQuery) ||
               (s['phone'] ?? '').contains(query);
      }).toList();
    });
  }

  Future<void> _deleteSupplier(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
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

    // Optimistic update
    setState(() {
      _uiSuppliers.removeWhere((s) => s['id'] == id);
    });

    try {
      await _dbHelper.delete('suppliers', id);
      _suppliers.removeWhere((s) => s['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Supplier deleted');
    } catch (e) {
      setState(() {
        _uiSuppliers = List.from(_suppliers);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddEditSupplierScreen()),
              ).then((_) => _loadSuppliers());
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
                hintText: 'Search suppliers...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterSuppliers,
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
          onRefresh: _loadSuppliers,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiSuppliers.isEmpty
                  ? const Center(
                      child: Text('No suppliers found.', style: TextStyle(color: AppColors.white)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _uiSuppliers.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var supplier = _uiSuppliers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primaryRed,
                            child: Text(
                              (supplier['name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: AppColors.white, fontSize: 14),
                            ),
                          ),
                          title: Text(
                            supplier['name'] ?? 'Unnamed',
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: supplier['phone'] != null
                              ? Text(
                                  supplier['phone'],
                                  style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.link, color: AppColors.info, size: 20),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SupplierMaterialsScreen(
                                        supplierId: supplier['id'],
                                        supplierName: supplier['name'] ?? '',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: AppColors.primaryRed, size: 20),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AddEditSupplierScreen(supplierData: supplier),
                                    ),
                                  ).then((_) => _loadSuppliers());
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                                onPressed: () => _deleteSupplier(supplier['id'], supplier['name'] ?? ''),
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