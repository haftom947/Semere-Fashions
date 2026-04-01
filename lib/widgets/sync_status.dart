import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class SyncStatus extends StatefulWidget {
  const SyncStatus({super.key});

  @override
  _SyncStatusState createState() => _SyncStatusState();
}

class _SyncStatusState extends State<SyncStatus> {
  final SyncService _syncService = SyncService();
  bool _isOnline = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
      if (_isOnline) _syncService.syncAll();
    });
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);
    await _syncService.syncAll();
    setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isOnline
            ? (_isSyncing ? AppColors.info : AppColors.success)
            : AppColors.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isOnline ? (_isSyncing ? Icons.sync : Icons.wifi) : Icons.wifi_off,
            color: AppColors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            _isOnline ? (_isSyncing ? 'Syncing...' : 'Online') : 'Offline',
            style: const TextStyle(color: AppColors.white, fontSize: 12),
          ),
          if (_isOnline && !_isSyncing)
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.white, size: 16),
              onPressed: _manualSync,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
