import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final _dataChangedController = StreamController<bool>.broadcast();
  Stream<bool> get dataChangedStream => _dataChangedController.stream;

  // Map table names to Firestore collection names
  final Map<String, String> _collectionMap = {
    'users': 'users',
    'orders': 'orders',
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
    'order_assignments': 'order_assignments',
    'measurement_types': 'measurement_types',
    'measurements': 'measurements',
  };

  Stream<bool> get onlineStream => Connectivity().onConnectivityChanged.map((status) => status != ConnectivityResult.none);

  Future<bool> isOnline() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> syncAll() async {
    if (!await isOnline()) return;

    await _uploadPending();
    await _downloadChanges();
    _dataChangedController.add(true);
  }

  Future<Map<String, dynamic>?> _fetchServerRecord(String collection, String docId) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection(collection).doc(docId).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }
    } catch (e) {
      print('Error fetching server record: $e');
    }
    return null;
  }

  Future<void> _uploadSingleRecord(String table, String collection, Map<String, dynamic> record) async {
    try {
      // Remove local-only fields before sending
      record.remove('syncStatus');
      record.remove('lastModified');
      // Ensure id is present
      if (!record.containsKey('id')) {
        print('Record missing id, skipping: $record');
        return;
      }
      await FirebaseFirestore.instance.collection(collection).doc(record['id']).set(record, SetOptions(merge: true));
      await _dbHelper.markAsSynced(table, record['id']);
    } catch (e) {
      print('Error uploading $table record ${record['id']}: $e');
    }
  }

  Future<void> _detectAndHandleConflict(String table, String collection, Map<String, dynamic> localRecord) async {
    var serverRecord = await _fetchServerRecord(collection, localRecord['id']);
    if (serverRecord != null) {
      // Conflict detected
      String conflictId = '${localRecord['id']}_$table';
      Map<String, dynamic> conflict = {
        'id': conflictId,
        'tableName': table,
        'recordId': localRecord['id'],
        'localData': jsonEncode(localRecord),
        'serverData': jsonEncode(serverRecord),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await _dbHelper.insertConflict(conflict);
    } else {
      // No server record, safe to upload
      await _uploadSingleRecord(table, collection, localRecord);
    }
  }

  Future<void> _uploadPending() async {
    for (var entry in _collectionMap.entries) {
      String table = entry.key;
      String collection = entry.value;
      List<Map<String, dynamic>> pending = await _dbHelper.getPendingRecords(table);
      for (var record in pending) {
        await _detectAndHandleConflict(table, collection, record);
      }
    }
  }

  Future<void> _downloadChanges() async {
    for (var entry in _collectionMap.entries) {
      String table = entry.key;
      String collection = entry.value;
      int? lastSync = await _dbHelper.getLastSync(collection);
      Query query = FirebaseFirestore.instance.collection(collection);
      if (lastSync != null) {
        query = query.where('lastModified', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastSync));
      }
      try {
        QuerySnapshot snapshot = await query.get();
        for (var doc in snapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          data['syncStatus'] = 'synced';
          data['lastModified'] = DateTime.now().millisecondsSinceEpoch;
          await _dbHelper.insert(table, data, markSynced: true);
        }
        await _dbHelper.setLastSync(collection, DateTime.now().millisecondsSinceEpoch);
      } catch (e) {
        print('Error downloading $collection: $e');
      }
    }
  }

  Future<void> markPending(String table, String id) async {
    Database db = await _dbHelper.database;
    await db.update(table, {'syncStatus': 'pending'}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resolveConflict(String conflictId, String resolution, [Map<String, dynamic>? mergedData]) async {
    var conflict = await _dbHelper.queryById('conflicts', conflictId);
    if (conflict == null) return;
    String table = conflict['tableName'];
    String recordId = conflict['recordId'];
    Map<String, dynamic> localData = jsonDecode(conflict['localData']);
    Map<String, dynamic> serverData = jsonDecode(conflict['serverData']);

    if (resolution == 'local') {
      // Upload local version
      await _uploadSingleRecord(table, _collectionMap[table]!, localData);
    } else if (resolution == 'server') {
      // Overwrite local with server
      serverData['syncStatus'] = 'synced';
      serverData['lastModified'] = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.update(table, serverData);
    } else if (resolution == 'merge' && mergedData != null) {
      // Save merged data locally and upload
      mergedData['syncStatus'] = 'synced';
      mergedData['lastModified'] = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.update(table, mergedData);
      await _uploadSingleRecord(table, _collectionMap[table]!, mergedData);
    }
    // Delete conflict after resolution
    await _dbHelper.deleteConflict(conflictId);
    // Trigger sync to ensure everything is consistent
    await syncAll();
  }

  void dispose() {
    _dataChangedController.close();
  }
}