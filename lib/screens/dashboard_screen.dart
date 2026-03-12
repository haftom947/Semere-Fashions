import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../widgets/stat_card.dart';
import '../widgets/category_card.dart';
import '../widgets/recent_order_card.dart';
import '../widgets/drawer_menu.dart';

class DashboardScreen extends StatefulWidget {
  final String role;
  const DashboardScreen({super.key, required this.role});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _userName = 'User';
  String _branchName = 'Branch';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          setState(() {
            _userName = userDoc.get('name') ?? 'User';
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
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context, 
        '/login', 
        (route) => false
      );
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
      drawer: DrawerMenu(role: widget.role),
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
                  // App Bar with Menu and Logout
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
                          setState(() => _isLoading = true);
                          _loadUserData();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: AppColors.white),
                        onPressed: _logout,
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Background gradient
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
                              ),
                            ),
                          ),
                          // Decorative pattern
                          Positioned(
                            bottom: -50,
                            right: -50,
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.white.withOpacity(0.1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Main Content
                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Profile Card
                        GestureDetector(
                          onTap: _navigateToEmployees,
                          child: Container(
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
                                    radius: 30,
                                    backgroundColor: AppColors.primaryRed.withOpacity(0.1),
                                    child: Text(
                                      widget.role[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.primaryRed,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 24,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _userName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.darkGrey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${widget.role} · $_branchName',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: AppColors.mediumGrey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryRed.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Text(
                                            'Balance: ETB 15,230',
                                            style: TextStyle(
                                              color: AppColors.primaryRed,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Welcome Message
                        Text(
                          'Good ${_getTimeOfDay()}, $_userName!',
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
                        
                        // Quick Actions Row
                        _buildQuickActions(),
                        const SizedBox(height: 24),
                        
                        // Stats Overview
                        _buildStatsSection(),
                        const SizedBox(height: 24),
                        
                        // Order Categories
                        _buildCategoriesSection(),
                        const SizedBox(height: 24),
                        
                        // Recent Orders
                        _buildRecentOrdersSection(),
                        const SizedBox(height: 24),
                        
                        // Account Summary
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

  String _getTimeOfDay() {
    var hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Morning';
    } else if (hour < 17) {
      return 'Afternoon';
    } else {
      return 'Evening';
    }
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
            _buildActionButton(Icons.people, 'Employees', AppColors.success, _navigateToEmployees),
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        int totalOrders = 0;
        int pendingOrders = 0;
        int completedOrders = 0;
        double totalRevenue = 0;

        if (snapshot.hasData) {
          totalOrders = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            String status = doc.get('status') ?? '';
            if (status == 'pending') pendingOrders++;
            if (status == 'delivered') completedOrders++;
            totalRevenue += (doc.get('total_amount') ?? 0).toDouble();
          }
        }

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
                    value: totalOrders.toString(),
                    icon: Icons.shopping_bag,
                    color: AppColors.primaryRed,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToReports,
                  child: StatCard(
                    title: 'Revenue',
                    value: 'ETB ${totalRevenue.toStringAsFixed(0)}',
                    icon: Icons.attach_money,
                    color: AppColors.success,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToOrders,
                  child: StatCard(
                    title: 'Pending',
                    value: pendingOrders.toString(),
                    icon: Icons.pending_actions,
                    color: AppColors.warning,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToOrders,
                  child: StatCard(
                    title: 'Completed',
                    value: completedOrders.toString(),
                    icon: Icons.check_circle,
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
                onTap: _navigateToOrders,
                child: CategoryCard(
                  title: 'To Deliver',
                  count: '0',
                  color: AppColors.primaryRed,
                  icon: Icons.delivery_dining,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _navigateToOrders,
                child: CategoryCard(
                  title: 'To Pick Up',
                  count: '0',
                  color: AppColors.warning,
                  icon: Icons.inventory,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _navigateToOrders,
                child: CategoryCard(
                  title: 'Delivered',
                  count: '0',
                  color: AppColors.success,
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _navigateToOrders,
                child: CategoryCard(
                  title: 'Cancelled',
                  count: '0',
                  color: AppColors.error,
                  icon: Icons.cancel,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _navigateToOrders,
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
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .orderBy('created_date', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Container(
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
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                var order = snapshot.data!.docs[index];
                return GestureDetector(
                  onTap: _navigateToOrders,
                  child: RecentOrderCard(
                    orderId: order.id,
                    customer: order.get('customer_name') ?? 'Unknown',
                    amount: 'ETB ${order.get('total_amount') ?? 0}',
                    status: order.get('status') ?? 'pending',
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildAccountSummary() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        double totalPaid = 0;
        double totalPending = 0;
        int totalOrders = 0;
        int returned = 0;

        if (snapshot.hasData) {
          totalOrders = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            double amount = (doc.get('total_amount') ?? 0).toDouble();
            String status = doc.get('status') ?? '';
            
            if (status == 'delivered') {
              totalPaid += amount;
            } else if (status == 'pending') {
              totalPending += amount;
            } else if (status == 'returned') {
              returned++;
            }
          }
        }

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
                    value: totalOrders.toString(),
                    icon: Icons.shopping_cart,
                    color: AppColors.primaryRed,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToReports,
                  child: StatCard(
                    title: 'Total Paid',
                    value: 'ETB ${totalPaid.toStringAsFixed(0)}',
                    icon: Icons.paid,
                    color: AppColors.success,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToOrders,
                  child: StatCard(
                    title: 'Pending',
                    value: 'ETB ${totalPending.toStringAsFixed(0)}',
                    icon: Icons.pending,
                    color: AppColors.warning,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToReports,
                  child: StatCard(
                    title: 'To Collect',
                    value: 'ETB ${(totalPending * 0.9).toStringAsFixed(0)}',
                    icon: Icons.account_balance_wallet,
                    color: AppColors.info,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToOrders,
                  child: StatCard(
                    title: 'Returned',
                    value: returned.toString(),
                    icon: Icons.assignment_return,
                    color: AppColors.error,
                  ),
                ),
                GestureDetector(
                  onTap: _navigateToOrders,
                  child: StatCard(
                    title: 'With Driver',
                    value: '0',
                    icon: Icons.delivery_dining,
                    color: AppColors.primaryRed,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}