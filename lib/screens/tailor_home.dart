import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/colors.dart';
import '../utils/currency_helper.dart';
import '../widgets/drawer_menu.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class TailorHome extends StatefulWidget {
  const TailorHome({super.key});

  @override
  _TailorHomeState createState() => _TailorHomeState();
}

class _TailorHomeState extends State<TailorHome> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _dataChangedSubscription;
  String _tailorName = 'Tailor';
  String _tailorId = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _assignedOrders = [];
  bool _initialSyncTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadTailorData();
    _dataChangedSubscription = _syncService.dataChangedStream.listen((_) {
      _loadAssignedOrders();
    });
  }

  @override
  void dispose() {
    _dataChangedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _triggerInitialSync() async {
    if (_initialSyncTriggered) return;
    _initialSyncTriggered = true;
    await _syncService.syncAll();
  }

  Future<void> _loadTailorData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _tailorId = user.uid;
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            _tailorName = userDoc.get('name') ?? 'Tailor';
          });
        }
        await _triggerInitialSync();
      }
    } catch (e) {
      print('Error loading tailor data: $e');
    } finally {
      _loadAssignedOrders();
    }
  }

  Future<void> _loadAssignedOrders() async {
    if (_tailorId.isEmpty) return;
    var orders = List<Map<String, dynamic>>.from(
      await _dbHelper.query('orders'),
    );
    // Look for assignments where this tailor is assigned
    // We need to fetch order_assignments for tailor role
    var allAssignments = List<Map<String, dynamic>>.from(
      await _dbHelper.query('order_assignments'),
    );
    var tailorAssignments = allAssignments
        .where((a) => a['employeeId'] == _tailorId && a['role'] == 'tailor')
        .map((a) => a['orderId'])
        .toSet();

    var assigned = orders
        .where(
          (o) =>
              tailorAssignments.contains(o['id']) &&
              (o['status'] == 'pending' ||
                  o['status'] == 'processing' ||
                  o['status'] == 'out_for_delivery'),
        )
        .toList();

    assigned.sort(
      (a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int),
    );
    setState(() {
      _assignedOrders = assigned;
      _isLoading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DrawerMenu(role: 'tailor'),
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
                        onPressed: _loadAssignedOrders,
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
                                'Welcome, $_tailorName!',
                                style: const TextStyle(
                                  color: AppColors.darkGrey,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Here are your assigned orders.',
                                style: TextStyle(
                                  color: AppColors.mediumGrey,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // My Assigned Orders
                        const Text(
                          'My Assigned Orders',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _assignedOrders.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text(
                                    'No assigned orders',
                                    style: TextStyle(
                                      color: AppColors.mediumGrey,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _assignedOrders.length,
                                itemBuilder: (context, index) {
                                  var order = _assignedOrders[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: AppColors.primaryRed,
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: AppColors.white,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        'Order #${order['id'].substring(0, 8)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Customer: ${order['customerName'] ?? 'Unknown'}',
                                          ),
                                          Text(
                                            'Amount: ${CurrencyHelper.formatAmount((order['totalAmount'] as num?)?.toDouble(), order['currency'])}',
                                          ),
                                        ],
                                      ),
                                      trailing: Chip(
                                        label: Text(
                                          order['status'] ?? 'pending',
                                          style: const TextStyle(
                                            color: AppColors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                        backgroundColor:
                                            order['status'] == 'pending'
                                            ? AppColors.warning
                                            : order['status'] == 'processing'
                                            ? AppColors.info
                                            : AppColors.accent,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
