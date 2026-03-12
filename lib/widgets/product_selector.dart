import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';

class ProductSelector extends StatefulWidget {
  final Function(Map<String, dynamic> product) onProductSelected;
  const ProductSelector({super.key, required this.onProductSelected});

  @override
  _ProductSelectorState createState() => _ProductSelectorState();
}

class _ProductSelectorState extends State<ProductSelector> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recentProducts = [];

  @override
  void initState() {
    super.initState();
    _loadRecentProducts();
  }

  Future<void> _loadRecentProducts() async {
    var allProducts = await _dbHelper.query('products');
    allProducts.sort((a, b) => (b['createdAt'] ?? 0).compareTo(a['createdAt'] ?? 0));
    setState(() {
      _recentProducts = allProducts.take(2).toList();
    });
  }

  void _filterProducts(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    var allProducts = await _dbHelper.query('products');
    setState(() {
      _searchResults = allProducts.where((p) =>
        (p['name'] ?? '').toLowerCase().contains(query.toLowerCase())
      ).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add Product', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.white.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              // Search field
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    hintStyle: TextStyle(color: AppColors.white.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.search, color: AppColors.white, size: 20),
                    border: InputBorder.none,
                  ),
                  onChanged: _filterProducts,
                ),
              ),

              // Recent products (only if search is empty)
              if (_searchController.text.isEmpty && _recentProducts.isNotEmpty) ...[
                const Divider(color: AppColors.white, height: 1, thickness: 0.5),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Recent', style: TextStyle(color: AppColors.white, fontSize: 12)),
                ),
                ..._recentProducts.map((p) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryRed,
                    child: Text(
                      (p['name'] ?? '?')[0].toUpperCase(),
                      style: const TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ),
                  title: Text(p['name'] ?? '', style: const TextStyle(color: AppColors.white, fontSize: 14)),
                  subtitle: Text(
                    'ETB ${(p['sellingPrice'] ?? 0).toStringAsFixed(0)}',
                    style: TextStyle(color: AppColors.white.withOpacity(0.7), fontSize: 12),
                  ),
                  onTap: () {
                    widget.onProductSelected(p);
                    _searchController.clear();
                    _filterProducts('');
                  },
                )),
              ],

              // Search results
              if (_searchResults.isNotEmpty)
                ..._searchResults.map((p) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryRed,
                    child: Text(
                      (p['name'] ?? '?')[0].toUpperCase(),
                      style: const TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ),
                  title: Text(p['name'] ?? '', style: const TextStyle(color: AppColors.white, fontSize: 14)),
                  subtitle: Text(
                    'ETB ${(p['sellingPrice'] ?? 0).toStringAsFixed(0)}',
                    style: TextStyle(color: AppColors.white.withOpacity(0.7), fontSize: 12),
                  ),
                  onTap: () {
                    widget.onProductSelected(p);
                    _searchController.clear();
                    _filterProducts('');
                  },
                )),
            ],
          ),
        ),
      ],
    );
  }
}