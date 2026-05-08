import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';
import '../utils/error_handler.dart';
import '../utils/locale_provider.dart';
import '../utils/translations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();

  bool _autoSync = true;
  bool _isAmharic = false;
  bool _isLoading = false;
  final String _appVersion = '1.0.0';
  int _localRecordCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadStats();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoSync = prefs.getBool('autoSync') ?? true;
      final langCode = prefs.getString('languageCode') ?? 'en';
      _isAmharic = langCode == 'am';
    });
  }

  Future<void> _loadStats() async {
    final users = await _dbHelper.query('users');
    final orders = await _dbHelper.query('orders');
    if (!mounted) return;
    setState(() {
      _localRecordCount = users.length + orders.length;
    });
  }

  Future<void> _toggleAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSync', value);
    if (!mounted) return;
    setState(() => _autoSync = value);
    if (value) {
      await _syncService.syncAll();
    }
  }

  Future<void> _toggleLanguage(bool value) async {
    setState(() => _isAmharic = value);
    final newLocale = value ? const Locale('am') : const Locale('en');
    await Provider.of<LocaleProvider>(
      context,
      listen: false,
    ).setLocale(newLocale);
  }

  Future<void> _clearDashboardCache() async {
    setState(() => _isLoading = true);
    try {
      final db = await _dbHelper.database;
      await db.delete('dashboard_cache');
      if (mounted) {
        ErrorHandler.showSuccess(context, context.tr('dashboard_cache_cleared'));
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          context.tr('failed_to_clear_cache', args: {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _forceSync() async {
    setState(() => _isLoading = true);
    try {
      await _syncService.syncAll();
      if (mounted) {
        ErrorHandler.showSuccess(context, context.tr('sync_completed'));
      }
      await _loadStats();
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          context.tr('sync_failed', args: {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportDatabase() async {
    ErrorHandler.showWarning(context, context.tr('export_feature_coming_soon'));
  }

  Future<void> _resetAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: Text(
            context.tr('reset_all_data'),
            style: const TextStyle(color: Colors.black),
          ),
          content: Text(
            context.tr('delete_all_data_message'),
            style: const TextStyle(color: Colors.black),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.tr('reset'),
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final db = await _dbHelper.database;
      final tables = await db.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ''',
      );

      for (final row in tables) {
        final tableName = row['name']?.toString();
        if (tableName == null || tableName.isEmpty) continue;
        await db.delete(tableName);
      }

      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          context.tr('reset_failed', args: {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings')),
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
            : ListView(
                children: [
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(
                      context.tr('language_amharic'),
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      context.tr('switch_to_amharic'),
                      style: TextStyle(color: Colors.white70),
                    ),
                    value: _isAmharic,
                    onChanged: _toggleLanguage,
                    activeColor: AppColors.primaryRed,
                  ),
                  const Divider(color: AppColors.white, height: 1),
                  SwitchListTile(
                    title: Text(
                      context.tr('auto_sync'),
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      context.tr('auto_sync_subtitle'),
                      style: TextStyle(color: Colors.white70),
                    ),
                    value: _autoSync,
                    onChanged: _toggleAutoSync,
                    activeColor: AppColors.primaryRed,
                  ),
                  const Divider(color: AppColors.white, height: 1),
                  ListTile(
                    leading: const Icon(Icons.sync, color: AppColors.white),
                    title: Text(
                      context.tr('force_sync_now'),
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      context.tr(
                        'local_records',
                        args: {'count': '$_localRecordCount'},
                      ),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: _forceSync,
                  ),
                  const Divider(color: AppColors.white, height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.clear_all,
                      color: AppColors.white,
                    ),
                    title: Text(
                      context.tr('clear_dashboard_cache'),
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      context.tr('refresh_dashboard_data'),
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: _clearDashboardCache,
                  ),
                  const Divider(color: AppColors.white, height: 1),
                  ListTile(
                    leading: const Icon(Icons.download, color: AppColors.white),
                    title: Text(
                      context.tr('export_database'),
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      context.tr('save_local_database'),
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: _exportDatabase,
                  ),
                  const Divider(color: AppColors.white, height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever,
                      color: AppColors.error,
                    ),
                    title: Text(
                      context.tr('reset_all_local_data'),
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      context.tr('delete_all_data_subtitle'),
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: _resetAllData,
                  ),
                  const Divider(color: AppColors.white, height: 1),
                  ListTile(
                    leading: const Icon(Icons.info, color: AppColors.white),
                    title: Text(
                      context.tr('app_version'),
                      style: TextStyle(color: AppColors.white),
                    ),
                    subtitle: Text(
                      _appVersion,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }
}
