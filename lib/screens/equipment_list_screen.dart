import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/error_handler.dart';
import 'add_edit_equipment_screen.dart';
import 'equipment_details_screen.dart';
import 'vehicle_details_screen.dart';
import 'checkout_logs_screen.dart';

class EquipmentListScreen extends StatefulWidget {
  const EquipmentListScreen({Key? key}) : super(key: key);

  @override
  _EquipmentListScreenState createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _equipment = [];
  List<Map<String, dynamic>> _uiEquipment = [];
  bool _isLoading = true;
  String _filterType = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEquipment();
    _syncService.dataChangedStream.listen((_) {
      _loadEquipment();
    });
  }

  Future<void> _loadEquipment() async {
    setState(() => _isLoading = true);
    var equipment = await _dbHelper.query('equipment');
    equipment.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    setState(() {
      _equipment = equipment;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    var filtered = _equipment;
    
    // Apply type filter
    if (_filterType != 'all') {
      filtered = filtered.where((e) => e['type'] == _filterType).toList();
    }
    
    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((e) {
        return (e['name'] ?? '').toLowerCase().contains(query) ||
               (e['serialNumber'] ?? '').toLowerCase().contains(query) ||
               (e['licensePlate'] ?? '').toLowerCase().contains(query);
      }).toList();
    }
    
    setState(() {
      _uiEquipment = filtered;
    });
  }

  void _filterByType(String? value) {
    setState(() {
      _filterType = value ?? 'all';
      _applyFilters();
    });
  }

  void _search(String query) {
    _applyFilters();
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'machine': return AppColors.info;
      case 'tool': return AppColors.warning;
      case 'vehicle': return AppColors.success;
      default: return AppColors.mediumGrey;
    }
  }

  Future<String> _getEmployeeName(String? employeeId) async {
    if (employeeId == null) return 'Unassigned';
    var user = await _dbHelper.queryById('users', employeeId);
    return user?['name'] ?? 'Unknown';
  }

  Future<void> _deleteEquipment(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Equipment'),
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
      _uiEquipment.removeWhere((e) => e['id'] == id);
    });

    try {
      await _dbHelper.delete('equipment', id);
      _equipment.removeWhere((e) => e['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Equipment deleted');
    } catch (e) {
      setState(() {
        _uiEquipment = List.from(_equipment);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddEditEquipmentScreen()),
              ).then((_) => _loadEquipment());
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
                    hintText: 'Search equipment...',
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
              Container(
                color: AppColors.primaryRedDark,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Text('Type:', style: TextStyle(color: AppColors.white)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _filterType,
                        dropdownColor: AppColors.backgroundStart,
                        style: const TextStyle(color: AppColors.white),
                        underline: Container(),
                        icon: const Icon(Icons.arrow_drop_down, color: AppColors.white),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'machine', child: Text('Machines')),
                          DropdownMenuItem(value: 'tool', child: Text('Tools')),
                          DropdownMenuItem(value: 'vehicle', child: Text('Vehicles')),
                        ],
                        onChanged: _filterByType,
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
          onRefresh: _loadEquipment,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiEquipment.isEmpty
                  ? const Center(
                      child: Text('No equipment found.', style: TextStyle(color: AppColors.white)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _uiEquipment.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var item = _uiEquipment[index];
                        return FutureBuilder<String>(
                          future: _getEmployeeName(item['assignedTo']),
                          builder: (context, assigneeSnapshot) {
                            return ListTile(
                              onTap: () {
                                if (item['type'] == 'vehicle') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VehicleDetailsScreen(vehicleId: item['id']),
                                    ),
                                  );
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EquipmentDetailsScreen(equipmentId: item['id']),
                                    ),
                                  );
                                }
                              },
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: _getTypeColor(item['type']),
                                child: Icon(
                                  item['type'] == 'vehicle' ? Icons.directions_car : Icons.settings,
                                  color: AppColors.white,
                                  size: 18,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['name'] ?? 'Unnamed',
                                      style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: item['status'] == 'active'
                                          ? AppColors.success
                                          : item['status'] == 'maintenance'
                                              ? AppColors.warning
                                              : AppColors.error,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      item['status'] ?? 'unknown',
                                      style: const TextStyle(color: AppColors.white, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  if (item['type'] == 'vehicle' && item['licensePlate'] != null)
                                    Text(
                                      '${item['licensePlate']} · ',
                                      style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                                    ),
                                  Expanded(
                                    child: Text(
                                      assigneeSnapshot.data ?? 'Loading...',
                                      style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.history, color: AppColors.info, size: 20),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => CheckoutLogsScreen(
                                            equipmentId: item['id'],
                                            equipmentName: item['name'] ?? '',
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
                                          builder: (context) => AddEditEquipmentScreen(equipmentData: item),
                                        ),
                                      ).then((_) => _loadEquipment());
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                                    onPressed: () => _deleteEquipment(item['id'], item['name'] ?? ''),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
      ),
    );
  }
}