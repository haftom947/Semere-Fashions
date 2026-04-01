import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../utils/currency_helper.dart';
import '../widgets/drawer_menu.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/app_date_filter.dart';
import 'create_order_screen.dart';
import 'orders_list_screen.dart';

class SalesHome extends StatefulWidget {
  const SalesHome({super.key});

  @override
  _SalesHomeState createState() => _SalesHomeState();
}

class _SalesHomeState extends State<SalesHome> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _dataChangedSubscription;
  String _salesName = 'Sales Person';
  bool _isLoading = true;
  int _todayOrders = 0;
  double _todaySales = 0.0;
  bool _initialSyncTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadSalesData();
    _loadTodayStats();
    AppDateFilter.instance.rangeNotifier.addListener(_onGlobalRangeChanged);
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      _loadTodayStats();
    });
  }

  @override
  void dispose() {
    AppDateFilter.instance.rangeNotifier.removeListener(_onGlobalRangeChanged);
    _dataChangedSubscription?.cancel();
    super.dispose();
  }

  void _onGlobalRangeChanged() {
    if (!mounted) return;
    _loadTodayStats();
  }

  Future<void> _triggerInitialSync() async {
    if (_initialSyncTriggered) return;
    _initialSyncTriggered = true;
    await _syncService.syncAll();
  }

  Future<void> _loadSalesData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            _salesName = userDoc.get('name') ?? 'Sales Person';
            _isLoading = false;
          });
          await _triggerInitialSync();
        } else {
          setState(() => _isLoading = false);
          await _triggerInitialSync();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading sales data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTodayStats() async {
    try {
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
      var orders = await _dbHelper.query('orders');
      int ordersToday = 0;
      double salesToday = 0.0;
      for (var order in orders) {
        int createdAt = order['createdAt'] ?? 0;
        if (createdAt >= startMillis && createdAt <= endMillis) {
          ordersToday++;
          salesToday += (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      setState(() {
        _todayOrders = ordersToday;
        _todaySales = salesToday;
      });
    } catch (e) {
      print('Error loading today stats: $e');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  void _navigateToCreateOrder() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateOrderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DrawerMenu(role: 'sales'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 150.0,
                    floating: false,
                    pinned: true,
                    backgroundColor: Colors.transparent,
                    leading: Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu, color: AppColors.white),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.white),
                        onPressed: () {
                          _loadSalesData();
                          _loadTodayStats();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: AppColors.white),
                        onPressed: _logout,
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(color: Colors.transparent),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Welcome Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome, $_salesName!',
                                style: const TextStyle(
                                  color: AppColors.darkGrey,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Ready to create new orders?',
                                style: TextStyle(
                                  color: AppColors.mediumGrey,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Quick Actions
                        const Text(
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildActionButton(
                              Icons.add_shopping_cart,
                              'New Order',
                              AppColors.primaryRed,
                              _navigateToCreateOrder,
                            ),
                            _buildActionButton(
                              Icons.history,
                              'Order History',
                              AppColors.info,
                              () {
                                Navigator.pushNamed(context, '/orders');
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Today's Stats
                        const Text(
                          "Selected Summary",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          childAspectRatio: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          children: [
                            _buildStatCard(
                              'Orders',
                              _todayOrders.toString(),
                              Icons.shopping_bag,
                              AppColors.primaryRed,
                            ),
                            _buildStatCard(
                              'Sales',
                              CurrencyHelper.formatAmount(_todaySales, null),
                              Icons.attach_money,
                              AppColors.success,
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateOrder,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: AppColors.white),
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.white),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 20),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.darkGrey,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: AppColors.mediumGrey),
            ),
          ],
        ),
      ),
    );
  }
}
