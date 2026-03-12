import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import 'add_edit_product_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({Key? key}) : super(key: key);

  @override
  _ProductListScreenState createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _syncService.dataChangedStream.listen((_) {
      _loadProducts();
    });
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    var products = await _dbHelper.query('products');
    products.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    setState(() {
      _products = products;
      _filteredProducts = products;
      _isLoading = false;
    });
  }

  void _filterProducts(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredProducts = _products;
      });
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredProducts = _products.where((p) {
        return (p['name'] ?? '').toLowerCase().contains(lowerQuery) ||
               (p['category'] ?? '').toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  Color _getStockColor(int stock, int minLevel) {
    if (stock <= 0) return AppColors.error;
    if (stock < minLevel) return AppColors.warning;
    return AppColors.success;
  }

  Future<void> _deleteProduct(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
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
    if (confirm == true) {
      await _dbHelper.delete('products', id);
      _loadProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        backgroundColor: AppColors.primaryRed,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddEditProductScreen()),
              ).then((_) => _loadProducts());
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
                hintText: 'Search products...',
                hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.white),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.white.withOpacity(0.1),
              ),
              onChanged: _filterProducts,
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
          onRefresh: _loadProducts,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredProducts.isEmpty
                  ? const Center(
                      child: Text('No products found.', style: TextStyle(color: AppColors.white)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filteredProducts.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.white, height: 0.5),
                      itemBuilder: (context, index) {
                        var product = _filteredProducts[index];
                        int stock = product['stock'] ?? 0;
                        int minLevel = product['minimumLevel'] ?? 5;
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: _getStockColor(stock, minLevel),
                            child: Text(
                              (product['name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: AppColors.white, fontSize: 14),
                            ),
                          ),
                          title: Text(
                            product['name'] ?? 'Unnamed',
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Row(
                            children: [
                              if (product['category'] != null)
                                Text(
                                  '${product['category']} · ',
                                  style: TextStyle(color: AppColors.white.withOpacity(0.7)),
                                ),
                              Text(
                                'Stock: $stock',
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
                                const Icon(Icons.warning, color: AppColors.warning, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'ETB ${(product['sellingPrice'] ?? 0).toStringAsFixed(0)}',
                                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit, color: AppColors.primaryRed, size: 20),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AddEditProductScreen(productData: product),
                                    ),
                                  ).then((_) => _loadProducts());
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                                onPressed: () => _deleteProduct(product['id'], product['name'] ?? ''),
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