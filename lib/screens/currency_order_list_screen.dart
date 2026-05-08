import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';
import 'order_details_screen.dart';

class CurrencyOrderListScreen extends StatefulWidget {
  final String currency;
  const CurrencyOrderListScreen({Key? key, required this.currency}) : super(key: key);

  @override
  State<CurrencyOrderListScreen> createState() => _CurrencyOrderListScreenState();
}

class _CurrencyOrderListScreenState extends State<CurrencyOrderListScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    final db = await DatabaseHelper().database;
    final orders = await db.rawQuery(
      "SELECT * FROM orders WHERE currency = ? AND status != 'cancelled' ORDER BY createdAt DESC",
      [widget.currency],
    );
    if (!mounted) return;
    setState(() {
      _orders = orders.map((r) => Map<String, dynamic>.from(r)).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.currency} Orders'),
        backgroundColor: AppColors.primaryRed,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(child: Text('No orders', style: TextStyle(color: AppColors.white70)))
              : ListView.builder(
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
                    final cogs = (order['cogs'] as num?)?.toDouble() ?? 0.0;
                    final grossProfit = total - cogs;
                    final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0.0;
                    final status = (order['status'] ?? '').toString();
                    final id = (order['id'] ?? '').toString();

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: AppColors.cardBackground,
                      child: ListTile(
                        title: Text(
                          '${order['customerName'] ?? 'Unknown'} (#${id.length >= 8 ? id.substring(0, 8) : id})',
                          style: const TextStyle(color: AppColors.darkGrey),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total: ${total.toStringAsFixed(2)} ${widget.currency}', style: const TextStyle(color: AppColors.mediumGrey)),
                            Text('COGS: ${cogs.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.warning)),
                            Text('Gross: ${grossProfit.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.success)),
                            Text('Paid: ${paid.toStringAsFixed(2)} | ${status}', style: const TextStyle(color: AppColors.mediumGrey)),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, color: AppColors.mediumGrey),
                        onTap: () {
                          if (id.isEmpty) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailsScreen(orderId: id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
