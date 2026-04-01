import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../screens/customers_screen.dart';

class TopCustomers extends StatelessWidget {
  const TopCustomers({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TOP CUSTOMERS',
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
                    builder: (context) => const CustomersScreen(),
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
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('orders').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            // Aggregate orders by customer
            Map<String, Map<String, dynamic>> customerMap = {};
            for (var doc in snapshot.data!.docs) {
              var data = doc.data();
              String customerId = data['customerId'] ?? '';
              String customerName = data['customerName'] ?? 'Unknown';
              double amount = (data['totalAmount'] ?? 0).toDouble();
              if (customerId.isEmpty) continue;
              if (!customerMap.containsKey(customerId)) {
                customerMap[customerId] = {
                  'name': customerName,
                  'orders': 0,
                  'total': 0.0,
                };
              }
              customerMap[customerId]!['orders'] =
                  (customerMap[customerId]!['orders'] as int) + 1;
              customerMap[customerId]!['total'] =
                  (customerMap[customerId]!['total'] as double) + amount;
            }
            // Convert to list and sort by order count
            var customerList = customerMap.entries
                .map(
                  (e) => {
                    'id': e.key,
                    'name': e.value['name'],
                    'orders': e.value['orders'],
                    'total': e.value['total'],
                  },
                )
                .toList();
            customerList.sort(
              (a, b) => (b['orders'] as int).compareTo(a['orders'] as int),
            );
            var topCustomers = customerList.take(3).toList();

            if (topCustomers.isEmpty) {
              return const Center(
                child: Text(
                  'No customer data yet',
                  style: TextStyle(color: AppColors.white),
                ),
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: topCustomers.map((c) {
                return Chip(
                  label: Text('${c['name']} • ${c['orders']} orders'),
                  backgroundColor: AppColors.primaryRed.withOpacity(0.2),
                  labelStyle: const TextStyle(color: AppColors.white),
                  avatar: CircleAvatar(
                    backgroundColor: AppColors.primaryRed,
                    radius: 14,
                    child: Text(
                      (c['name'][0]).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
