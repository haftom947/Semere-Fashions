import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../widgets/stat_card.dart';
import '../widgets/category_card.dart';
import '../widgets/drawer_menu.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/low_stock_service.dart';
import '../utils/error_handler.dart';
import 'add_employee_screen.dart';
import 'orders_list_screen.dart';
import 'inventory_screen.dart';
import 'employee_list_screen.dart';
import 'customers_screen.dart';
import 'reports_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({Key? key}) : super(key: key);

  @override
  _AdminHomeState createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  Timer? _lowStockTimer;
  StreamSubscription? _lowStockSubscription;
  bool _hasShownLowStockAlert = false;

  String _adminName = 'Admin';
  String _branchName = 'Main Branch';
  bool _isLoading = true;

  // Stats data
  int _totalOrders = 0;
  int _pendingOrders = 0;
  int _completedOrders = 0;
  double _totalRevenue = 0.0;
  List<Map<String, dynamic>> _recentOrders = [];

  // Rental summary data
  double _rentalReceivedThisMonth = 0.0;
  double _rentalOverdue = 0.0;
  double _rentalOccupancyRate = 0.0;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
    _loadStats();
    _loadRentalSummary();
    _syncService.dataChangedStream.listen((_) {
      _loadStats();
      _loadRentalSummary();
    });
    _startLowStockPeriodicCheck();
    _listenToLowStock();
  }

  void _listenToLowStock() {
    _lowStockSubscription = _getLowStockStream().listen((lowStock) {
      if (lowStock.isNotEmpty && !_hasShownLowStockAlert && mounted) {
        ErrorHandler.showWarning(
          context,
          'Low stock alert: ${lowStock.length} item${lowStock.length > 1 ? 's' : ''} below minimum.',
        );
        _hasShownLowStockAlert = true;
      }
    });
  }

  void _startLowStockPeriodicCheck() {
    _lowStockTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      await LowStockService().checkAndNotify();
    });
  }

  @override
  void dispose() {
    _lowStockTimer?.cancel();
    _lowStockSubscription?.cancel();
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
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  Future<void> _loadAdminData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          setState(() {
            _adminName = userDoc.get('name') ?? 'Admin';
            _branchName = userDoc.get('branchId') ?? 'Main Branch';
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading admin data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    var orders = await _dbHelper.query('orders');
    int total = 0;
    int pending = 0;
    int completed = 0;
    double revenue = 0.0;

    for (var order in orders) {
      total++;
      String status = order['status'] ?? '';
      if (status == 'pending') pending++;
      if (status == 'completed' || status == 'delivered') completed++;
      revenue += (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    }

    orders.sort((a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    var recent = orders.take(5).toList();

    setState(() {
      _totalOrders = total;
      _pendingOrders = pending;
      _completedOrders = completed;
      _totalRevenue = revenue;
      _recentOrders = recent;
    });
  }

  Future<void> _loadRentalSummary() async {
    try {
      var rentDues = await _dbHelper.query('rent_dues');
      var payments = await _dbHelper.query('rent_payments');
      var properties = await _dbHelper.query('properties');

      // Get current month
      final now = DateTime.now();
      final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      // Calculate received this month
      double received = 0;
      for (var p in payments) {
        if (p['month'] == currentMonth) {
          received += (p['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      // Calculate overdue (status 'pending' and dueDate < now)
      double overdue = 0;
      for (var d in rentDues) {
        if (d['status'] == 'pending' && (d['dueDate'] as int) < now.millisecondsSinceEpoch) {
          overdue += (d['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      // Occupancy rate (occupied / total)
      int total = properties.length;
      int occupied = properties.where((p) => p['status'] == 'occupied').length;
      double occupancy = total > 0 ? (occupied / total) * 100 : 0;

      setState(() {
        _rentalReceivedThisMonth = received;
        _rentalOverdue = overdue;
        _rentalOccupancyRate = occupancy;
      });
    } catch (e) {
      print('Error loading rental summary: $e');
    }
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

  void _navigateToAddEmployee() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEmployeeScreen()),
    );
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

  void _navigateToProperties() {
    Navigator.pushNamed(context, '/properties');
  }

  // Helper to get top customers for chips
  Future<List<Map<String, dynamic>>> _getTopCustomers() async {
    var orders = await _dbHelper.query('orders');
    Map<String, Map<String, dynamic>> customerMap = {};
    for (var order in orders) {
      String customerId = order['customerId'] ?? '';
      String customerName = order['customerName'] ?? 'Unknown';
      double amount = (order['totalAmount'] as num?)?.toDouble() ?? 0;
      if (customerId.isEmpty) continue;
      if (!customerMap.containsKey(customerId)) {
        customerMap[customerId] = {
          'id': customerId,
          'name': customerName,
          'orders': 0,
          'total': 0.0,
        };
      }
      customerMap[customerId]!['orders'] = customerMap[customerId]!['orders'] + 1;
      customerMap[customerId]!['total'] = customerMap[customerId]!['total'] + amount;
    }
    var list = customerMap.values.toList();
    list.sort((a, b) => (b['orders'] as int).compareTo(a['orders'] as int));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DrawerMenu(role: 'admin'),
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
                    expandedHeight: 200.0,
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
                          _loadAdminData();
                          _loadStats();
                          _loadRentalSummary();
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
                        Text(
                          'Welcome back, $_adminName!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Here\'s your business overview for today.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        _buildQuickActions(),
                        const SizedBox(height: 24),
                        _buildStatsSection(),
                        const SizedBox(height: 24),
                        _buildCategoriesSection(),
                        const SizedBox(height: 24),

                        // Rental Summary Section (new)
                        _buildRentalSummary(),
                        const SizedBox(height: 24),

                        // Top Customers as chips
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getTopCustomers(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const SizedBox();
                            }
                            var topCustomers = snapshot.data!;
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
                                      onPressed: _navigateToCustomers,
                                      child: const Text('See All >', style: TextStyle(color: AppColors.white)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: topCustomers.take(3).map((customer) {
                                    return Chip(
                                      label: Text('${customer['name']} (${customer['orders']})'),
                                      avatar: CircleAvatar(
                                        backgroundColor: AppColors.primaryRed,
                                        child: Text(
                                          (customer['name'][0]).toUpperCase(),
                                          style: const TextStyle(color: AppColors.white, fontSize: 12),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // Recent Orders as chips
                        Column(
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
                                  child: const Text('View All >', style: TextStyle(color: AppColors.white)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _recentOrders.isEmpty
                                ? const Text('No recent orders', style: TextStyle(color: AppColors.white))
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _recentOrders.take(3).map((order) {
                                      return Chip(
                                        label: Text('#${order['id'].substring(0, 6)} · ETB ${(order['totalAmount'] as num?)?.toStringAsFixed(0)}'),
                                        avatar: const CircleAvatar(
                                          backgroundColor: AppColors.info,
                                          child: Icon(Icons.shopping_bag, color: AppColors.white, size: 14),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _buildAccountSummary(),
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
            _buildActionButton(Icons.person_add, 'Add Employee', AppColors.primaryRed, _navigateToAddEmployee),
            _buildActionButton(Icons.shopping_bag, 'New Order', AppColors.success, _navigateToOrders),
            _buildActionButton(Icons.inventory, 'Add Stock', AppColors.info, _navigateToInventory),
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

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
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
            GestureDetector(
              onTap: _navigateToReports,
              child: StatCard(
                title: 'Revenue',
                value: 'ETB ${_totalRevenue.toStringAsFixed(0)}',
                icon: Icons.attach_money,
                color: AppColors.success,
              ),
            ),
            GestureDetector(
              onTap: _navigateToOrders,
              child: StatCard(
                title: 'Pending',
                value: _pendingOrders.toString(),
                icon: Icons.pending_actions,
                color: AppColors.warning,
              ),
            ),
            GestureDetector(
              onTap: _navigateToOrders,
              child: StatCard(
                title: 'Completed',
                value: _completedOrders.toString(),
                icon: Icons.check_circle,
                color: AppColors.info,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRentalSummary() {
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: _navigateToProperties,
                  child: const Text('Manage >'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRentalStat(
                  'Received',
                  'ETB ${_rentalReceivedThisMonth.toStringAsFixed(0)}',
                  Icons.payment,
                  AppColors.success,
                ),
                _buildRentalStat(
                  'Overdue',
                  'ETB ${_rentalOverdue.toStringAsFixed(0)}',
                  Icons.warning,
                  AppColors.error,
                ),
                _buildRentalStat(
                  'Occupancy',
                  '${_rentalOccupancyRate.toStringAsFixed(1)}%',
                  Icons.percent,
                  AppColors.info,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentalStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
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
                      builder: (context) => OrdersListScreen(initialStatus: 'pending'),
                    ),
                  );
                },
                child: CategoryCard(
                  title: 'To Pick Up',
                  count: '0',
                  color: AppColors.warning,
                  icon: Icons.inventory,
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
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrdersListScreen(initialStatus: 'cancelled'),
                    ),
                  );
                },
                child: CategoryCard(
                  title: 'Cancelled',
                  count: '0',
                  color: AppColors.error,
                  icon: Icons.cancel,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrdersListScreen(initialStatus: 'returned'),
                    ),
                  );
                },
                child: CategoryCard(
                  title: 'Returned',
                  count: '0',
                  color: AppColors.primaryRed,
                  icon: Icons.assignment_return,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Account Summary',
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
          childAspectRatio: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            GestureDetector(
              onTap: _navigateToOrders,
              child: StatCard(
                title: 'Total Orders',
                value: _totalOrders.toString(),
                icon: Icons.shopping_cart,
                color: AppColors.primaryRed,
              ),
            ),
            GestureDetector(
              onTap: _navigateToReports,
              child: StatCard(
                title: 'Total Paid',
                value: 'ETB ${_totalRevenue.toStringAsFixed(0)}',
                icon: Icons.paid,
                color: AppColors.success,
              ),
            ),
            GestureDetector(
              onTap: _navigateToOrders,
              child: StatCard(
                title: 'Pending',
                value: 'ETB ${(_totalRevenue * 0.3).toStringAsFixed(0)}',
                icon: Icons.pending,
                color: AppColors.warning,
              ),
            ),
            GestureDetector(
              onTap: _navigateToReports,
              child: StatCard(
                title: 'To Collect',
                value: 'ETB ${(_totalRevenue * 0.7).toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet,
                color: AppColors.info,
              ),
            ),
            StatCard(
              title: 'Returned',
              value: '0',
              icon: Icons.assignment_return,
              color: AppColors.error,
            ),
            StatCard(
              title: 'With Driver',
              value: '0',
              icon: Icons.delivery_dining,
              color: AppColors.primaryRed,
            ),
          ],
        ),
      ],
    );
  }
}