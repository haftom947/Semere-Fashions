import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
import '../services/sync_service.dart';
import '../services/database_helper.dart';
import '../screens/conflict_resolution_screen.dart';

class DrawerMenu extends StatefulWidget {
  final String role;
  const DrawerMenu({Key? key, required this.role}) : super(key: key);

  @override
  _DrawerMenuState createState() => _DrawerMenuState();
}

class _DrawerMenuState extends State<DrawerMenu> {
  final SyncService _syncService = SyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isOnline = true;
  int _conflictCount = 0;
  int? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _checkOnlineStatus();
    _loadConflictCount();
    _loadLastSyncTime();
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
    });
    _syncService.dataChangedStream.listen((_) {
      _loadConflictCount();
      _loadLastSyncTime();
    });
  }

  Future<void> _checkOnlineStatus() async {
    var result = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  Future<void> _loadConflictCount() async {
    var conflicts = await _dbHelper.getConflicts();
    setState(() {
      _conflictCount = conflicts.length;
    });
  }

  Future<void> _loadLastSyncTime() async {
    var time = await _dbHelper.getLatestSyncTime();
    setState(() {
      _lastSyncTime = time;
    });
  }

  Future<void> _manualSync() async {
    if (_isOnline) {
      await _syncService.syncAll();
      _loadLastSyncTime();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync completed')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection')),
      );
    }
  }

  void _navigateToScreen(BuildContext context, String routeName) {
    Navigator.pushNamed(context, routeName);
  }

  void _logout(BuildContext context) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context, 
                    '/login', 
                    (route) => false
                  );
                }
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  String _formatLastSync() {
    if (_lastSyncTime == null) return 'Never';
    final date = DateTime.fromMillisecondsSinceEpoch(_lastSyncTime!);
    return DateFormat('dd/MM/yy HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: Column(
          children: [
            // Drawer Header with sync status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.white,
                        child: Text(
                          widget.role[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primaryRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Semere Fashions',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.role.toUpperCase(),
                              style: TextStyle(
                                color: AppColors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Sync status row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isOnline ? AppColors.success : AppColors.error,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: _isOnline ? AppColors.success : AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (_conflictCount > 0)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ConflictResolutionScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning, color: AppColors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '$_conflictCount conflict${_conflictCount > 1 ? 's' : ''}',
                                  style: const TextStyle(color: AppColors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.sync, color: AppColors.white, size: 20),
                        onPressed: _manualSync,
                      ),
                    ],
                  ),
                  // Last sync time
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Last sync: ${_formatLastSync()}',
                      style: TextStyle(
                        color: AppColors.white.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Drawer Items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Dashboard
                  _buildDrawerItem(
                    Icons.dashboard, 
                    'Dashboard', 
                    () {
                      Navigator.pop(context);
                      if (widget.role == 'admin') {
                        _navigateToScreen(context, '/admin');
                      } else if (widget.role == 'manager') {
                        _navigateToScreen(context, '/manager');
                      } else if (widget.role == 'sales') {
                        _navigateToScreen(context, '/sales');
                      } else {
                        _navigateToScreen(context, '/tailor');
                      }
                    },
                  ),
                  
                  // Orders
                  _buildDrawerItem(
                    Icons.shopping_bag, 
                    'Orders', 
                    () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/orders');
                    },
                  ),
                  
                  // Inventory
                  _buildDrawerItem(
                    Icons.inventory, 
                    'Inventory', 
                    () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/inventory');
                    },
                  ),
                  
                  // Employees (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.people, 
                      'Employees', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/employees');
                      },
                    ),
                  
                  // Customers
                  _buildDrawerItem(
                    Icons.person, 
                    'Customers', 
                    () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/customers');
                    },
                  ),
                  
                  // Reports (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.receipt, 
                      'Reports', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/reports');
                      },
                    ),
                  
                  // Branches (Admin only)
                  if (widget.role == 'admin')
                    _buildDrawerItem(
                      Icons.store, 
                      'Branches', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/branches');
                      },
                    ),
                  
                  // Equipment (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.build, 
                      'Equipment', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/equipment');
                      },
                    ),
                  
                  // Suppliers (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.business, 
                      'Suppliers', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/suppliers');
                      },
                    ),
                  
                  // Measurement Types (Admin only)
                  if (widget.role == 'admin')
                    _buildDrawerItem(
                      Icons.straighten, 
                      'Measurement Types', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/measurement_types');
                      },
                    ),
                  
                  // Accounts (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.account_balance, 
                      'Accounts', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/accounts');
                      },
                    ),
                  
                  // Cash Flow (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.timeline, 
                      'Cash Flow', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/cashflow');
                      },
                    ),
                  
                  // Commissions (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.monetization_on, 
                      'Commissions', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/commissions');
                      },
                    ),
                  
                  // Purchase Orders (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.shopping_cart, 
                      'Purchase Orders', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/purchase_orders');
                      },
                    ),
                  
                  // Production Orders (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.factory, 
                      'Production', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/production');
                      },
                    ),
                  
                  // Social Dashboard (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.bar_chart, 
                      'Social Dashboard', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/social_dashboard');
                      },
                    ),
                  
                  // Social Accounts (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.share, 
                      'Social Accounts', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/social');
                      },
                    ),
                  
                  // Employee Payments (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.payment, 
                      'Employee Payments', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/employee_payments');
                      },
                    ),
                  
                  // Leave Request (Employees)
                  if (widget.role == 'sales' || widget.role == 'tailor' || widget.role == 'delivery')
                    _buildDrawerItem(
                      Icons.beach_access, 
                      'Request Leave', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/leave_request');
                      },
                    ),
                  
                  // Leave Requests (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.list, 
                      'Leave Requests', 
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/leave_requests');
                      },
                    ),
                  
                  const Divider(color: AppColors.white),
                  
                  // Settings
                  _buildDrawerItem(
                    Icons.settings, 
                    'Settings', 
                    () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Settings coming soon')),
                      );
                    },
                  ),
                  
                  // Logout
                  _buildDrawerItem(
                    Icons.logout, 
                    'Logout', 
                    () => _logout(context),
                  ),
                ],
              ),
            ),
            
            // App version at bottom
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Version 1.0.0',
                style: TextStyle(
                  color: AppColors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.white),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}