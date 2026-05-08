import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
import '../services/sync_service.dart';
import '../services/database_helper.dart';
import '../screens/conflict_resolution_screen.dart';
import '../screens/device_binding_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/retail_products_screen.dart';
import '../utils/translations.dart';

class DrawerMenu extends StatefulWidget {
  final String role;
  const DrawerMenu({Key? key, required this.role}) : super(key: key);

  @override
  _DrawerMenuState createState() => _DrawerMenuState();
}

class _DrawerMenuState extends State<DrawerMenu> {
  final SyncService _syncService = SyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOnline = true;
  int _conflictCount = 0;
  int? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _checkOnlineStatus();
    _loadConflictCount();
    _loadLastSyncTime();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> result,
    ) {
      if (mounted) {
        setState(() {
          _isOnline = !result.contains(ConnectivityResult.none);
        });
      }
    });

    _syncService.dataChangedStream.listen((_) {
      if (mounted) {
        _loadConflictCount();
        _loadLastSyncTime();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _checkOnlineStatus() async {
    var result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = !result.contains(ConnectivityResult.none);
      });
    }
  }

  Future<void> _loadConflictCount() async {
    var conflicts = await _dbHelper.getConflicts();
    if (mounted) {
      setState(() {
        _conflictCount = conflicts.length;
      });
    }
  }

  Future<void> _loadLastSyncTime() async {
    var time = await _dbHelper.getLatestSyncTime();
    if (mounted) {
      setState(() {
        _lastSyncTime = time;
      });
    }
  }

  Future<void> _manualSync() async {
    if (_isOnline) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('syncing'))));
      await _syncService.syncAll();
      if (mounted) {
        _loadLastSyncTime();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('sync_completed'))));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(context.tr('error_no_internet'))),
        );
      }
    }
  }

  void _navigateToScreen(BuildContext context, String routeName) {
    Navigator.pushNamed(context, routeName);
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: Text(
            context.tr('logout'),
            style: const TextStyle(color: Colors.black),
          ),
          content: Text(
            context.tr('are_you_sure_logout'),
            style: const TextStyle(color: Colors.black),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                context.tr('cancel'),
                style: const TextStyle(color: Colors.blue),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                context.tr('logout'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('userRole');
      await prefs.remove('userId');
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }
    String _formatLastSync() {
      if (_lastSyncTime == null) return context.tr('never');
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
                            Text(
                              context.tr('semere_fashions'),
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
                              color: _isOnline
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isOnline
                                ? context.tr('online')
                                : context.tr('offline'),
                            style: TextStyle(
                              color: _isOnline
                                  ? AppColors.success
                                  : AppColors.error,
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
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ConflictResolutionScreen(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning,
                                  color: AppColors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_conflictCount} ${context.tr('sync_conflicts')}',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.sync,
                          color: AppColors.white,
                          size: 20,
                        ),
                        onPressed: _manualSync,
                      ),
                    ],
                  ),
                  // Last sync time
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.tr(
                        'last_sync',
                        args: {'time': _formatLastSync()},
                      ),
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
                  _buildDrawerItem(Icons.dashboard, context.tr('dashboard'), () {
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
                  }),

                  // Orders
                  _buildDrawerItem(Icons.shopping_bag, context.tr('orders'), () {
                    Navigator.pop(context);
                    _navigateToScreen(context, '/orders');
                  }),

                  // Inventory
                  _buildDrawerItem(Icons.inventory, context.tr('inventory'), () {
                    Navigator.pop(context);
                    _navigateToScreen(context, '/inventory');
                  }),

                  // Employees (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.people, context.tr('employees'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/employees');
                    }),

                  // Customers
                  _buildDrawerItem(Icons.person, context.tr('customers'), () {
                    Navigator.pop(context);
                    _navigateToScreen(context, '/customers');
                  }),

                  // Reports (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.receipt, context.tr('reports'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/reports');
                    }),

                  // Branches (Admin only)
                  if (widget.role == 'admin')
                    _buildDrawerItem(Icons.store, context.tr('branches'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/branches');
                    }),

                  // Equipment (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.build, context.tr('equipment'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/equipment');
                    }),
                  // Properties (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.apartment,
                      context.tr('properties'),
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/properties');
                      },
                    ),
                  // Suppliers (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.business, context.tr('suppliers'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/suppliers');
                    }),

                  // Measurement Types (Admin only)
                  if (widget.role == 'admin')
                    _buildDrawerItem(Icons.straighten, context.tr('measurement_types'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/measurement_types');
                    }),

                  if (widget.role == 'admin')
                    _buildDrawerItem(Icons.badge, context.tr('roles'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/roles');
                    }),

                  if (widget.role == 'admin')
                    _buildDrawerItem(Icons.devices, context.tr('device_binding'), () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DeviceBindingScreen(),
                        ),
                      );
                    }),

                  // Accounts (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.account_balance, context.tr('accounts'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/accounts');
                    }),

                  // Cash Flow (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.timeline, context.tr('cash_flow'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/cashflow');
                    }),

                  // Commissions (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.monetization_on, context.tr('commissions'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/commissions');
                    }),

                  // Purchase Orders (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(
                      Icons.shopping_cart,
                      context.tr('purchase_orders'),
                      () {
                        Navigator.pop(context);
                        _navigateToScreen(context, '/purchase_orders');
                      },
                    ),

                  // Production Orders (removed — replaced by Retail Products)

                  // Retail Products (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.shopping_bag, context.tr('retail_products'), () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RetailProductsScreen(),
                        ),
                      );
                    }),

                  // Social Dashboard (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.bar_chart, context.tr('social_dashboard'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/social_dashboard');
                    }),

                  // Social Accounts (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.share, context.tr('social_accounts'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/social');
                    }),

                  // Employee Payments (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.payment, context.tr('employee_payments'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/employee_payments');
                    }),

                  // Leave Request (Employees)
                  if (widget.role == 'sales' ||
                      widget.role == 'tailor' ||
                      widget.role == 'delivery')
                    _buildDrawerItem(Icons.beach_access, context.tr('request_leave'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/leave_request');
                    }),

                  // Leave Requests (Admin and Manager only)
                  if (widget.role == 'admin' || widget.role == 'manager')
                    _buildDrawerItem(Icons.list, context.tr('leave_requests'), () {
                      Navigator.pop(context);
                      _navigateToScreen(context, '/leave_requests');
                    }),

                  const Divider(color: AppColors.white),

                  // Settings
                  _buildDrawerItem(Icons.settings, context.tr('settings'), () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  }),

                  // Logout
                  _buildDrawerItem(
                    Icons.logout,
                    context.tr('logout'),
                    () => _logout(context),
                  ),
                ],
              ),
            ),

            // App version at bottom
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('version'),
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
