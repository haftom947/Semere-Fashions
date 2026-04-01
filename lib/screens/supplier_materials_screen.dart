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
      _isLoading = false;
    });
  }

  Future<void> _toggleLink(String materialId) async {
    var existing = _links.firstWhere(
      (l) => l['materialId'] == materialId,
      orElse: () => <String, dynamic>{},
    );
    if (existing.isNotEmpty) {
      // Remove link
      await _dbHelper.delete('supplier_materials', existing['id']);
    } else {
      // Add link
      await _dbHelper.insert('supplier_materials', {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'supplierId': widget.supplierId,
        'materialId': materialId,
        'notes': '',
      });
    }
    _loadData();
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
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _materials.length,
                itemBuilder: (context, index) {
                  var material = _materials[index];
                  bool isLinked = _links.any(
                    (l) => l['materialId'] == material['id'],
                  );
                  return CheckboxListTile(
                    title: Text(
                      material['name'] ?? '',
                      style: const TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      'Unit: ${material['unit'] ?? ''}',
                      style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                    ),
                    value: isLinked,
                    onChanged: (_) => _toggleLink(material['id']),
                    activeColor: AppColors.primaryRed,
                  );
                },
              ),
      ),
    );
  }
}
