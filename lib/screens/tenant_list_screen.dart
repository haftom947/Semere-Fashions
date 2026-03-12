import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_edit_tenant_screen.dart';
import 'rent_payment_screen.dart';

class TenantListScreen extends StatefulWidget {
  final String propertyId;
  final String propertyName;
  const TenantListScreen({Key? key, required this.propertyId, required this.propertyName}) : super(key: key);

  @override
  _TenantListScreenState createState() => _TenantListScreenState();
}

class _TenantListScreenState extends State<TenantListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _tenants = [];
  List<Map<String, dynamic>> _uiTenants = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTenants();
    _syncService.dataChangedStream.listen((_) {
      _loadTenants();
    });
  }

  Future<void> _loadTenants() async {
    setState(() => _isLoading = true);
    var allTenants = await _dbHelper.query('tenants');
    var filtered = allTenants.where((t) => t['propertyId'] == widget.propertyId).toList();
    filtered.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    setState(() {
      _tenants = filtered;
      _uiTenants = filtered;
      _isLoading = false;
    });
  }

  void _filterTenants(String query) {
    if (query.isEmpty) {
      setState(() {
        _uiTenants = _tenants;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _uiTenants = _tenants.where((t) {
        return (t['name'] ?? '').toLowerCase().contains(lowerQuery) ||
               (t['phone'] ?? '').contains(query);
      }).toList();
    });
  }

  Future<void> _deleteTenant(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tenant'),
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
      _uiTenants.removeWhere((t) => t['id'] == id);
    });

    try {
      await _dbHelper.delete('tenants', id);
      _tenants.removeWhere((t) => t['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Tenant deleted');
    } catch (e) {
      setState(() {
        _uiTenants = List.from(_tenants);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tenants - ${widget.propertyName}'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddEditTenantScreen(propertyId: widget.propertyId),
                ),
              ).then((_) => _loadTenants());
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
                hintText: 'Search tenants...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterTenants,
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
          onRefresh: _loadTenants,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiTenants.isEmpty
                  ? const Center(
                      child: Text('No tenants found.', style: TextStyle(color: AppColors.white)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _uiTenants.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var tenant = _uiTenants[index];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primaryRed,
                            child: Text(
                              (tenant['name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: AppColors.white, fontSize: 14),
                            ),
                          ),
                          title: Text(
                            tenant['name'] ?? 'Unnamed',
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Row(
                            children: [
                              if (tenant['phone'] != null)
                                Text(
                                  '${tenant['phone']} · ',
                                  style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                                ),
                              Text(
                                'ETB ${(tenant['monthlyRent'] ?? 0).toStringAsFixed(0)}/mo',
                                style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.payment, color: AppColors.success, size: 20),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => RentPaymentScreen(
                                        tenantId: tenant['id'],
                                        tenantName: tenant['name'] ?? '',
                                        monthlyRent: (tenant['monthlyRent'] as num?)?.toDouble() ?? 0,
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
                                      builder: (context) => AddEditTenantScreen(
                                        propertyId: widget.propertyId,
                                        tenantData: tenant,
                                      ),
                                    ),
                                  ).then((_) => _loadTenants());
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                                onPressed: () => _deleteTenant(tenant['id'], tenant['name'] ?? ''),
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