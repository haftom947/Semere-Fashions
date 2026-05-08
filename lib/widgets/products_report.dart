import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_helper.dart';
import '../services/excel_generator.dart';
import '../services/pdf_generator.dart';
import '../utils/app_date_filter.dart';
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
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _bottomProducts = [];

  bool _isLoading = true;
  bool _showOnlyLowStock = false;
  String _selectedCategory = 'all';
  String _selectedBranchId = 'all';
  String _selectedCurrency = 'all';
  String _sortBy = 'quantity';

  double _totalStockValue = 0.0;
  double _totalProfit = 0.0;
  List<_ProductSection> _currencySections = [];

  @override
  void initState() {
    super.initState();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _loadData();
    _loadCategories();
    _loadBranches();
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    setState(() {
      _loadProductPerformance();
    });
  }

  Future<void> _loadData() async {
    final products = await _dbHelper.query('products');
    final orders = await _dbHelper.query('orders');
    if (!mounted) return;
    setState(() {
      _products = List<Map<String, dynamic>>.from(products);
      _orders = List<Map<String, dynamic>>.from(orders);
      _loadProductPerformance();
      _isLoading = false;
    });
  }

  Future<void> _loadCategories() async {
    final products = await _dbHelper.query('products');
    if (!mounted) return;
    final categories = products
        .map((product) => product['category']?.toString() ?? '')
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    setState(() {
      _categories = categories.map((category) => {'name': category}).toList();
    });
  }

  Future<void> _loadBranches() async {
    final branches = await _dbHelper.query('branches');
    if (!mounted) return;
    setState(() {
      _branches = List<Map<String, dynamic>>.from(branches);
    });
  }

  List<String> _availableCurrencies() {
    final currencies = _orders
        .map((order) => order['currency']?.toString().trim() ?? '')
        .where((currency) => currency.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return currencies;
  }

  void _loadProductPerformance() {
    if (_selectedCurrency == 'all') {
      _currencySections = _availableCurrencies()
          .map((currency) => _buildProductSection(currency))
          .toList();
      _filteredProducts = [];
      _topProducts = [];
      _bottomProducts = [];
      _totalStockValue = 0.0;
      _totalProfit = 0.0;
      return;
    }

    _currencySections = [];
    final section = _buildProductSection(_selectedCurrency);
    _filteredProducts = section.products;
    _topProducts = section.topProducts;
    _bottomProducts = section.bottomProducts;
    _totalStockValue = section.totalStockValue;
    _totalProfit = section.totalProfit;
  }

  _ProductSection _buildProductSection(String currency) {
    final range = AppDateFilter.instance.range;
    final startMillis = range == null
        ? 0
        : DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          ).millisecondsSinceEpoch;
    final endMillis = range == null
        ? DateTime.now().millisecondsSinceEpoch
        : DateTime(
            range.end.year,
            range.end.month,
            range.end.day,
            23,
            59,
            59,
            999,
          ).millisecondsSinceEpoch;

    final productMap = <String, Map<String, dynamic>>{
      for (final product in _products)
        if ((product['id']?.toString() ?? '').isNotEmpty)
          product['id'].toString(): {
            ...Map<String, dynamic>.from(product),
            'quantitySold': 0.0,
            'revenue': 0.0,
            'cogs': 0.0,
            'profit': 0.0,
            'stockValue':
                ((product['stock'] as num?)?.toDouble() ?? 0.0) *
                ((product['costPrice'] as num?)?.toDouble() ?? 0.0),
          },
    };

    for (final order in _orders) {
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      if (status == 'cancelled') continue;
      final createdAt = (order['createdAt'] as num?)?.toInt() ?? 0;
      if (createdAt < startMillis || createdAt > endMillis) continue;
      if (_selectedBranchId != 'all' &&
          order['branchId']?.toString() != _selectedBranchId) {
        continue;
      }
      if (order['currency']?.toString() != currency) continue;

      final rawItems = order['items'];
      final items = rawItems is String
          ? List<dynamic>.from(jsonDecode(rawItems) as List<dynamic>)
          : List<dynamic>.from(rawItems as List? ?? const []);

      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final productId = item['productId']?.toString();
        if (productId == null || productId.isEmpty) continue;
        final product = productMap[productId];
        if (product == null) continue;

        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final sellingPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
        final costPrice = (product['costPrice'] as num?)?.toDouble() ?? 0.0;
        final revenue = quantity * sellingPrice;
        final cogs = quantity * costPrice;

        product['currency'] = currency;
        product['quantitySold'] = (product['quantitySold'] as double) + quantity;
        product['revenue'] = (product['revenue'] as double) + revenue;
        product['cogs'] = (product['cogs'] as double) + cogs;
        product['profit'] = (product['profit'] as double) + (revenue - cogs);
      }
    }

    var list = productMap.values.toList();
    list = list.where((product) {
      if (_selectedCategory != 'all' &&
          product['category']?.toString() != _selectedCategory) {
        return false;
      }
      if (_selectedBranchId != 'all') {
        final productBranchId = product['branchId']?.toString() ?? '';
        if (productBranchId.isNotEmpty && productBranchId != _selectedBranchId) {
          return false;
        }
      }
      if (_showOnlyLowStock) {
        final stock = (product['stock'] as num?)?.toDouble() ?? 0.0;
        final minimumLevel =
            (product['minimumLevel'] as num?)?.toDouble() ?? 5.0;
        if (stock >= minimumLevel) return false;
      }
      return true;
    }).toList();

    _sortProducts(_sortBy, products: list, updateState: false);

    final topProducts = List<Map<String, dynamic>>.from(list.take(5));
    final bottom = List<Map<String, dynamic>>.from(list.reversed.take(5).toList())
      ..sort(
        (a, b) => ((a['quantitySold'] as num?)?.toDouble() ?? 0.0).compareTo(
          (b['quantitySold'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    final totalStockValue = list.fold<double>(
      0.0,
      (sum, product) => sum + ((product['stockValue'] as num?)?.toDouble() ?? 0.0),
    );
    final totalProfit = list.fold<double>(
      0.0,
      (sum, product) => sum + ((product['profit'] as num?)?.toDouble() ?? 0.0),
    );
    return _ProductSection(
      currency: currency,
      products: list,
      topProducts: topProducts,
      bottomProducts: bottom,
      totalStockValue: totalStockValue,
      totalProfit: totalProfit,
    );
  }

  void _sortProducts(
    String field, {
    List<Map<String, dynamic>>? products,
    bool updateState = true,
  }) {
    final target = products ?? List<Map<String, dynamic>>.from(_filteredProducts);
    int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (field) {
        case 'revenue':
          return ((b['revenue'] as num?)?.toDouble() ?? 0.0).compareTo(
            (a['revenue'] as num?)?.toDouble() ?? 0.0,
          );
        case 'profit':
          return ((b['profit'] as num?)?.toDouble() ?? 0.0).compareTo(
            (a['profit'] as num?)?.toDouble() ?? 0.0,
          );
        case 'stock':
          return ((b['stock'] as num?)?.toDouble() ?? 0.0).compareTo(
            (a['stock'] as num?)?.toDouble() ?? 0.0,
          );
        case 'name':
          return (a['name']?.toString() ?? '').compareTo(
            b['name']?.toString() ?? '',
          );
        case 'quantity':
        default:
          return ((b['quantitySold'] as num?)?.toDouble() ?? 0.0).compareTo(
            (a['quantitySold'] as num?)?.toDouble() ?? 0.0,
          );
      }
    }

    target.sort(compare);

    if (updateState && mounted) {
      setState(() {
        _sortBy = field;
        _filteredProducts = target;
        _topProducts = List<Map<String, dynamic>>.from(target.take(5));
        final bottom = List<Map<String, dynamic>>.from(
          target.reversed.take(5).toList(),
        )..sort(
            (a, b) => ((a['quantitySold'] as num?)?.toDouble() ?? 0.0)
                .compareTo(
                  (b['quantitySold'] as num?)?.toDouble() ?? 0.0,
                ),
          );
        _bottomProducts = bottom;
        _totalStockValue = target.fold<double>(
          0.0,
          (sum, product) =>
              sum + ((product['stockValue'] as num?)?.toDouble() ?? 0.0),
        );
        _totalProfit = target.fold<double>(
          0.0,
          (sum, product) =>
              sum + ((product['profit'] as num?)?.toDouble() ?? 0.0),
        );
      });
    }
  }

  Future<void> _exportPDF() async {
    try {
      final pdf = await PdfGenerator.generateProductsReport(
        _filteredProducts,
        _topProducts,
      );
      await Printing.sharePdf(bytes: pdf, filename: 'products_report.pdf');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'PDF export failed: $e');
    }
  }

  Future<void> _exportExcel() async {
    try {
      final excel = ExcelGenerator.generateProductsReport(
        _filteredProducts,
        _topProducts,
      );
      final now = DateTime.now();
      final fileName = 'products_report_${now.millisecondsSinceEpoch}.xlsx';
      await Share.shareXFiles([
        XFile.fromData(
          excel,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: fileName,
        ),
      ], text: 'Products Report');
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, 'Excel export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ValueListenableBuilder<DateTimeRange?>(
                valueListenable: AppDateFilter.instance.rangeNotifier,
                builder: (context, range, _) {
                  return Text(
                    range == null
                        ? 'Global filter: All dates'
                        : 'Global filter: ${range.start.day}/${range.start.month}/${range.start.year} - ${range.end.day}/${range.end.month}/${range.end.year}',
                    style: const TextStyle(color: AppColors.white),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildFilterCard(),
              const SizedBox(height: 16),
              _buildKpiCard(),
              const SizedBox(height: 16),
              _buildPerformanceCard(),
              const SizedBox(height: 16),
              _buildProductTable(),
              const SizedBox(height: 16),
              _buildExportCard(),
            ],
          );
  }

  Widget _buildFilterCard() {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth < 600
              ? constraints.maxWidth
              : 220.0;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Categories'),
                      ),
                      ..._categories.map(
                        (category) => DropdownMenuItem<String>(
                          value: category['name']?.toString() ?? '',
                          child: Text(category['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value ?? 'all';
                        _loadProductPerformance();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBranchId,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Branches'),
                      ),
                      ..._branches.map(
                        (branch) => DropdownMenuItem<String>(
                          value: branch['id']?.toString() ?? '',
                          child: Text(
                            branch['name']?.toString() ??
                                branch['id']?.toString() ??
                                'Branch',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBranchId = value ?? 'all';
                        _loadProductPerformance();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Currencies'),
                      ),
                      ..._availableCurrencies().map(
                        (currency) => DropdownMenuItem<String>(
                          value: currency,
                          child: Text(currency),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCurrency = value ?? 'all';
                        _loadProductPerformance();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _sortBy,
                    decoration: const InputDecoration(
                      labelText: 'Sort By',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'quantity', child: Text('Sold Qty')),
                      DropdownMenuItem(value: 'revenue', child: Text('Revenue')),
                      DropdownMenuItem(value: 'profit', child: Text('Profit')),
                      DropdownMenuItem(value: 'stock', child: Text('Stock')),
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _sortProducts(value);
                    },
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _showOnlyLowStock,
                      onChanged: (value) {
                        setState(() {
                          _showOnlyLowStock = value;
                          _loadProductPerformance();
                        });
                      },
                    ),
                    const Text('Low Stock Only'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiCard() {
    if (_selectedCurrency == 'all') {
      return Column(
        children: _currencySections
            .map((section) => _buildProductSectionView(section))
            .toList(),
      );
    }
    final lowStockCount = _filteredProducts.where((product) {
      final stock = (product['stock'] as num?)?.toDouble() ?? 0.0;
      final minimumLevel = (product['minimumLevel'] as num?)?.toDouble() ?? 5.0;
      return stock < minimumLevel;
    }).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 16,
          alignment: WrapAlignment.spaceAround,
          children: [
            _buildStatItem(
              'Total Products',
              _filteredProducts.length.toString(),
              Icons.category,
            ),
            _buildStatItem(
              'Low Stock',
              lowStockCount.toString(),
              Icons.warning,
            ),
            _buildStatItem(
              'Stock Value',
              'ETB ${_totalStockValue.toStringAsFixed(0)}',
              Icons.attach_money,
            ),
            _buildStatItem(
              'Total Profit',
              'ETB ${_totalProfit.toStringAsFixed(0)}',
              Icons.trending_up,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSectionView(_ProductSection section) {
    final lowStockCount = section.products.where((product) {
      final stock = (product['stock'] as num?)?.toDouble() ?? 0.0;
      final minimumLevel = (product['minimumLevel'] as num?)?.toDouble() ?? 5.0;
      return stock < minimumLevel;
    }).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.currency,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 24,
                runSpacing: 16,
                alignment: WrapAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Products',
                    section.products.length.toString(),
                    Icons.category,
                  ),
                  _buildStatItem(
                    'Low Stock',
                    lowStockCount.toString(),
                    Icons.warning,
                  ),
                  _buildStatItem(
                    'Profit',
                    '${section.currency} ${section.totalProfit.toStringAsFixed(0)}',
                    Icons.trending_up,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildPerformanceCardForSection(section),
          const SizedBox(height: 12),
          _buildProductTableForSection(section),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard() {
    if (_selectedCurrency == 'all') {
      return const SizedBox.shrink();
    }
    Widget panel(String title, List<Map<String, dynamic>> items) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Text('No sales data for the selected filters.')
              else
                ...items.map(_buildPerformanceRow),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;
        if (isNarrow) {
          return Column(
            children: [
              panel('Top Performers', _topProducts),
              const SizedBox(height: 12),
              panel('Bottom Performers', _bottomProducts),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: panel('Top Performers', _topProducts)),
            const SizedBox(width: 12),
            Expanded(child: panel('Bottom Performers', _bottomProducts)),
          ],
        );
      },
    );
  }

  Widget _buildPerformanceCardForSection(_ProductSection section) {
    Widget panel(String title, List<Map<String, dynamic>> items) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Text('No sales data for the selected filters.')
              else
                ...items.map(_buildPerformanceRow),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;
        if (isNarrow) {
          return Column(
            children: [
              panel('Top Performers', section.topProducts),
              const SizedBox(height: 12),
              panel('Bottom Performers', section.bottomProducts),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: panel('Top Performers', section.topProducts)),
            const SizedBox(width: 12),
            Expanded(child: panel('Bottom Performers', section.bottomProducts)),
          ],
        );
      },
    );
  }

  Widget _buildPerformanceRow(Map<String, dynamic> product) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              product['name']?.toString() ?? 'Product',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Text('${(product['quantitySold'] as num?)?.toStringAsFixed(0) ?? '0'} sold'),
        ],
      ),
    );
  }

  Widget _buildProductTable() {
    if (_selectedCurrency == 'all') {
      return const SizedBox.shrink();
    }
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Product Performance',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_filteredProducts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('No products match the selected filters.'),
                    ),
                  )
                else if (isNarrow)
                  ..._filteredProducts.map(_buildProductMobileCard)
                else ...[
                  _buildTableHeader(),
                  const Divider(height: 16),
                  ..._filteredProducts.map(_buildProductRow),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductTableForSection(_ProductSection section) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Product Performance (${section.currency})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (section.products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('No products match the selected filters.'),
                    ),
                  )
                else if (isNarrow)
                  ...section.products.map(
                    (product) => _buildProductMobileCard(
                      product,
                      currency: section.currency,
                    ),
                  )
                else ...[
                  _buildTableHeader(),
                  const Divider(height: 16),
                  ...section.products.map(
                    (product) => _buildProductRow(
                      product,
                      currency: section.currency,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductMobileCard(Map<String, dynamic> product, {String? currency}) {
    final profit = (product['profit'] as num?)?.toDouble() ?? 0.0;
    final stock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final minLevel = (product['minimumLevel'] as num?)?.toDouble() ?? 0.0;

    Widget line(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.mediumGrey)),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: valueColor),
              ),
            ),
          ],
        ),
      );
    }

    final code = currency ?? product['currency']?.toString() ?? 'ETB';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product['name']?.toString() ?? 'Product',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            product['category']?.toString() ?? '-',
            style: const TextStyle(color: AppColors.mediumGrey),
          ),
          const SizedBox(height: 8),
          line(
            'Sold',
            ((product['quantitySold'] as num?)?.toDouble() ?? 0.0)
                .toStringAsFixed(0),
          ),
          line(
            'Revenue',
            '$code ${((product['revenue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
          ),
          line(
            'Profit',
            '$code ${profit.toStringAsFixed(0)}',
            valueColor: profit >= 0 ? AppColors.success : AppColors.error,
          ),
          line('Stock', '${stock.toStringAsFixed(0)} / ${minLevel.toStringAsFixed(0)}'),
          line(
            'Stock Value',
            'ETB ${((product['stockValue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    Widget header(String label, {int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }

    return Row(
      children: [
        header('Product', flex: 2),
        header('Category'),
        header('Sold'),
        header('Revenue'),
        header('Profit'),
        header('Stock'),
        header('Stock Value'),
      ],
    );
  }

  Widget _buildProductRow(Map<String, dynamic> product, {String? currency}) {
    final profit = (product['profit'] as num?)?.toDouble() ?? 0.0;
    final stock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final minLevel = (product['minimumLevel'] as num?)?.toDouble() ?? 0.0;

    final code = currency ?? product['currency']?.toString() ?? 'ETB';
    Widget cell(String text, {int flex = 1, Color? color}) {
      return Expanded(
        flex: flex,
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          cell(product['name']?.toString() ?? 'Product', flex: 2),
          cell(product['category']?.toString() ?? '-'),
          cell(((product['quantitySold'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)),
          cell('$code ${((product['revenue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}'),
          cell(
            '$code ${profit.toStringAsFixed(0)}',
            color: profit >= 0 ? AppColors.success : AppColors.error,
          ),
          cell('${stock.toStringAsFixed(0)} / ${minLevel.toStringAsFixed(0)}'),
          cell(
            'ETB ${((product['stockValue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
          ),
        ],
      ),
    );
  }

  Widget _buildExportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primaryRed),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildExportButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ProductSection {
  const _ProductSection({
    required this.currency,
    required this.products,
    required this.topProducts,
    required this.bottomProducts,
    required this.totalStockValue,
    required this.totalProfit,
  });

  final String currency;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> bottomProducts;
  final double totalStockValue;
  final double totalProfit;
}
