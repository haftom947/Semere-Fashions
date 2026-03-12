import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../widgets/stat_card.dart';
import '../widgets/category_card.dart';
import '../widgets/recent_order_card.dart';
import '../widgets/drawer_menu.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/low_stock_service.dart';
import 'orders_list_screen.dart';
import 'inventory_screen.dart';
import 'employee_list_screen.dart';
import 'customers_screen.dart';
import 'reports_screen.dart';

class ManagerHome extends StatefulWidget {
  const ManagerHome({Key? key}) : super(key: key);

  @override
  _ManagerHomeState createState() => _ManagerHomeState();
}

class _ManagerHomeState extends State<ManagerHome> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Timer? _lowStockTimer;

  String _managerName = 'Manager';
  String _branchName = 'Branch';
  bool _isLoading = true;

  // Stats data
  int _totalOrders = 0;
  int _pendingOrders = 0;
  int _completedOrders = 0;
  double _totalRevenue = 0.0;
  List<Map<String, dynamic>> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadManagerData();
    _loadStats();
    _syncService.dataChangedStream.listen((_) {
      _loadStats();
    });
    _startLowStockPeriodicCheck();
  }

  void _startLowStockPeriodicCheck() {
    _lowStockTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      await LowStockService().checkAndNotify();
    });
  }

  @override
  void dispose() {
    _lowStockTimer?.cancel();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _getLowStockStream() async* {
    while (true) {
      var products = await _dbHelper.query('products');
      var materials = await _dbHelper.query('materials');
      List<Map<String, dynamic>> lowStock = [];
      lowStock.addAll(products.where((p) => (p['stock'] ?? 0) < (p['minimumLevel'] ?? 5)));
      lowStock.addAll(materials.where((m) => (m['stock'] ?? 0) < (m['minimumLevel'] ?? 5)));
      yield lowStock;
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  Future<void> _loadManagerData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          setState(() {
            _managerName = userDoc.get('name') ?? 'Manager';
            _branchName = userDoc.get('branchId') ?? 'Branch';
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading manager data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    var orders = await _dbHelper.query('orders');
    // Filter by branch
    var branchOrders = orders.where((o) => o['branchId'] == _branchName).toList();

    int total = 0;
    int pending = 0;
    int completed = 0;
    double revenue = 0.0;

    for (var order in branchOrders) {
      total++;
      String status = order['status'] ?? '';
      if (status == 'pending') pending++;
      if (status == 'completed' || status == 'delivered') completed++;
      revenue += (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    }

    branchOrders.sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    var recent = branchOrders.take(5).toList();

    setState(() {
      _totalOrders = total;
      _pendingOrders = pending;
      _completedOrders = completed;
      _totalRevenue = revenue;
      _recentOrders = recent;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  void _navigateToOrders() {
    Navigator.pushNamed(context, '/orders');
  }

  void _navigateToInventory() {
    Navigator.pushNamed(context, '/inventory');
  }

  void _navigateToReports() {
    Navigator.pushNamed(context, '/reports');
  }

  void _navigateToEmployees() {
    Navigator.pushNamed(context, '/employees');
  }

  void _navigateToCustomers() {
    Navigator.pushNamed(context, '/customers');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DrawerMenu(role: 'manager'),
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
                    expandedHeight: 180.0,
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
                          _loadManagerData();
                          _loadStats();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: AppColors.white),
                        onPressed: _logout,
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                  
                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Low Stock Banner
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _getLowStockStream(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const SizedBox();
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.2),
                                border: Border.all(color: AppColors.warning),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '⚠️ Low Stock Alert',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  ...snapshot.data!.map((item) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      '${item['name']}: ${item['stock']} remaining',
                                      style: const TextStyle(color: AppColors.white),
                                    ),
                                  )),
                                ],
                              ),
                            );
                          },
                        ),
                        
                        // Branch Info Card
                        Container(
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
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: AppColors.primaryRed.withOpacity(0.1),
                                  child: const Icon(
                                    Icons.store,
                                    color: AppColors.primaryRed,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _managerName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkGrey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Manager · $_branchName',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.mediumGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        Text(
                          'Good day, $_managerName!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Here\'s your branch performance.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        _buildQuickActions(),
                        const SizedBox(height: 24),
                        _buildBranchStats(),
                        const SizedBox(height: 24),
                        _buildCategoriesSection(),
                        const SizedBox(height: 24),
                        _buildRecentOrdersSection(),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToOrders,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: AppColors.white),
      ),
    );
  }

  Widget _buildQuickActions() {
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
            _buildActionButton(Icons.shopping_bag, 'New Order', AppColors.primaryRed, _navigateToOrders),
            _buildActionButton(Icons.inventory, 'Inventory', AppColors.info, _navigateToInventory),
            _buildActionButton(Icons.people, 'Staff', AppColors.success, _navigateToEmployees),
            _buildActionButton(Icons.receipt, 'Reports', AppColors.accent, _navigateToReports),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
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
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Branch Overview',
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
              onTap: _navigateToOrders,
              child: StatCard(
                title: 'Total Orders',
                value: _totalOrders.toString(),
                icon: Icons.shopping_bag,
                color: AppColors.primaryRed,
              ),
            ),
            StatCard(
              title: 'Revenue',
              value: 'ETB ${_totalRevenue.toStringAsFixed(0)}',
              icon: Icons.attach_money,
              color: AppColors.success,
            ),
            StatCard(
              title: 'Pending',
              value: _pendingOrders.toString(),
              icon: Icons.pending_actions,
              color: AppColors.warning,
            ),
            StatCard(
              title: 'Completed',
              value: _completedOrders.toString(),
              icon: Icons.check_circle,
              color: AppColors.info,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Order Categories',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            TextButton(
              onPressed: _navigateToOrders,
              child: const Text(
                'See All >',
                style: TextStyle(color: AppColors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrdersListScreen(initialStatus: 'pending'),
                    ),
                  );
                },
                child: CategoryCard(
                  title: 'To Deliver',
                  count: '0',
                  color: AppColors.primaryRed,
                  icon: Icons.delivery_dining,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrdersListScreen(initialStatus: 'processing'),
                    ),
                  );
                },
                child: CategoryCard(
                  title: 'Processing',
                  count: '0',
                  color: AppColors.warning,
                  icon: Icons.pending,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrdersListScreen(initialStatus: 'delivered'),
                    ),
                  );
                },
                child: CategoryCard(
                  title: 'Delivered',
                  count: '0',
                  color: AppColors.success,
                  icon: Icons.check_circle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentOrdersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Orders',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            TextButton(
              onPressed: _navigateToOrders,
              child: const Text(
                'View All',
                style: TextStyle(color: AppColors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _recentOrders.isEmpty
            ? Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'No orders yet',
                    style: TextStyle(color: AppColors.mediumGrey),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentOrders.length,
                itemBuilder: (context, index) {
                  var order = _recentOrders[index];
                  return GestureDetector(
                    onTap: _navigateToOrders,
                    child: RecentOrderCard(
                      orderId: order['id'],
                      customer: order['customerName'] ?? 'Unknown',
                      amount: 'ETB ${(order['totalAmount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      status: order['status'] ?? 'pending',
                    ),
                  );
                },
              ),
      ],
    );
  }
}