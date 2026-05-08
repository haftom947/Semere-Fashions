import 'package:flutter/material.dart';
import 'dart:async';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'add_edit_material_screen.dart';

class MaterialListScreen extends StatefulWidget {
  const MaterialListScreen({Key? key}) : super(key: key);

  @override
  _MaterialListScreenState createState() => _MaterialListScreenState();
}

class _MaterialListScreenState extends State<MaterialListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _dataChangedSubscription;
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _uiMaterials = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMaterials();
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      if (mounted) _loadMaterials();
    });
  }

  @override
  void dispose() {
    _dataChangedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    setState(() => _isLoading = true);
    var materials = await _dbHelper.query('materials');
    _materials = List<Map<String, dynamic>>.from(materials);
    _applyFilters();
    setState(() => _isLoading = false);
  }

  void _applyFilters() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _uiMaterials = _materials;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _uiMaterials = _materials.where((m) {
        return (m['name'] ?? '').toLowerCase().contains(lowerQuery) ||
            (m['category'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  void _filterMaterials(String query) {
    _applyFilters();
  }

  Color _getStockColor(int stock, int minLevel) {
    if (stock <= 0) return AppColors.error;
    if (stock < minLevel) return AppColors.warning;
    return AppColors.success;
  }

  Future<void> _deleteMaterial(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Delete Material'),
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

    // Optimistic update
    setState(() {
      _uiMaterials.removeWhere((m) => m['id'] == id);
    });

    try {
      await _dbHelper.delete('materials', id);
      _materials.removeWhere((m) => m['id'] == id);
      _syncService.syncAll();
      if (mounted) ErrorHandler.showSuccess(context, 'Material deleted');
    } catch (e) {
      setState(() {
        _uiMaterials = List.from(_materials);
      });
      if (mounted) ErrorHandler.showError(context, 'Delete failed: $e');
    }
  }

  Future<void> _decrementStock(Map<String, dynamic> material) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Use Material', style: TextStyle(color: Colors.black)),
          content: Text('Mark one unit of ${material['name']} as used?', style: TextStyle(color: Colors.black)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.blue))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Use')),
          ],
        ),
      ),
    );
    if (confirm == true) {
      int currentStock = material['stock'] ?? 0;
      if (currentStock > 0) {
        var updatedMaterial = Map<String, dynamic>.from(material);
        updatedMaterial['stock'] = currentStock - 1;
        await _dbHelper.update('materials', updatedMaterial);

        double costPerUnit = (material['cost_per_unit'] ?? 0).toDouble();
        if (costPerUnit > 0) {
          await _dbHelper.insert('material_usage', {
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'material_id': material['id'],
            'quantity': 1,
            'cost': costPerUnit,
            'date': DateTime.now().millisecondsSinceEpoch,
            'notes': 'Used 1 unit of ${material['name']}',
            'type': 'general',
          });
        }

        _loadMaterials();
      } else {
        ErrorHandler.showError(context, 'Stock already zero');
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Materials'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddEditMaterialScreen(),
                ),
              ).then((_) => _loadMaterials());
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
                hintText: 'Search materials...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterMaterials,
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
          onRefresh: _loadMaterials,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _uiMaterials.isEmpty
                  ? const Center(
                      child: Text(
                        'No materials found.',
                        style: TextStyle(color: AppColors.white),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _uiMaterials.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var material = _uiMaterials[index];
                        int stock = material['stock'] ?? 0;
                        int minLevel = material['minimumLevel'] ?? 5;
                        String unit = material['unit'] ?? 'piece';
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: _getStockColor(stock, minLevel),
                            child: Text(
                              (material['name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: AppColors.white, fontSize: 14),
                            ),
                          ),
                          title: Text(
                            material['name'] ?? 'Unnamed',
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Row(
                            children: [
                              if (material['category'] != null)
                                Flexible(
                                  child: Text(
                                    '${material['category']} · ',
                                    style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Text(
                                'Stock: $stock $unit',
                                style: TextStyle(
                                  color: _getStockColor(stock, minLevel),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (stock < minLevel)
                                const Icon(
                                  Icons.warning,
                                  color: AppColors.warning,
                                  size: 16,
                                ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle,
                                  color: AppColors.warning,
                                  size: 20,
                                ),
                                onPressed: () => _decrementStock(material),
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
                                      builder: (context) => AddEditMaterialScreen(
                                        materialData: material,
                                      ),
                                    ),
                                  ).then((_) => _loadMaterials());
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: AppColors.error,
                                  size: 20,
                                ),
                                onPressed: () => _deleteMaterial(
                                  material['id'],
                                  material['name'] ?? '',
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
