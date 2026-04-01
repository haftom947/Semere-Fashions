import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/colors.dart';

class ConflictResolutionScreen extends StatefulWidget {
  const ConflictResolutionScreen({super.key});

  @override
  State<ConflictResolutionScreen> createState() =>
      _ConflictResolutionScreenState();
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
    final conflicts = await _dbHelper.getConflicts();
    if (!mounted) return;
    setState(() {
      _conflicts = conflicts;
    });
  }

  Future<void> _resolveConflict(
    Map<String, dynamic> conflict,
    String resolution, [
    Map<String, dynamic>? merged,
  ]) async {
    await _syncService.resolveConflict(conflict['id'], resolution, merged);
    await _loadConflicts();
  }

  Set<String> _conflictingFields(
    Map<String, dynamic> conflict,
    Map<String, dynamic> local,
    Map<String, dynamic> server,
  ) {
    final raw = conflict['conflictingFields'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
    }

    return {
      for (final key in {...local.keys, ...server.keys})
        if (key != 'syncStatus' &&
            key != 'lastModified' &&
            local[key] != server[key])
          key.toString(),
    };
  }

  Widget _buildConflictDetails(
    Map<String, dynamic> conflict,
    Map<String, dynamic> local,
    Map<String, dynamic> server,
  ) {
    final fields = _conflictingFields(conflict, local, server).toList()..sort();
    if (fields.isEmpty) {
      return const Text(
        'No field-level differences found.',
        style: TextStyle(color: Colors.black54),
      );
    }

    return Column(
      children: fields.map((field) {
        final localValue = local[field];
        final serverValue = server[field];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Local:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          _formatValue(localValue),
                          style: const TextStyle(color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Server:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          _formatValue(serverValue),
                          style: const TextStyle(color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return '(empty)';
    if (value is num) return value.toString();
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is String) return value;
    if (value is List) return '[ ${value.join(', ')} ]';
    if (value is Map) return '{ ... }';
    return value.toString();
  }

  void _showResolutionDialog(Map<String, dynamic> conflict) {
    final local = Map<String, dynamic>.from(
      jsonDecode(conflict['localData']) as Map,
    );
    final server = Map<String, dynamic>.from(
      jsonDecode(conflict['serverData']) as Map,
    );

    showDialog(
      context: context,
      builder: (context) => Theme(
        data: ThemeData.light(),
        child: AlertDialog(
          title: Text(
            'Conflict in ${conflict['tableName']}',
            style: const TextStyle(color: Colors.black),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Only the conflicting fields are shown below:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                _buildConflictDetails(conflict, local, server),
                const SizedBox(height: 16),
                const Text(
                  'Choose which version to keep:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
            ElevatedButton(
              onPressed: () {
                _resolveConflict(conflict, 'local');
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
              child: const Text('Keep Local'),
            ),
            ElevatedButton(
              onPressed: () {
                _resolveConflict(conflict, 'server');
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
              child: const Text('Use Server'),
            ),
          ],
        ),
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
                child: Text(
                  'No conflicts!',
                  style: TextStyle(color: AppColors.white),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _conflicts.length,
                itemBuilder: (context, index) {
                  final conflict = _conflicts[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.warning,
                        color: AppColors.warning,
                      ),
                      title: Text(
                        '${conflict['tableName']} - ${conflict['recordId']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Conflicted at ${DateTime.fromMillisecondsSinceEpoch(conflict['timestamp'])}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showResolutionDialog(conflict),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
