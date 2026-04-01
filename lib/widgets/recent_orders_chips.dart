import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../utils/colors.dart';
import '../screens/orders_list_screen.dart';

class RecentOrdersChips extends StatefulWidget {
  const RecentOrdersChips({super.key});

  @override
  _RecentOrdersChipsState createState() => _RecentOrdersChipsState();
}

class _RecentOrdersChipsState extends State<RecentOrdersChips> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadRecentOrders();
  }

  Future<void> _loadRecentOrders() async {
    var orders = await _dbHelper.query('orders');
    orders.sort(
      (a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int),
    );
    setState(() {
      _recentOrders = orders.take(3).toList(); // only 3
    });
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'processing':
        return AppColors.info;
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.mediumGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT ORDERS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OrdersListScreen(),
                  ),
                );
              },
              child: const Text(
                'See All >',
                style: TextStyle(color: AppColors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _recentOrders.isEmpty
            ? const Center(
                child: Text(
                  'No recent orders',
                  style: TextStyle(color: AppColors.white),
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentOrders.map((order) {
                  return ActionChip(
                    label: Text(
                      '${order['customerName'] ?? 'Unknown'} • ETB ${(order['totalAmount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: _getStatusColor(
                      order['status'],
                    ).withOpacity(0.2),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              OrdersListScreen(initialStatus: order['status']),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
      ],
    );
  }
}
