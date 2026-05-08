import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class SupplierMaterialsScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;
  const SupplierMaterialsScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  _SupplierMaterialsScreenState createState() =>
      _SupplierMaterialsScreenState();
}

class _SupplierMaterialsScreenState extends State<SupplierMaterialsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _links = [];
  List<Map<String, dynamic>> _materials = [];
  Set<String> _selectedMaterialIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    var materials = await _dbHelper.query('materials');
    var allLinks = await _dbHelper.query('supplier_materials');
    var filteredLinks = allLinks
        .where((l) => l['supplierId'] == widget.supplierId)
        .toList();
    setState(() {
      _materials = materials;
      _links = filteredLinks;
      _selectedMaterialIds = _links.map((l) => l['materialId']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
      _isLoading = false;
    });
  }
  Future<void> _saveLinks() async {
    setState(() => _isLoading = true);
    try {
      final existingIds = _links.map((l) => l['materialId']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();

      final toAdd = _selectedMaterialIds.difference(existingIds);
      final toRemove = existingIds.difference(_selectedMaterialIds);

      // Remove links
      var allLinks = await _dbHelper.query('supplier_materials');
      for (final rem in toRemove) {
        final existing = allLinks.firstWhere(
          (l) => l['supplierId'] == widget.supplierId && (l['materialId']?.toString() ?? '') == rem,
          orElse: () => <String, dynamic>{},
        );
        if (existing.isNotEmpty) {
          await _dbHelper.delete('supplier_materials', existing['id']);
        }
      }

      // Add links
      final now = DateTime.now().millisecondsSinceEpoch;
      // Ensure missing column exists on older DBs (safe no-op if present)
      try {
        final db = await _dbHelper.database;
        await db.execute(
            "ALTER TABLE supplier_materials ADD COLUMN changed_fields TEXT");
      } catch (_) {}

      for (final add in toAdd) {
        await _dbHelper.insert('supplier_materials', {
          'id': '${now}_$add',
          'supplierId': widget.supplierId,
          'materialId': add,
          'notes': '',
          'syncStatus': 'pending',
          'lastModified': now,
        });
      }

      await _syncService.syncAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier links updated')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving links: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Materials - ${widget.supplierName}'),
        backgroundColor: AppColors.primaryRed,
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
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _materials.length,
                      itemBuilder: (context, index) {
                        var material = _materials[index];
                        final mid = material['id']?.toString() ?? '';
                        return CheckboxListTile(
                          title: Text(
                            material['name'] ?? '',
                            style: const TextStyle(color: AppColors.white),
                          ),
                          subtitle: Text(
                            'Unit: ${material['unit'] ?? ''}',
                            style: TextStyle(
                                color: AppColors.white.withOpacity(0.7)),
                          ),
                          value: _selectedMaterialIds.contains(mid),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedMaterialIds.add(mid);
                              } else {
                                _selectedMaterialIds.remove(mid);
                              }
                            });
                          },
                          activeColor: AppColors.primaryRed,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveLinks,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: AppColors.white)
                            : const Text('Save'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
