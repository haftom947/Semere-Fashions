import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/colors.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class ConflictResolutionScreen extends StatefulWidget {
  const ConflictResolutionScreen({super.key});

  @override
  _ConflictResolutionScreenState createState() => _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _conflicts = [];

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    var conflicts = await _dbHelper.getConflicts();
    setState(() {
      _conflicts = conflicts;
    });
  }

  Future<void> _resolveConflict(Map<String, dynamic> conflict, String resolution, [Map<String, dynamic>? merged]) async {
    await _syncService.resolveConflict(conflict['id'], resolution, merged);
    await _loadConflicts();
  }

  void _showMergeDialog(Map<String, dynamic> conflict) {
    Map<String, dynamic> local = jsonDecode(conflict['localData']);
    Map<String, dynamic> server = jsonDecode(conflict['serverData']);
    // Simple merge UI – just show fields side by side and let user pick
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Merge Conflict - ${conflict['tableName']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Local', style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: ListView(
                              children: local.entries.map((e) => Text('${e.key}: ${e.value}')).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Server', style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: ListView(
                              children: server.entries.map((e) => Text('${e.key}: ${e.value}')).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              // For simplicity, just pick server
              _resolveConflict(conflict, 'server');
              Navigator.pop(context);
            },
            child: const Text('Use Server'),
          ),
          ElevatedButton(
            onPressed: () {
              _resolveConflict(conflict, 'local');
              Navigator.pop(context);
            },
            child: const Text('Use Local'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Conflicts'),
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
        child: _conflicts.isEmpty
            ? const Center(
                child: Text('No conflicts!', style: TextStyle(color: AppColors.white)),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _conflicts.length,
                itemBuilder: (context, index) {
                  var conflict = _conflicts[index];
                  return Card(
                    child: ListTile(
                      title: Text('${conflict['tableName']} - ${conflict['recordId']}'),
                      subtitle: Text('Conflict detected at ${DateTime.fromMillisecondsSinceEpoch(conflict['timestamp'])}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.compare_arrows, color: AppColors.info),
                            onPressed: () => _showMergeDialog(conflict),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}