import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/financial_calculator.dart';
import '../utils/colors.dart';

class ProfitDetailsScreen extends StatefulWidget {
  final DateTimeRange? dateRange;
  final String? branchId;

  const ProfitDetailsScreen({Key? key, this.dateRange, this.branchId})
      : super(key: key);

  @override
  State<ProfitDetailsScreen> createState() => _ProfitDetailsScreenState();
}

class _ProfitDetailsScreenState extends State<ProfitDetailsScreen> {
  List<CurrencySummary> _summaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final summaries = await FinancialCalculator()
        .calculatePerCurrency(range: widget.dateRange, branchId: widget.branchId);
    if (!mounted) return;
    setState(() {
      _summaries = summaries;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Summary'),
        backgroundColor: AppColors.primaryRed, // AppBar can remain red
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summaries.isEmpty
              ? const Center(
                  child: Text('No data', style: TextStyle(color: AppColors.white70)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final summary in _summaries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0, top: 12.0),
                        child: Text(
                          '${summary.currency}',
                          style: const TextStyle( // Currency title can be white on dark background
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ), 
                        ),
                      ),
                      _buildSalesProfitCard(summary),
                      const SizedBox(height: 12),
                      _buildOperatingExpensesCard(summary),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadOrdersForCurrency(String currency) async {
    final dbHelper = DatabaseHelper();
    final startMillis = widget.dateRange?.start.millisecondsSinceEpoch ?? 0;
    // Add 1 day to end date to include the whole day
    final endMillis = widget.dateRange?.end.add(const Duration(days: 1)).millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;

    final orders = await dbHelper.getOrdersInDateRange(
      startMillis,
      endMillis,
      branchId: widget.branchId,
    );

    final filteredOrders = orders.where((order) {
      final orderCurrency = order['currency']?.toString() ?? 'ETB';
      final status = order['status']?.toString() ?? '';
      return orderCurrency == currency && status != 'cancelled';
    }).toList()
      ..sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));

    for (var order in filteredOrders) {
      final orderId = order['id']?.toString();
      if (orderId != null) {
        order['totalCommissions'] = await dbHelper.getCommissionsTotalForOrder(orderId);
      } else {
        order['totalCommissions'] = 0.0;
      }
    }

    return filteredOrders;
  }

  Widget _buildSalesProfitCard(CurrencySummary summary) {
    return Card(
      // Set card background to a neutral dark grey for better contrast with white text
      color: const Color(0xFF2C2C2C),
      child: ExpansionTile(
        iconColor: AppColors.white70, // Ensure icon is visible
        collapsedIconColor: AppColors.white70, // Ensure icon is visible
        textColor: AppColors.white, // Ensure title text is visible
        collapsedTextColor: AppColors.white, // Ensure title text is visible
        title: const Text(
          '📈 Sales Profit',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
        children: [
          Column( // Wrap children in a Column
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    _buildStatRow('Revenue', summary.revenue, valueColor: AppColors.success),
                    _buildStatRow('COGS', summary.cogs, valueColor: AppColors.warning),
                    _buildStatRow('Gross Profit', summary.grossProfit, valueColor: AppColors.info),
                    _buildStatRow('Commissions', summary.commissionExpenses, valueColor: AppColors.error, isDeduction: true),
                    _buildStatRow('Losses', summary.lossesExpense, valueColor: AppColors.error, isDeduction: true),
                    const Divider(color: AppColors.white24),
                    _buildStatRow('Net Profit', summary.netProfit, valueColor: summary.netProfit >= 0 ? AppColors.success : AppColors.error, bold: true),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Orders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              ),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadOrdersForCurrency(summary.currency),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Error loading orders: ${snapshot.error}', style: const TextStyle(color: AppColors.error)),
                    );
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No orders found for this currency.', style: TextStyle(color: AppColors.white70)),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    primary: false,
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      final order = snapshot.data![index];
                      final orderId = order['id']?.toString() ?? '';
                      final customerName = order['customerName']?.toString() ?? 'Unknown';
                      final totalAmount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
                      final cogs = (order['cogs'] as num?)?.toDouble() ?? 0.0;
                      final grossProfit = totalAmount - cogs;
                      final paidAmount = (order['paid_amount'] as num?)?.toDouble() ?? 0.0;
                      final status = order['status']?.toString() ?? 'N/A';
                      final totalCommissions = (order['totalCommissions'] as num?)?.toDouble() ?? 0.0;

                      return _buildOrderListTile(
                        orderId: orderId,
                        customerName: customerName,
                        totalAmount: totalAmount,
                        cogs: cogs,
                        grossProfit: grossProfit,
                        paidAmount: paidAmount,
                        status: status,
                        currency: summary.currency,
                        totalCommissions: totalCommissions,
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperatingExpensesCard(CurrencySummary summary) {
    final overheadItems = summary.expenseItems
        .where((item) =>
            item.category == 'Fuel' ||
            item.category == 'Maintenance' ||
            item.category == 'Rent Expense' ||
            item.category == 'Material' ||
            item.category == 'Material (General)')
        .toList();

    return Card(
      // Set card background to a neutral dark grey for better contrast with white text
      color: const Color(0xFF2C2C2C),
      child: ExpansionTile(
        iconColor: AppColors.white70, // Ensure icon is visible
        collapsedIconColor: AppColors.white70, // Ensure icon is visible
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '⚙️ Operating Expenses',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            ),
            Text(
              'Not deducted from Sales Profit',
              style: TextStyle(color: AppColors.white70, fontSize: 12), // Text color remains white70
            ),
          ],
        ),
        children: [
          Padding( // This padding is for the aggregated overhead items
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                if (overheadItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No expenses to show.', style: TextStyle(color: AppColors.white70)),
                  )
                else ...[
                  ...overheadItems.map((item) => _buildStatRow(
                    item.title,
                    item.amount,
                    valueColor: AppColors.warning,
                    isDeduction: true,
                    subtitle: item.subtitle, // Display subtitle for more detail
                  )),
                  // Display other expense items from the summary
                  ...summary.expenseItems.where((item) => !overheadItems.contains(item)).map((item) => _buildStatRow(
                    item.title, item.amount, valueColor: AppColors.warning, isDeduction: true, subtitle: item.subtitle,
                  )),
                ],
                const Divider(color: AppColors.white24),
                _buildStatRow('Total Overhead', summary.overheadExpenses, valueColor: AppColors.warning, bold: true),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    double amount, {
    Color? valueColor,
    bool bold = false,
    bool isDeduction = false,
    String? subtitle,
  }) {
    final sign = isDeduction ? '-' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.white70, // Text color remains white70
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: valueColor ?? AppColors.white, // Text color remains white
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.white24, // Subtitle color remains white24
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderListTile({
    required String orderId,
    required String customerName,
    required double totalAmount,
    required double cogs,
    required double grossProfit,
    required double paidAmount,
    required String status,
    required String currency,
    required double totalCommissions,
  }) {
    // Net profit = (totalAmount - cogs) - totalCommissions
    final netProfit = grossProfit - totalCommissions;
    final netProfitColor = netProfit >= 0 ? AppColors.success : AppColors.error;

    return ListTile(
      title: Text(
        '$customerName (#${orderId.substring(0, 6)})',
        style: const TextStyle(color: AppColors.white),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total: $currency ${totalAmount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.white70)),
          Text('COGS: $currency ${cogs.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.white70)),
          Text('Gross Profit: $currency ${grossProfit.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.white70)),
          if (totalCommissions > 0)
            Text('Commissions: $currency ${totalCommissions.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.white70)),
          Text('Paid: $currency ${paidAmount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.white70)),
          Text('Status: $status', style: const TextStyle(color: AppColors.white70)),
        ],
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'Net Profit',
            style: TextStyle(
              color: AppColors.white70,
              fontSize: 11,
            ),
          ),
          Text(
            '$currency ${netProfit.toStringAsFixed(2)}',
            style: TextStyle(
              color: netProfitColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      onTap: () {
        // Optionally navigate to order details
        // Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailsScreen(orderId: orderId)));
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      tileColor: Colors.transparent,
    );
  }
}
