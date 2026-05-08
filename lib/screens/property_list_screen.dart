import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_edit_property_screen.dart';
import 'landlord_payment_screen.dart';
import 'tenant_list_screen.dart';

class PropertyListScreen extends StatefulWidget {
  const PropertyListScreen({Key? key}) : super(key: key);

  @override
  _PropertyListScreenState createState() => _PropertyListScreenState();
}

class _PropertyListScreenState extends State<PropertyListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _uiProperties = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProperties();
    _syncService.dataChangedStream.listen((_) {
      _loadProperties();
    });
  }

  Future<void> _loadProperties() async {
    setState(() => _isLoading = true);
    final properties = List<Map<String, dynamic>>.from(
      await _dbHelper.query('properties'),
    );
    properties.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    setState(() {
      _properties = properties;
      _uiProperties = properties;
      _isLoading = false;
    });
  }

  void _filterProperties(String query) {
    if (query.isEmpty) {
      setState(() {
        _uiProperties = _properties;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _uiProperties = _properties.where((p) {
        return (p['name'] ?? '').toLowerCase().contains(lowerQuery) ||
            (p['address'] ?? '').toLowerCase().contains(lowerQuery) ||
            (p['type'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  String _usageTypeOf(Map<String, dynamic> property) {
    final usage = property['usageType']?.toString();
    if (usage != null && usage.isNotEmpty) return usage;
    return property['ownership'] == 'leased' ? 'business_use' : 'rented_out';
  }

  String _usageLabel(String usageType) {
    switch (usageType) {
      case 'business_use':
        return 'Business Use';
      case 'rented_out':
      default:
        return 'Rented Out';
    }
  }

  String _rentLabel(Map<String, dynamic> property) {
    return _usageTypeOf(property) == 'business_use' ? 'Lease Cost' : 'Rent';
  }

  Color _getOwnershipColor(String? ownership) {
    return ownership == 'owned' ? AppColors.success : AppColors.warning;
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'vacant':
        return AppColors.success;
      case 'occupied':
        return AppColors.info;
      case 'maintenance':
        return AppColors.warning;
      default:
        return AppColors.mediumGrey;
    }
  }

  Future<void> _deleteProperty(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Delete Property'),
          content: Text('Are you sure you want to delete $name?'),
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

    setState(() {
      _uiProperties.removeWhere((p) => p['id'] == id);
    });

    try {
      await _dbHelper.delete('properties', id);
      _properties.removeWhere((p) => p['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Property deleted');
    } catch (e) {
      setState(() {
        _uiProperties = List.from(_properties);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Properties'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddEditPropertyScreen(),
                ),
              ).then((_) => _loadProperties());
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
                hintText: 'Search properties...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterProperties,
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
          onRefresh: _loadProperties,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiProperties.isEmpty
              ? const Center(
                  child: Text(
                    'No properties found.',
                    style: TextStyle(color: AppColors.white),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _uiProperties.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.white, height: 0.5),
                  itemBuilder: (context, index) {
                    final property = _uiProperties[index];
                    final usageType = _usageTypeOf(property);
                    final canManageTenants = usageType == 'rented_out';

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: _getOwnershipColor(
                          property['ownership'],
                        ),
                        child: Icon(
                          property['type'] == 'flat'
                              ? Icons.apartment
                              : Icons.store,
                          color: AppColors.white,
                          size: 16,
                        ),
                      ),
                      title: Text(
                        property['name'] ?? 'Unnamed',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${property['type']} - ${_usageLabel(usageType)} - ${property['ownership']}',
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.7),
                            ),
                          ),
                          Text(
                            '${_rentLabel(property)}: ETB ${(property['monthlyRent'] ?? 0).toStringAsFixed(0)}',
                            style: TextStyle(
                              color: AppColors.white.withOpacity(0.7),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getStatusColor(
                                    property['status'] ?? 'vacant',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                property['status'] ?? 'vacant',
                                style: TextStyle(
                                  color: AppColors.white.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((property['landlordName']?.toString().trim() ?? '')
                              .isNotEmpty)
                            IconButton(
                              icon: const Icon(
                                Icons.payments,
                                color: AppColors.success,
                                size: 20,
                              ),
                              tooltip: 'Pay Landlord',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LandlordPaymentScreen(
                                      propertyId: property['id'],
                                      propertyName: property['name'] ?? '',
                                      landlordName:
                                          property['landlordName'] ?? '',
                                      monthlyRent:
                                          (property['monthlyRent'] as num?)
                                              ?.toDouble() ??
                                          0,
                                    ),
                                  ),
                                ).then((_) => _loadProperties());
                              },
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.people,
                              color: AppColors.info,
                              size: 20,
                            ),
                            onPressed: canManageTenants
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TenantListScreen(
                                          propertyId: property['id'],
                                          propertyName: property['name'] ?? '',
                                        ),
                                      ),
                                    );
                                  }
                                : () {
                                    ErrorHandler.showWarning(
                                      context,
                                      'This property is marked as Business Use, so tenant management is disabled.',
                                    );
                                  },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: AppColors.primaryRed,
                              size: 20,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddEditPropertyScreen(
                                    propertyData: property,
                                  ),
                                ),
                              ).then((_) => _loadProperties());
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () => _deleteProperty(
                              property['id'],
                              property['name'] ?? '',
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
