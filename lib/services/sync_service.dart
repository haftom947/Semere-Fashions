import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final _dataChangedController = StreamController<bool>.broadcast();
  Stream<bool> get dataChangedStream => _dataChangedController.stream;
  Future<void>? _activeSync;
  void emitDataChanged() {
  _dataChangedController.add(true);
}

  final Map<String, String> _collectionMap = {
    'users': 'users',
    'orders': 'orders',
    'material_usage': 'material_usage',
    'products': 'products',
    'materials': 'materials',
    'equipment': 'equipment',
    'customers': 'customers',
    'branches': 'branches',
    'suppliers': 'suppliers',
    'properties': 'properties',
    'tenants': 'tenants',
    'rent_payments': 'rent_payments',
    'rent_dues': 'rent_dues',
    'social_accounts': 'social_accounts',
    'social_metrics': 'social_metrics',
    'purchase_orders': 'purchase_orders',
    'purchase_order_items': 'purchase_order_items',
    'fuel_logs': 'fuel_logs',
    'maintenance_logs': 'maintenance_logs',
    'checkout_logs': 'checkout_logs',
    'commissions': 'commissions',
    'accounts': 'accounts',
    'transactions': 'transactions',
    'payment_transaction': 'payment_transaction',
    'payment_breakdown': 'payment_breakdown',
    'order_assignments': 'order_assignments',
    'measurement_types': 'measurement_types',
    'measurements': 'measurements',
  };
  static const Set<String> _safeFields = {
    'notes',
    'description',
    'lastModified',
    'changed_fields',
  };
  static const Set<String> _criticalFields = {
    'status',
    'customerId',
    'customer_name',
    'totalAmount',
    'assignedTailor',
    'deliveryPerson',
    'salesPersonId',
    'branchId',
    'tailorId',
    'employeeId',
  };
  static const Set<String> _conditionalFields = {
    'paid_amount',
    'tip_amount',
  };

  Stream<bool> get onlineStream => Connectivity().onConnectivityChanged.map(
    (statuses) => !statuses.contains(ConnectivityResult.none),
  );

  void triggerBackgroundSync() {
    unawaited(syncAll());
  }

  Future<bool> isOnline() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    final online = !connectivityResults.contains(ConnectivityResult.none);
    print('Online: $online');
    return online;
  }

  Future<void> syncAll() async {
    if (_activeSync != null) {
      print('Sync already in progress, waiting for current run');
      return _activeSync!;
    }

    if (FirebaseAuth.instance.currentUser == null) {
      print('Skipping sync: no authenticated user');
      return;
    }

    final completer = Completer<void>();
    _activeSync = completer.future;

    print('syncAll started');
    try {
      if (!await isOnline()) {
        print('No internet connection');
        return;
      }

      print('Uploading pending records...');
      await _uploadPending();
      print('Uploading pending deletions...');
      await _uploadDeletions();
      print('Downloading remote changes...');
      await _downloadChanges();
      _dataChangedController.add(true);
      print('syncAll completed');
    } finally {
      completer.complete();
      _activeSync = null;
    }
  }

  Map<String, dynamic> _convertFirestoreData(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.millisecondsSinceEpoch);
      } else if (value is List) {
        return MapEntry(key, jsonEncode(value));
      } else if (value is DocumentReference) {
        return MapEntry(key, value.path);
      } else {
        return MapEntry(key, value);
      }
    });
  }

  Map<String, dynamic> _normalizeForLocalWrite(
    String table,
    Map<String, dynamic> data,
  ) {
    final normalized = Map<String, dynamic>.from(data);
    if (table == 'users') {
      if (normalized.containsKey('deviceId') &&
          !normalized.containsKey('device_id')) {
        normalized['device_id'] = normalized['deviceId'];
      }
      normalized.remove('deviceId');
    }
    return normalized;
  }

  Set<String> _decodeChangedFields(dynamic value) {
    if (value == null) return <String>{};
    if (value is String) {
      if (value.trim().isEmpty) return <String>{};
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.keys.map((k) => k.toString()).toSet();
        }
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {
        return <String>{};
      }
    }
    if (value is Map) {
      return value.keys.map((k) => k.toString()).toSet();
    }
    if (value is List) {
      return value.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  String _fieldCategory(String field) {
    if (_safeFields.contains(field)) return 'safe';
    if (_conditionalFields.contains(field)) return 'conditional';
    if (_criticalFields.contains(field)) return 'critical';
    return 'normal';
  }

  bool _isAutoMergeSafe(Set<String> fields) {
    for (final field in fields) {
      final category = _fieldCategory(field);
      if (category == 'critical' || category == 'normal') {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _mergeRecords(
    Map<String, dynamic> serverRecord,
    Map<String, dynamic> localRecord,
    Set<String> localChangedFields,
  ) {
    final merged = Map<String, dynamic>.from(serverRecord);
    for (final field in localChangedFields) {
      if (field == 'changed_fields') continue;
      if (!localRecord.containsKey(field)) continue;
      merged[field] = localRecord[field];
    }
    merged['lastModified'] = DateTime.now().millisecondsSinceEpoch;
    merged['changed_fields'] = jsonEncode(
      {
        for (final field in localChangedFields)
          if (field != 'changed_fields') field: localRecord[field],
      },
    );
    return merged;
  }

  Future<Map<String, dynamic>?> _fetchServerRecord(
    String collection,
    String docId,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .get();
      if (doc.exists) {
        final data = _convertFirestoreData(doc.data() as Map<String, dynamic>);
        data['id'] = doc.id;
        return data;
      }
    } catch (e) {
      print('Error fetching server record: $e');
    }
    return null;
  }

  Future<void> _uploadSingleRecord(
    String table,
    String collection,
    Map<String, dynamic> record,
  ) async {
    try {
      final recordCopy = Map<String, dynamic>.from(record);
      recordCopy.remove('syncStatus');
      if (!recordCopy.containsKey('id')) {
        print('Record missing id, skipping: $recordCopy');
        return;
      }
      recordCopy['lastModified'] = Timestamp.fromMillisecondsSinceEpoch(
        _extractLastModified(record['lastModified']),
      );
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(recordCopy['id'])
          .set(recordCopy, SetOptions(merge: true));
      await _dbHelper.markAsSynced(table, record['id']);
      print('Uploaded $table/${record['id']}');
    } catch (e) {
      print('Error uploading $table record ${record['id']}: $e');
    }
  }

  int _extractLastModified(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<void> _detectAndHandleConflict(
    String table,
    String collection,
    Map<String, dynamic> localRecord,
  ) async {
    final serverRecord = await _fetchServerRecord(
      collection,
      localRecord['id'],
    );
    if (serverRecord != null) {
      final localLastModified = _extractLastModified(
        localRecord['lastModified'],
      );
      final serverLastModified = _extractLastModified(
        serverRecord['lastModified'],
      );
      final localChangedFields = _decodeChangedFields(localRecord['changed_fields']);
      final serverChangedFields = _decodeChangedFields(serverRecord['changed_fields']);
      final overlappingFields = <String>{
        for (final field in localChangedFields)
          if (serverChangedFields.contains(field) &&
              _fieldCategory(field) != 'safe')
            field,
      };

      if (serverLastModified <= localLastModified) {
        await _uploadSingleRecord(table, collection, localRecord);
        return;
      }

      if (overlappingFields.isEmpty || _isAutoMergeSafe(overlappingFields)) {
        final merged = _mergeRecords(
          serverRecord,
          localRecord,
          localChangedFields,
        );
        await _dbHelper.update(
          table,
          merged,
          markSynced: true,
          changedFields: <String, dynamic>{},
        );
        await _uploadSingleRecord(table, collection, merged);
        return;
      }

      final conflictId = '${localRecord['id']}_$table';
      final conflict = {
        'id': conflictId,
        'tableName': table,
        'recordId': localRecord['id'],
        'localData': jsonEncode(localRecord),
        'serverData': jsonEncode(serverRecord),
        'conflictingFields': jsonEncode(overlappingFields.toList()),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await _dbHelper.insertConflict(conflict);
      print('Conflict detected for $table/${localRecord['id']}');
    } else {
      await _uploadSingleRecord(table, collection, localRecord);
    }
  }

  Future<void> _uploadPending() async {
    for (final entry in _collectionMap.entries) {
      final table = entry.key;
      final collection = entry.value;
      final pending = await _dbHelper.getPendingRecords(table);
      if (pending.isNotEmpty) {
        print('Found ${pending.length} pending in $table');
      }
      for (final record in pending) {
        await _detectAndHandleConflict(table, collection, record);
      }
    }
  }

  Future<void> _uploadDeletions() async {
    final db = await _dbHelper.database;
    final deletions = await db.query('pending_deletions');
    if (deletions.isNotEmpty) {
      print('Found ${deletions.length} pending deletions');
    }
    for (final del in deletions) {
      final table = del['tableName'] as String;
      final recordId = del['recordId'] as String;
      final collection = _collectionMap[table];
      if (collection != null) {
        try {
          await FirebaseFirestore.instance
              .collection(collection)
              .doc(recordId)
              .delete();
          await db.delete(
            'pending_deletions',
            where: 'id = ?',
            whereArgs: [del['id']],
          );
          print('Deleted $collection/$recordId');
        } catch (e) {
          print('Error deleting $collection/$recordId: $e');
        }
      }
    }
  }

  Future<void> _downloadChanges() async {
    for (final entry in _collectionMap.entries) {
      final table = entry.key;
      final collection = entry.value;
      final lastSync = await _dbHelper.getLastSync(collection);
      Query query = FirebaseFirestore.instance.collection(collection);
      if (lastSync != null) {
        query = query.where(
          'lastModified',
          isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastSync),
        );
      }
      try {
        final snapshot = await query.get();
        if (snapshot.docs.isNotEmpty) {
          print('Downloading ${snapshot.docs.length} from $collection');
        }
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final convertedData = _convertFirestoreData(data);
          convertedData['id'] = doc.id;
          convertedData['syncStatus'] = 'synced';
          convertedData['lastModified'] = DateTime.now().millisecondsSinceEpoch;
          await _dbHelper.insert(
            table,
            _normalizeForLocalWrite(table, convertedData),
            markSynced: true,
          );
        }
        await _dbHelper.setLastSync(
          collection,
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (e) {
        print('Error downloading $collection: $e');
      }
    }
  }

  Future<void> markPending(String table, String id) async {
    final db = await _dbHelper.database;
    await db.update(
      table,
      {'syncStatus': 'pending'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> resolveConflict(
    String conflictId,
    String resolution, [
    Map<String, dynamic>? mergedData,
  ]) async {
    final conflict = await _dbHelper.queryById('conflicts', conflictId);
    if (conflict == null) return;
    final table = conflict['tableName'];
    final localData = jsonDecode(conflict['localData']);
    final serverData = jsonDecode(conflict['serverData']);

    if (resolution == 'local') {
      await _uploadSingleRecord(table, _collectionMap[table]!, localData);
    } else if (resolution == 'server') {
      serverData['syncStatus'] = 'synced';
      serverData['lastModified'] = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.update(
        table,
        serverData,
        markSynced: true,
        changedFields: <String, dynamic>{},
      );
    } else if (resolution == 'merge' && mergedData != null) {
      mergedData['syncStatus'] = 'synced';
      mergedData['lastModified'] = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.update(
        table,
        mergedData,
        markSynced: true,
        changedFields: <String, dynamic>{},
      );
      await _uploadSingleRecord(table, _collectionMap[table]!, mergedData);
    }
    await _dbHelper.deleteConflict(conflictId);
    print('Conflict $conflictId resolved with $resolution');
    await syncAll();
  }

  void dispose() {
    _dataChangedController.close();
  }
}
