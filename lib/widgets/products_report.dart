import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/database_helper.dart';
import '../services/pdf_generator.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class ProductsReport extends StatefulWidget {
  const ProductsReport({Key? key}) : super(key: key);

  @override
  _ProductsReportState createState() => _ProductsReportState();
}

class _ProductsReportState extends State<ProductsReport> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  List<Map<String, dynamic>> _topProducts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    var products = await _dbHelper.query('products');
    var orders = await _dbHelper.query('orders');
    setState(() {
      _products = products;
      _orders = orders;
      _calculateTopProducts();
      _isLoading = false;
    });
  }

  void _calculateTopProducts() {
    Map<String, Map<String, dynamic>> productMap = {};
    for (var order in _orders) {
      List items = order['items'] as List? ?? [];
      for (var item in items) {
        String desc = item['description'] ?? 'Unknown';
        if (!productMap.containsKey(desc)) {
          productMap[desc] = {'name': desc, 'quantity': 0, 'revenue': 0.0};
        }
        productMap[desc]!['quantity'] = productMap[desc]!['quantity'] + (item['quantity'] as int);
        productMap[desc]!['revenue'] = productMap[desc]!['revenue'] + ((item['price'] as double) * (item['quantity'] as int));
      }
    }
    var list = productMap.values.toList();
    list.sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int));
    _topProducts = list.take(5).toList();
  }

  Future<void> _exportPDF() async {
    try {
      final pdf = await PdfGenerator.generateProductsReport(_products, _topProducts);
      await Printing.sharePdf(bytes: pdf, filename: 'products_report.pdf');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'PDF export failed: $e');
    }
  }

  Future<void> _exportExcel() async {
    ErrorHandler.showWarning(context, 'Excel export coming soon');
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary cards
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('Products', _products.length.toString(), Icons.category),
                      _buildStatItem('Low Stock', _products.where((p) => (p['stock'] ?? 0) < (p['minimumLevel'] ?? 5)).length.toString(), Icons.warning),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Top products list
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top 5 Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_topProducts.isEmpty)
                        const Center(child: Text('No product sales data'))
                      else
                        ..._topProducts.map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                              ),
                              Text('${p['quantity']} sold'),
                              const SizedBox(width: 16),
                              Text('ETB ${p['revenue'].toStringAsFixed(0)}'),
                            ],
                          ),
                        )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Export card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Export Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildExportButton(
                            icon: Icons.picture_as_pdf,
                            label: 'PDF',
                            color: AppColors.error,
                            onTap: _exportPDF,
                          ),
                          _buildExportButton(
                            icon: Icons.table_chart,
                            label: 'Excel',
                            color: AppColors.success,
                            onTap: _exportExcel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryRed),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildExportButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}