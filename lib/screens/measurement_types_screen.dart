import 'package:flutter/material.dart';
import 'package:reorderables/reorderables.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class MeasurementTypesScreen extends StatefulWidget {
  const MeasurementTypesScreen({Key? key}) : super(key: key);

  @override
  _MeasurementTypesScreenState createState() => _MeasurementTypesScreenState();
}

class _MeasurementTypesScreenState extends State<MeasurementTypesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _filteredTypes = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTypes();
    _syncService.dataChangedStream.listen((_) {
      _loadTypes();
    });
  }

  Future<void> _loadTypes() async {
    setState(() => _isLoading = true);
    var types = await _dbHelper.query('measurement_types');
    types.sort((a, b) => (a['sortOrder'] ?? 0).compareTo(b['sortOrder'] ?? 0));
    setState(() {
      _types = types;
      _filteredTypes = types;
      _isLoading = false;
    });
  }

  void _filterTypes(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredTypes = _types;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredTypes = _types.where((t) {
        return (t['name'] ?? '').toLowerCase().contains(lowerQuery) ||
               (t['unit'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _addType() async {
    final nameController = TextEditingController();
    final unitController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.light(),
          child: AlertDialog(
            title: const Text('Add Measurement Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter a name (e.g., "Chest") and optionally a unit (e.g., "cm", "inches").',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    hintText: 'e.g., Chest, Waist, Height',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit (optional)',
                    hintText: 'e.g., cm, inches',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
    if (result == true) {
      int maxSort = _types.isEmpty ? 0 : (_types.map((e) => e['sortOrder'] as int? ?? 0).reduce((a, b) => a > b ? a : b));
      await _dbHelper.insert('measurement_types', {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': nameController.text.trim(),
        'unit': unitController.text.trim(),
        'sortOrder': maxSort + 1,
      });
      _loadTypes();
    }
  }

  Future<void> _editType(Map<String, dynamic> type) async {
    final nameController = TextEditingController(text: type['name']);
    final unitController = TextEditingController(text: type['unit']);
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.light(),
          child: AlertDialog(
            title: const Text('Edit Measurement Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result == true) {
      type['name'] = nameController.text.trim();
      type['unit'] = unitController.text.trim();
      await _dbHelper.update('measurement_types', type);
      _loadTypes();
    }
  }

  Future<void> _deleteType(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Type'),
        content: const Text('Are you sure? This will also delete all measurements of this type.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _dbHelper.delete('measurement_types', id);
      _loadTypes();
    }
  }

  void _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _filteredTypes.removeAt(oldIndex);
      _filteredTypes.insert(newIndex, item);
      // Also reorder the original list to keep sync
      final originalItem = _types.firstWhere((t) => t['id'] == item['id']);
      _types.remove(originalItem);
      _types.insert(newIndex, originalItem);
      for (int i = 0; i < _types.length; i++) {
        _types[i]['sortOrder'] = i;
      }
    });
    for (var type in _types) {
      await _dbHelper.update('measurement_types', type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Measurement Types'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search types...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterTypes,
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
            : _filteredTypes.isEmpty
                ? const Center(
                    child: Text('No measurement types found.', style: TextStyle(color: AppColors.white)),
                  )
                : ReorderableListView(
                    padding: const EdgeInsets.all(8),
                    onReorder: _onReorder,
                    children: _filteredTypes.map((type) {
                      return Card(
                        key: ValueKey(type['id']),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.drag_handle, color: AppColors.white),
                          title: Text(
                            type['name'],
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: type['unit']?.isNotEmpty == true
                              ? Text('Unit: ${type['unit']}', style: TextStyle(color: AppColors.white.withOpacity(0.7)))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: AppColors.primaryRed, size: 20),
                                onPressed: () => _editType(type),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                                onPressed: () => _deleteType(type['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addType,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add),
      ),
    );
  }
}