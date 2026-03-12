import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/error_handler.dart';

class PurchaseOrderDetailsScreen extends StatefulWidget {
  final String poId;
  const PurchaseOrderDetailsScreen({Key? key, required this.poId}) : super(key: key);

  @override
  _PurchaseOrderDetailsScreenState createState() => _PurchaseOrderDetailsScreenState();
}

class _PurchaseOrderDetailsScreenState extends State<PurchaseOrderDetailsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Map<String, dynamic>? _po;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncService.dataChangedStream.listen((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _po = await _dbHelper.queryById('purchase_orders', widget.poId);
    if (_po != null) {
      var allItems = await _dbHelper.query('purchase_order_items');
      _items = allItems.where((item) => item['poId'] == widget.poId).toList();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_po == null) return;
    setState(() => _isLoading = true);
    _po!['status'] = newStatus;
    await _dbHelper.update('purchase_orders', _po!);

    // If status is 'received', update inventory
    if (newStatus == 'received') {
      await _receiveItems();
    }

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
      _syncService.syncAll();
    }
    _loadData();
  }

  Future<void> _receiveItems() async {
    for (var item in _items) {
      String table = item['itemType'] == 'product' ? 'products' : 'materials';
      var existingItem = await _dbHelper.queryById(table, item['itemId']);

      if (existingItem != null) {
        // Item exists, just add quantity
        existingItem['stock'] = (existingItem['stock'] as int) + item['quantity'];
        await _dbHelper.update(table, existingItem);
      } else {
        // Item does not exist – prompt user to create it
        bool? created = await _showCreateItemDialog(item);
        if (created != true) {
          // User cancelled creation – maybe abort receiving? For now, skip this item.
          ErrorHandler.showWarning(context, 'Skipped item ${item['itemName']}');
        }
      }
    }
    ErrorHandler.showSuccess(context, 'Purchase order received');
  }

  Future<bool?> _showCreateItemDialog(Map<String, dynamic> item) async {
    final nameController = TextEditingController(text: item['itemName']);
    final unitController = TextEditingController();
    final costPriceController = TextEditingController(text: item['unitPrice']?.toString() ?? '');
    final sellingPriceController = TextEditingController();
    final stockController = TextEditingController(text: item['quantity'].toString());
    final minLevelController = TextEditingController();

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New ${item['itemType'] == 'product' ? 'Product' : 'Material'}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name *'),
              ),
              const SizedBox(height: 8),
              if (item['itemType'] == 'material') ...[
                DropdownButtonFormField<String>(
                  value: unitController.text.isEmpty ? null : unitController.text,
                  items: const [
                    DropdownMenuItem(value: 'meter', child: Text('meter')),
                    DropdownMenuItem(value: 'piece', child: Text('piece')),
                    DropdownMenuItem(value: 'box', child: Text('box')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'liter', child: Text('liter')),
                  ],
                  onChanged: (value) => unitController.text = value!,
                  decoration: const InputDecoration(labelText: 'Unit *'),
                ),
                const SizedBox(height: 8),
              ],
              if (item['itemType'] == 'product') ...[
                TextFormField(
                  controller: costPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cost Price (ETB)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: sellingPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Selling Price (ETB)'),
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Initial Stock'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: minLevelController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minimum Level'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Basic validation
              if (nameController.text.isEmpty) return;
              if (item['itemType'] == 'material' && unitController.text.isEmpty) return;

              Map<String, dynamic> newItem = {
                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                'name': nameController.text.trim(),
                if (item['itemType'] == 'product') ...{
                  'category': '',
                  'costPrice': double.tryParse(costPriceController.text) ?? 0,
                  'sellingPrice': double.tryParse(sellingPriceController.text) ?? 0,
                  'stock': int.tryParse(stockController.text) ?? 0,
                  'minimumLevel': int.tryParse(minLevelController.text) ?? 5,
                } else ...{
                  'category': '',
                  'unit': unitController.text,
                  'stock': int.tryParse(stockController.text) ?? 0,
                  'minimumLevel': int.tryParse(minLevelController.text) ?? 5,
                },
              };

              await _dbHelper.insert(item['itemType'] == 'product' ? 'products' : 'materials', newItem);
              Navigator.pop(context, true);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'draft': return AppColors.mediumGrey;
      case 'ordered': return AppColors.info;
      case 'received': return AppColors.success;
      case 'cancelled': return AppColors.error;
      default: return AppColors.mediumGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Order Details'),
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
            : _po == null
                ? const Center(child: Text('Purchase order not found', style: TextStyle(color: AppColors.white)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PO ID: ${_po!['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text('Supplier: ${_po!['supplierName']}'),
                              Text('Order Date: ${DateTime.fromMillisecondsSinceEpoch(_po!['orderDate']).toLocal()}'),
                              if (_po!['expectedDate'] != null)
                                Text('Expected: ${DateTime.fromMillisecondsSinceEpoch(_po!['expectedDate']).toLocal()}'),
                              Text('Status: ${_po!['status']}'),
                              if (_po!['notes'] != null) Text('Notes: ${_po!['notes']}'),
                              Text('Total: ETB ${(_po!['totalAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      const Text('Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white)),
                      const SizedBox(height: 8),
                      ..._items.map((item) => Card(
                        child: ListTile(
                          title: Text(item['itemName']),
                          subtitle: Text('${item['quantity']} x ${item['unitPrice']}'),
                          trailing: Text('ETB ${(item['quantity'] * item['unitPrice']).toStringAsFixed(0)}'),
                        ),
                      )),

                      const SizedBox(height: 24),

                      // Status update buttons
                      if (_po!['status'] == 'ordered')
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _updateStatus('received'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: AppColors.white,
                                ),
                                child: const Text('Mark Received'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _updateStatus('cancelled'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  foregroundColor: AppColors.white,
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
      ),
    );
  }
}