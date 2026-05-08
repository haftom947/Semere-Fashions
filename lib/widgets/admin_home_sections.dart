import 'package:flutter/material.dart';

import '../utils/colors.dart';
import 'stat_card.dart';

class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({
    super.key,
    required this.onAddEmployee,
    required this.onCreateOrder,
    required this.onAddStock,
    required this.onReports,
  });

  final VoidCallback onAddEmployee;
  final VoidCallback onCreateOrder;
  final VoidCallback onAddStock;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ActionButton(
              icon: Icons.person_add,
              label: 'Add Employee',
              color: AppColors.primaryRed,
              onTap: onAddEmployee,
            ),
            _ActionButton(
              icon: Icons.shopping_bag,
              label: 'New Order',
              color: AppColors.success,
              onTap: onCreateOrder,
            ),
            _ActionButton(
              icon: Icons.inventory,
              label: 'Add Stock',
              color: AppColors.info,
              onTap: onAddStock,
            ),
            _ActionButton(
              icon: Icons.receipt,
              label: 'Reports',
              color: AppColors.accent,
              onTap: onReports,
            ),
          ],
        ),
      ],
    );
  }
}

class OrderStatsGridSection extends StatelessWidget {
  const OrderStatsGridSection({
    super.key,
    required this.totalOrders,
    required this.pendingOrders,
    required this.completedOrders,
    required this.withDriverCount,
    required this.processingCount,
    required this.cancelledBefore,
    required this.cancelledAfter,
    required this.onTotalTap,
    required this.onPendingTap,
    required this.onCompletedTap,
    required this.onWithDriverTap,
    required this.onProcessingTap,
  });

  final int totalOrders;
  final int pendingOrders;
  final int completedOrders;
  final int withDriverCount;
  final int processingCount;
  final int cancelledBefore;
  final int cancelledAfter;
  final VoidCallback onTotalTap;
  final VoidCallback onPendingTap;
  final VoidCallback onCompletedTap;
  final VoidCallback onWithDriverTap;
  final VoidCallback onProcessingTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            GestureDetector(
              onTap: onTotalTap,
              child: StatCard(
                title: 'Total Orders',
                value: totalOrders.toString(),
                icon: Icons.shopping_bag,
                color: AppColors.primaryRed,
              ),
            ),
            GestureDetector(
              onTap: onPendingTap,
              child: StatCard(
                title: 'Pending',
                value: pendingOrders.toString(),
                icon: Icons.pending_actions,
                color: AppColors.warning,
              ),
            ),
            GestureDetector(
              onTap: onCompletedTap,
              child: StatCard(
                title: 'Completed',
                value: completedOrders.toString(),
                icon: Icons.check_circle,
                color: AppColors.info,
              ),
            ),
            GestureDetector(
              onTap: onWithDriverTap,
              child: StatCard(
                title: 'With Driver',
                value: withDriverCount.toString(),
                icon: Icons.delivery_dining,
                color: AppColors.primaryRed,
              ),
            ),
            GestureDetector(
              onTap: onProcessingTap,
              child: StatCard(
                title: 'Processing',
                value: processingCount.toString(),
                icon: Icons.pending,
                color: AppColors.info,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(
                          Icons.cancel,
                          color: AppColors.error,
                          size: 20,
                        ),
                        Text(
                          '${cancelledBefore + cancelledAfter}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGrey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cancelled',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mediumGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$cancelledBefore before / $cancelledAfter after',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RentalSummarySection extends StatelessWidget {
  const RentalSummarySection({
    super.key,
    required this.receivedThisMonth,
    required this.overdue,
    required this.occupancyRate,
    required this.onManageTap,
  });

  final double receivedThisMonth;
  final double overdue;
  final double occupancyRate;
  final VoidCallback onManageTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Rental Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: onManageTap,
                  child: const Text('Manage >'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _RentalStat(
                  label: 'Received',
                  value: 'ETB ${receivedThisMonth.toStringAsFixed(0)}',
                  icon: Icons.payment,
                  color: AppColors.success,
                ),
                _RentalStat(
                  label: 'Overdue',
                  value: 'ETB ${overdue.toStringAsFixed(0)}',
                  icon: Icons.warning,
                  color: AppColors.error,
                ),
                _RentalStat(
                  label: 'Occupancy',
                  value: '${occupancyRate.toStringAsFixed(1)}%',
                  icon: Icons.percent,
                  color: AppColors.info,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FinancialOverviewSection extends StatelessWidget {
  const FinancialOverviewSection({
    super.key,
    required this.totalRevenue,
    required this.salesTotal,
    required this.toCollectAmount,
    required this.cogs,
    required this.losses,
    required this.netProfit,
    required this.onReportsTap,
    required this.onUnpaidTap,
    required this.onCogsTap,
    required this.onProfitTap,
    required this.onLossesTap,
  });

  final double totalRevenue;
  final double salesTotal;
  final double toCollectAmount;
  final double cogs;
  final double losses;
  final double netProfit;
  final VoidCallback onReportsTap;
  final VoidCallback onUnpaidTap;
  final VoidCallback onCogsTap;
  final VoidCallback onProfitTap;
  final VoidCallback onLossesTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Financial Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            GestureDetector(
              onTap: onReportsTap,
              child: StatCard(
                title: 'Revenue',
                value: 'ETB ${totalRevenue.toStringAsFixed(0)}',
                icon: Icons.attach_money,
                color: AppColors.success,
              ),
            ),
            GestureDetector(
              onTap: onReportsTap,
              child: StatCard(
                title: 'Sales',
                value: 'ETB ${salesTotal.toStringAsFixed(0)}',
                icon: Icons.shopping_cart,
                color: AppColors.primaryRed,
              ),
            ),
            GestureDetector(
              onTap: onUnpaidTap,
              child: StatCard(
                title: 'To Collect',
                value: 'ETB ${toCollectAmount.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet,
                color: AppColors.accent,
              ),
            ),
            GestureDetector(
              onTap: onCogsTap,
              child: StatCard(
                title: 'COGS',
                value: 'ETB ${cogs.toStringAsFixed(0)}',
                icon: Icons.inventory,
                color: AppColors.warning,
              ),
            ),
            if (losses > 0)
              GestureDetector(
                onTap: onLossesTap,
                child: StatCard(
                  title: 'Losses',
                  value: 'ETB ${losses.toStringAsFixed(0)}',
                  icon: Icons.report,
                  color: AppColors.error,
                ),
              ),
            GestureDetector(
              onTap: onProfitTap,
              child: StatCard(
                title: 'Net Profit',
                value: 'ETB ${netProfit.toStringAsFixed(0)}',
                icon: Icons.trending_up,
                color: netProfit >= 0 ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.white),
          ),
        ],
      ),
    );
  }
}

class _RentalStat extends StatelessWidget {
  const _RentalStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
