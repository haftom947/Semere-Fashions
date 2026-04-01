import 'dart:async';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import 'product_list_screen.dart';
import 'material_list_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  _InventoryScreenState createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _dataChangedSubscription;
  List<Map<String, dynamic>> _lowStockItems = [];
  List<Map<String, dynamic>> _filteredLowStock = [];
  bool _isLoading = true;
  bool _hasShownAlert = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLowStock();
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      if (mounted) _loadLowStock();
    });
  }

  @override
  void dispose() {
    _dataChangedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLowStock() async {
    if (mounted) setState(() => _isLoading = true);
    var products = await _dbHelper.query('products');
    var materials = await _dbHelper.query('materials');

    List<Map<String, dynamic>> lowStock = [];

    for (var p in products) {
      int stock = p['stock'] ?? 0;
      int minLevel = p['minimumLevel'] ?? 5;
      if (stock < minLevel) {
        lowStock.add({
          ...p,
          'itemType': 'product',
          'displayName': '📦 ${p['name']}',
        });
      }
    }

    for (var m in materials) {
      int stock = m['stock'] ?? 0;
      int minLevel = m['minimumLevel'] ?? 5;
      if (stock < minLevel) {
        lowStock.add({
          ...m,
          'itemType': 'material',
          'displayName': '🧵 ${m['name']}',
        });
      }
    }

    lowStock.sort((a, b) {
      int aStock = a['stock'] ?? 0;
      int bStock = b['stock'] ?? 0;
      return aStock.compareTo(bStock);
    });

    if (mounted) {
      setState(() {
        _lowStockItems = lowStock;
        _filteredLowStock = lowStock;
        _isLoading = false;
      });
    }

    // Show snackbar if low stock exists and not shown yet
    if (lowStock.isNotEmpty && !_hasShownAlert && mounted) {
      ErrorHandler.showWarning(
        context,
        'Low stock alert: ${lowStock.length} item${lowStock.length > 1 ? 's' : ''} below minimum.',
      );
      _hasShownAlert = true;
    }
  }

  void _filterLowStock(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredLowStock = _lowStockItems;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredLowStock = _lowStockItems.where((item) {
        return (item['name'] ?? '').toLowerCase().contains(lowerQuery) ||
            (item['category'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  Color _getStockColor(int stock, int minLevel) {
    if (stock <= 0) return AppColors.error;
    if (stock < minLevel) return AppColors.warning;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: AppColors.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Search low stock items...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterLowStock,
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
          onRefresh: _loadLowStock,
          child: CustomScrollView(
            slivers: [
              // Quick action cards
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.2,
                  ),
                  delegate: SliverChildListDelegate([
                    _buildActionCard(
                      'Products',
                      Icons.shopping_bag,
                      AppColors.primaryRed,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProductListScreen(),
                        ),
                      ),
                    ),
                    _buildActionCard(
                      'Materials',
                      Icons.inventory,
                      AppColors.info,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MaterialListScreen(),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),

              // Low stock header
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Low Stock Items',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.white,
                        ),
                      ),
                      Text(
                        '${_filteredLowStock.length} items',
                        style: TextStyle(
                          color: AppColors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Low stock list
              _isLoading
                  ? const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _filteredLowStock.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 64,
                              color: AppColors.white.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'All stock levels are healthy',
                              style: TextStyle(color: AppColors.white),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        var item = _filteredLowStock[index];
                        int stock = item['stock'] ?? 0;
                        int minLevel = item['minimumLevel'] ?? 5;
                        Color stockColor = _getStockColor(stock, minLevel);
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: stockColor.withOpacity(0.2),
                              child: Text(
                                stock.toString(),
                                style: TextStyle(
                                  color: stockColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              item['name'] ?? 'Unnamed',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${item['itemType'] == 'product' ? 'Product' : 'Material'} · Min: $minLevel',
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.7),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.chevron_right,
                                color: AppColors.white,
                              ),
                              onPressed: () {
                                if (item['itemType'] == 'product') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProductListScreen(),
                                    ),
                                  );
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          MaterialListScreen(),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        );
                      }, childCount: _filteredLowStock.length),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.darkGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
