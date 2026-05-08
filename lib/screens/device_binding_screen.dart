import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';

class DeviceBindingScreen extends StatefulWidget {
  const DeviceBindingScreen({Key? key}) : super(key: key);

  @override
  State<DeviceBindingScreen> createState() => _DeviceBindingScreenState();
}

class _DeviceBindingScreenState extends State<DeviceBindingScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshUsers(showOfflineMessage: false);
  }

  Future<void> _refreshUsers({bool showOfflineMessage = true}) async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      await _syncService.syncAll();
      await _loadUsersFromFirestore();
    } catch (_) {
      await _loadUsersFromLocal(showOfflineMessage: showOfflineMessage);
    }
  }

  Future<void> _loadUsersFromFirestore() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final users = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      if (data.containsKey('deviceId') && !data.containsKey('device_id')) {
        data['device_id'] = data['deviceId'];
      }
      return data;
    }).toList();

    users.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  Future<void> _loadUsersFromLocal({required bool showOfflineMessage}) async {
    final localUsers = await _dbHelper.queryAll('users');
    localUsers.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _users = localUsers;
      _isLoading = false;
    });

    if (showOfflineMessage) {
      ErrorHandler.showWarning(context, 'Using offline data. Pull to refresh.');
    }
  }

  Future<void> _resetBinding(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();
    final userName = user['name']?.toString().trim().isNotEmpty == true
        ? user['name'].toString().trim()
        : 'this user';

    if (userId == null || userId.isEmpty) {
      ErrorHandler.showError(context, 'User ID is missing.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Device Binding'),
        content: Text(
          '$userName will be able to log in from any device. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: AppColors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'deviceId': FieldValue.delete(),
      });

      await _dbHelper.update('users', {
        'id': userId,
        'device_id': null,
      });

      await _refreshUsers(showOfflineMessage: false);
      if (mounted) {
        ErrorHandler.showSuccess(context, 'Binding reset for $userName');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.showError(context, 'Failed to reset binding: $e');
      }
    }
  }

  String _formatDeviceId(dynamic deviceId) {
    final value = deviceId?.toString().trim() ?? '';
    if (value.isEmpty) return 'Not bound';
    if (value.length <= 18) return 'Device: $value';
    return 'Device: ${value.substring(0, 18)}...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Binding'),
        backgroundColor: AppColors.primaryRed,
      ),
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
            : RefreshIndicator(
                onRefresh: _refreshUsers,
                child: _users.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 180),
                          Center(
                            child: Text(
                              'No users found',
                              style: TextStyle(color: AppColors.white),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final deviceId = user['device_id'];
                          final isBound =
                              deviceId != null &&
                              deviceId.toString().trim().isNotEmpty;
                          final role = (user['role'] ?? '')
                              .toString()
                              .toUpperCase();
                          final name = (user['name'] ?? 'Unknown User')
                              .toString();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: AppColors.cardBackground,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (role.isNotEmpty)
                                      Text(
                                        role,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDeviceId(deviceId),
                                      style: TextStyle(
                                        color: isBound
                                            ? AppColors.success
                                            : AppColors.warning,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: isBound
                                  ? TextButton.icon(
                                      onPressed: () => _resetBinding(user),
                                      icon: const Icon(
                                        Icons.link_off,
                                        color: AppColors.primaryRed,
                                      ),
                                      label: const Text(
                                        'Reset',
                                        style: TextStyle(
                                          color: AppColors.primaryRed,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
