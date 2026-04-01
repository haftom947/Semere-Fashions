import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const List<String> _syncTrackedTables = [
    'users',
    'orders',
    'material_usage',
    'products',
    'materials',
    'equipment',
    'customers',
    'branches',
    'suppliers',
    'properties',
    'tenants',
    'rent_payments',
    'rent_dues',
    'social_accounts',
    'social_metrics',
    'purchase_orders',
    'purchase_order_items',
    'fuel_logs',
    'maintenance_logs',
    'checkout_logs',
    'commissions',
    'accounts',
    'transactions',
    'payment_transaction',
    'payment_breakdown',
    'order_assignments',
    'measurement_types',
    'measurements',
    'production_orders',
    'employee_payments',
    'leave_requests',
  ];
  static const Set<String> _excludedChangedFields = {
    'syncStatus',
    'lastModified',
    'changed_fields',
    'paid_amount',
  };

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'semere_fashions.db');
    return await openDatabase(
      path,
      version: 27,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _ensureChangedFieldsColumns(Database db) async {
    for (final table in _syncTrackedTables) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN changed_fields TEXT');
      } catch (_) {
        // Column or table may already exist on upgraded installs.
      }
    }
  }

  Future<void> _ensureConflictColumns(Database db) async {
    try {
      await db.execute('ALTER TABLE conflicts ADD COLUMN conflictingFields TEXT');
    } catch (_) {
      // Existing installs may already have this column.
    }
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 24) {
      await db.execute('ALTER TABLE materials ADD COLUMN cost_per_unit REAL DEFAULT 0');
      await db.execute('''
        CREATE TABLE material_usage(
          id TEXT PRIMARY KEY,
          material_id TEXT,
          quantity REAL,
          cost REAL,
          date INTEGER,
          notes TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    if (oldVersion < 25) {
      await db.execute(
        'ALTER TABLE payment_transaction ADD COLUMN tip_amount REAL DEFAULT 0',
      );
    }
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE measurement_types(
          id TEXT PRIMARY KEY,
          name TEXT,
          unit TEXT,
          sortOrder INTEGER,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE measurements(
          id TEXT PRIMARY KEY,
          customer_id TEXT,
          measurement_type_id TEXT,
          date_taken INTEGER,
          value REAL,
          notes TEXT,
          order_id TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    // In database_helper.dart
    if (oldVersion < 23) {
      await db.execute('ALTER TABLE orders ADD COLUMN cogs REAL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE accounts(
          id TEXT PRIMARY KEY,
          name TEXT,
          type TEXT,
          opening_balance REAL,
          current_balance REAL,
          notes TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE transactions(
          id TEXT PRIMARY KEY,
          account_id TEXT,
          date INTEGER,
          amount REAL,
          type TEXT,
          category TEXT,
          reference_id TEXT,
          description TEXT,
          status TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE orders ADD COLUMN delivery_fee REAL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE users ADD COLUMN delivery_commission_type TEXT',
      );
      await db.execute(
        'ALTER TABLE users ADD COLUMN delivery_commission_value REAL DEFAULT 0',
      );
      await db.execute('''
        CREATE TABLE order_assignments(
          id TEXT PRIMARY KEY,
          orderId TEXT,
          employeeId TEXT,
          employeeName TEXT,
          role TEXT,
          assignedAt INTEGER,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE orders ADD COLUMN discount_type TEXT');
      await db.execute(
        'ALTER TABLE orders ADD COLUMN discount_value REAL DEFAULT 0',
      );
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE production_orders(
          id TEXT PRIMARY KEY,
          productName TEXT,
          tailorId TEXT,
          tailorName TEXT,
          materialsUsed TEXT,
          totalMaterialCost REAL,
          tailorCommission REAL,
          totalCost REAL,
          sellingPrice REAL DEFAULT 0,
          status TEXT,
          createdAt INTEGER,
          completedAt INTEGER,
          notes TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
      await db.execute(
        'ALTER TABLE products ADD COLUMN productionOrderId TEXT',
      );
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE order_assignments ADD COLUMN commission_amount REAL DEFAULT 0',
      );
    }
    if (oldVersion < 8) {
      await db.execute(
        'ALTER TABLE equipment ADD COLUMN registration_expiry INTEGER',
      );
      await db.execute(
        'ALTER TABLE equipment ADD COLUMN insurance_policy TEXT',
      );
      await db.execute(
        'ALTER TABLE equipment ADD COLUMN insurance_expiry INTEGER',
      );
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE supplier_materials(
          id TEXT PRIMARY KEY,
          supplierId TEXT,
          materialId TEXT,
          notes TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE employee_payments(
          id TEXT PRIMARY KEY,
          employeeId TEXT,
          employeeName TEXT,
          type TEXT,
          amount REAL,
          month TEXT,
          datePaid INTEGER,
          notes TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE leave_requests(
          id TEXT PRIMARY KEY,
          employeeId TEXT,
          employeeName TEXT,
          startDate INTEGER,
          endDate INTEGER,
          reason TEXT,
          status TEXT DEFAULT 'pending',
          approvedBy TEXT,
          approvedAt INTEGER,
          notes TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    if (oldVersion < 12) {
      await db.execute(
        'ALTER TABLE branches ADD COLUMN currency TEXT DEFAULT "ETB"',
      );
    }
    if (oldVersion < 13) {
      await db.execute('ALTER TABLE orders ADD COLUMN currency TEXT');
    }
    if (oldVersion < 14) {
      await db.execute('ALTER TABLE users ADD COLUMN fcmToken TEXT');
    }
    if (oldVersion < 15) {
      await db.execute('ALTER TABLE materials ADD COLUMN createdAt INTEGER');
      await db.execute('ALTER TABLE products ADD COLUMN createdAt INTEGER');
    }
    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE pending_deletions(
          id TEXT PRIMARY KEY,
          tableName TEXT,
          recordId TEXT,
          timestamp INTEGER
        )
      ''');
    }
    if (oldVersion < 17) {
      await db.execute('ALTER TABLE orders ADD COLUMN tracking_number TEXT');
      await db.execute('ALTER TABLE orders ADD COLUMN courier_name TEXT');
    }
    if (oldVersion < 18) {
      await db.execute('ALTER TABLE orders ADD COLUMN salesPersonId TEXT');
    }
    if (oldVersion < 19) {
      await db.execute('''
        CREATE TABLE payment_transaction(
          id TEXT PRIMARY KEY,
          orderId TEXT,
          branchId TEXT,
          receivedBy TEXT,
          date INTEGER,
          type TEXT,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE payment_breakdown(
          id TEXT PRIMARY KEY,
          payment_transaction_id TEXT,
          method TEXT,
          amount REAL,
          syncStatus TEXT DEFAULT 'synced',
          lastModified INTEGER
        )
      ''');
    }
    if (oldVersion < 20) {
      await db.execute(
        'ALTER TABLE orders ADD COLUMN stock_deducted INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 21) {
      await db.execute(
        'ALTER TABLE orders ADD COLUMN paid_amount REAL DEFAULT 0',
      );
    }
    if (oldVersion < 22) {
      await db.execute(
        'ALTER TABLE payment_transaction ADD COLUMN amount REAL DEFAULT 0',
      );
    }
    if (oldVersion < 26) {
      await _ensureChangedFieldsColumns(db);
      await _ensureConflictColumns(db);
    }
    if (oldVersion < 27) {
      await _ensureConflictColumns(db);
      await db.execute(
        'ALTER TABLE users ADD COLUMN device_id TEXT',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS dashboard_cache (
          key TEXT PRIMARY KEY,
          value TEXT,
          lastUpdated INTEGER
        )
      ''');
    }
  }

  Future _onCreate(Database db, int version) async {
    // Users table
    
    await db.execute('''
      CREATE TABLE users(
        id TEXT PRIMARY KEY,
        name TEXT,
        phone TEXT,
        role TEXT,
        branchId TEXT,
        employmentType TEXT,
        status TEXT,
        commissionRate REAL,
        tailorCut REAL,
        delivery_commission_type TEXT,
        delivery_commission_value REAL DEFAULT 0,
        createdAt INTEGER,
        fcmToken TEXT,
        device_id TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Branches table
    await db.execute('''
      CREATE TABLE branches(
        id TEXT PRIMARY KEY,
        name TEXT,
        location TEXT,
        phone TEXT,
        email TEXT,
        currency TEXT DEFAULT 'ETB',
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Orders table (with all fields, no comments)
    await db.execute('''
      CREATE TABLE orders(
        id TEXT PRIMARY KEY,
        customerId TEXT,
        customerName TEXT,
        items TEXT,
        totalAmount REAL,
        delivery_fee REAL DEFAULT 0,
        discount_type TEXT,
        discount_value REAL DEFAULT 0,
        status TEXT,
        createdAt INTEGER,
        createdBy TEXT,
        branchId TEXT,
        tailorId TEXT,
        currency TEXT,
        tracking_number TEXT,
        courier_name TEXT,
        salesPersonId TEXT,
        stock_deducted INTEGER DEFAULT 0,
        paid_amount REAL DEFAULT 0,
        cogs REAL DEFAULT 0,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Order assignments table
    await db.execute('''
      CREATE TABLE order_assignments(
        id TEXT PRIMARY KEY,
        orderId TEXT,
        employeeId TEXT,
        employeeName TEXT,
        role TEXT,
        assignedAt INTEGER,
        commission_amount REAL DEFAULT 0,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Products table
    await db.execute('''
      CREATE TABLE products(
        id TEXT PRIMARY KEY,
        name TEXT,
        category TEXT,
        costPrice REAL,
        sellingPrice REAL,
        stock INTEGER,
        minimumLevel INTEGER,
        productionOrderId TEXT,
        createdAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Materials table
    await db.execute('''
      CREATE TABLE materials(
        id TEXT PRIMARY KEY,
        name TEXT,
        category TEXT,
        unit TEXT,
        cost_per_unit REAL DEFAULT 0,
        stock INTEGER,
        minimumLevel INTEGER,
        createdAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Equipment table
    await db.execute('''
      CREATE TABLE equipment(
        id TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        status TEXT,
        serialNumber TEXT,
        make TEXT,
        model TEXT,
        year INTEGER,
        licensePlate TEXT,
        color TEXT,
        registration_expiry INTEGER,
        insurance_policy TEXT,
        insurance_expiry INTEGER,
        assignedTo TEXT,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Customers table
    await db.execute('''
      CREATE TABLE customers(
        id TEXT PRIMARY KEY,
        name TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        createdAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Suppliers table
    await db.execute('''
      CREATE TABLE suppliers(
        id TEXT PRIMARY KEY,
        name TEXT,
        phone TEXT,
        createdAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Supplier materials junction table
    await db.execute('''
      CREATE TABLE supplier_materials(
        id TEXT PRIMARY KEY,
        supplierId TEXT,
        materialId TEXT,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Properties table
    await db.execute('''
      CREATE TABLE properties(
        id TEXT PRIMARY KEY,
        name TEXT,
        address TEXT,
        type TEXT,
        ownership TEXT,
        status TEXT DEFAULT 'vacant',
        monthlyRent REAL,
        landlordName TEXT,
        landlordPhone TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Tenants table
    await db.execute('''
      CREATE TABLE tenants(
        id TEXT PRIMARY KEY,
        propertyId TEXT,
        name TEXT,
        phone TEXT,
        monthlyRent REAL,
        createdAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Rent payments table
    await db.execute('''
      CREATE TABLE rent_payments(
        id TEXT PRIMARY KEY,
        tenantId TEXT,
        tenantName TEXT,
        amount REAL,
        month TEXT,
        paidAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Rent dues table
    await db.execute('''
      CREATE TABLE rent_dues(
        id TEXT PRIMARY KEY,
        tenantId TEXT,
        tenantName TEXT,
        propertyId TEXT,
        amount REAL,
        dueMonth TEXT,
        dueDate INTEGER,
        status TEXT,
        createdAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Social accounts table
    await db.execute('''
      CREATE TABLE social_accounts(
        id TEXT PRIMARY KEY,
        platform TEXT,
        accountName TEXT,
        accountUrl TEXT,
        employeeId TEXT,
        employeeName TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Social metrics table
    await db.execute('''
      CREATE TABLE social_metrics(
        id TEXT PRIMARY KEY,
        accountId TEXT,
        date INTEGER,
        followers INTEGER,
        posts INTEGER,
        likes INTEGER,
        comments INTEGER,
        shares INTEGER,
        views INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Purchase orders table
    await db.execute('''
      CREATE TABLE purchase_orders(
        id TEXT PRIMARY KEY,
        supplierId TEXT,
        supplierName TEXT,
        orderDate INTEGER,
        expectedDate INTEGER,
        status TEXT,
        notes TEXT,
        totalAmount REAL,
        createdAt INTEGER,
        createdBy TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Purchase order items table
    await db.execute('''
      CREATE TABLE purchase_order_items(
        id TEXT PRIMARY KEY,
        poId TEXT,
        itemType TEXT,
        itemId TEXT,
        itemName TEXT,
        quantity INTEGER,
        unitPrice REAL,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Fuel logs table
    await db.execute('''
      CREATE TABLE fuel_logs(
        id TEXT PRIMARY KEY,
        vehicleId TEXT,
        date INTEGER,
        odometer INTEGER,
        liters REAL,
        cost REAL,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Maintenance logs table
    await db.execute('''
      CREATE TABLE maintenance_logs(
        id TEXT PRIMARY KEY,
        vehicleId TEXT,
        date INTEGER,
        type TEXT,
        description TEXT,
        cost REAL,
        odometer INTEGER,
        nextDue INTEGER,
        completed BOOLEAN,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Checkout logs table
    await db.execute('''
      CREATE TABLE checkout_logs(
        id TEXT PRIMARY KEY,
        equipmentId TEXT,
        equipmentName TEXT,
        employeeId TEXT,
        employeeName TEXT,
        checkoutDate INTEGER,
        expectedReturnDate INTEGER,
        actualReturnDate INTEGER,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Commissions table
    await db.execute('''
      CREATE TABLE commissions(
        id TEXT PRIMARY KEY,
        orderId TEXT,
        employeeId TEXT,
        employeeName TEXT,
        amount REAL,
        type TEXT,
        status TEXT DEFAULT 'pending',
        createdAt INTEGER,
        paidAt INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Conflicts table
    await db.execute('''
      CREATE TABLE conflicts(
        id TEXT PRIMARY KEY,
        tableName TEXT,
        recordId TEXT,
        localData TEXT,
        serverData TEXT,
        conflictingFields TEXT,
        timestamp INTEGER
      )
    ''');

    // Last sync table
    await db.execute('''
      CREATE TABLE last_sync(
        collection TEXT PRIMARY KEY,
        timestamp INTEGER
      )
    ''');

    // Measurement types table
    await db.execute('''
      CREATE TABLE measurement_types(
        id TEXT PRIMARY KEY,
        name TEXT,
        unit TEXT,
        sortOrder INTEGER,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Measurements table
    await db.execute('''
      CREATE TABLE measurements(
        id TEXT PRIMARY KEY,
        customer_id TEXT,
        measurement_type_id TEXT,
        date_taken INTEGER,
        value REAL,
        notes TEXT,
        order_id TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Accounts table
    await db.execute('''
      CREATE TABLE accounts(
        id TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        opening_balance REAL,
        current_balance REAL,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Transactions table
    await db.execute('''
      CREATE TABLE transactions(
        id TEXT PRIMARY KEY,
        account_id TEXT,
        date INTEGER,
        amount REAL,
        type TEXT,
        category TEXT,
        reference_id TEXT,
        description TEXT,
        status TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Production orders table
    await db.execute('''
      CREATE TABLE production_orders(
        id TEXT PRIMARY KEY,
        productName TEXT,
        tailorId TEXT,
        tailorName TEXT,
        materialsUsed TEXT,
        totalMaterialCost REAL,
        tailorCommission REAL,
        totalCost REAL,
        sellingPrice REAL DEFAULT 0,
        status TEXT,
        createdAt INTEGER,
        completedAt INTEGER,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Employee payments table
    await db.execute('''
      CREATE TABLE employee_payments(
        id TEXT PRIMARY KEY,
        employeeId TEXT,
        employeeName TEXT,
        type TEXT,
        amount REAL,
        month TEXT,
        datePaid INTEGER,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Leave requests table
    await db.execute('''
      CREATE TABLE leave_requests(
        id TEXT PRIMARY KEY,
        employeeId TEXT,
        employeeName TEXT,
        startDate INTEGER,
        endDate INTEGER,
        reason TEXT,
        status TEXT DEFAULT 'pending',
        approvedBy TEXT,
        approvedAt INTEGER,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Pending deletions table
    await db.execute('''
      CREATE TABLE pending_deletions(
        id TEXT PRIMARY KEY,
        tableName TEXT,
        recordId TEXT,
        timestamp INTEGER
      )
    ''');

    // Payment transaction table
    await db.execute('''
      CREATE TABLE payment_transaction(
        id TEXT PRIMARY KEY,
        orderId TEXT,
        branchId TEXT,
        receivedBy TEXT,
        date INTEGER,
        type TEXT,
        amount REAL DEFAULT 0,
        tip_amount REAL DEFAULT 0,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Payment breakdown table
    await db.execute('''
      CREATE TABLE payment_breakdown(
        id TEXT PRIMARY KEY,
        payment_transaction_id TEXT,
        method TEXT,
        amount REAL,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE material_usage(
        id TEXT PRIMARY KEY,
        material_id TEXT,
        quantity REAL,
        cost REAL,
        date INTEGER,
        notes TEXT,
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dashboard_cache (
        key TEXT PRIMARY KEY,
        value TEXT,
        lastUpdated INTEGER
      )
    ''');

    await _ensureChangedFieldsColumns(db);
    await _ensureConflictColumns(db);
  }

  // ========== CRUD METHODS ==========
  Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(data);
  }

  Map<String, dynamic> _trackedFieldDiff(
    Map<String, dynamic> previous,
    Map<String, dynamic> next, {
    Set<String> exclude = const {},
  }) {
    final diff = <String, dynamic>{};
    final keys = {...previous.keys, ...next.keys};
    for (final key in keys) {
      if (_excludedChangedFields.contains(key) || exclude.contains(key)) {
        continue;
      }
      final previousValue = previous[key];
      final nextValue = next[key];
      if (previousValue != nextValue) {
        diff[key] = nextValue;
      }
    }
    return diff;
  }

  Future<Map<String, dynamic>?> _rowForUpdate(String table, dynamic id) async {
    if (id == null) return null;
    return await queryById(table, id.toString());
  }

  Future<Map<String, dynamic>?> _rowForInsert(String table, dynamic id) async {
    if (id == null) return null;
    return await queryById(table, id.toString());
  }

  Map<String, dynamic> _withWriteMetadata(
    Map<String, dynamic> data, {
    required bool markSynced,
    Map<String, dynamic>? changedFields,
  }) {
    final payload = _jsonSafeMap(data);
    payload['syncStatus'] = markSynced ? 'synced' : 'pending';
    payload['lastModified'] = DateTime.now().millisecondsSinceEpoch;
    if (changedFields != null) {
      payload['changed_fields'] = jsonEncode(changedFields);
    } else if (!payload.containsKey('changed_fields') &&
        payload.isNotEmpty &&
        payload['id'] != null) {
      final autoChanged = _trackedFieldDiff(const {}, payload);
      payload['changed_fields'] = jsonEncode(autoChanged);
    }
    return payload;
  }

  Future<void> insert(
    String table,
    Map<String, dynamic> data, {
    bool markSynced = false,
    Map<String, dynamic>? changedFields,
  }) async {
    Database db = await database;
    final payload = _withWriteMetadata(
      data,
      markSynced: markSynced,
      changedFields: changedFields,
    );
    await db.insert(table, payload, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(
    String table,
    Map<String, dynamic> data, {
    bool markSynced = false,
    Map<String, dynamic>? changedFields,
  }) async {
    Database db = await database;
    final current = await _rowForUpdate(table, data['id']);
    final merged = current == null
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{...current, ...data};
    final payload = _withWriteMetadata(
      merged,
      markSynced: markSynced,
      changedFields: changedFields ??
          (current == null
              ? _trackedFieldDiff(const {}, merged)
              : _trackedFieldDiff(current, merged)),
    );
    await db.update(table, payload, where: 'id = ?', whereArgs: [data['id']]);
  }

  Future<void> delete(String table, String id) async {
    Database db = await database;
    // Insert into pending_deletions
    await db.insert('pending_deletions', {
      'id': '${table}_$id',
      'tableName': table,
      'recordId': id,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // Remove from main table
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> query(String table) async {
    Database db = await database;
    final results = await db.query(table);
    if (table == 'orders') {
      return await _applyComputedPaidAmount(results);
    }
    return results;
  }

  Future<Map<String, dynamic>?> queryById(String table, String id) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    if (table == 'orders') {
      final computed = await _applyComputedPaidAmount([results.first]);
      return computed.isNotEmpty ? computed.first : results.first;
    }
    return results.first;
  }

  Future<List<Map<String, dynamic>>> queryWhere(
    String table,
    String whereClause,
    List<dynamic> whereArgs,
  ) async {
    Database db = await database;
    final results = await db.query(table, where: whereClause, whereArgs: whereArgs);
    if (table == 'orders') {
      return await _applyComputedPaidAmount(results);
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> _applyComputedPaidAmount(
    List<Map<String, dynamic>> orders,
  ) async {
    if (orders.isEmpty) return orders;
    final payments = await query('payment_transaction');
    final paymentTotals = <String, double>{};
    for (final payment in payments) {
      final orderId = payment['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) continue;
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      final type = payment['type']?.toString();
      if (type == 'refund') {
        paymentTotals[orderId] = (paymentTotals[orderId] ?? 0.0) - amount;
      } else {
        paymentTotals[orderId] = (paymentTotals[orderId] ?? 0.0) + amount;
      }
    }

    return orders.map((order) {
      final orderCopy = Map<String, dynamic>.from(order);
      final orderId = orderCopy['id']?.toString();
      final totalAmount = (orderCopy['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final computedPaid = orderId == null ? 0.0 : (paymentTotals[orderId] ?? 0.0);
      orderCopy['paid_amount'] = computedPaid.clamp(0.0, totalAmount);
      return orderCopy;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingRecords(String table) async {
    Database db = await database;
    return await db.query(
      table,
      where: 'syncStatus = ?',
      whereArgs: ['pending'],
    );
  }

  Future<void> markAsSynced(String table, String id) async {
    Database db = await database;
    await db.update(
      table,
      {'syncStatus': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ========== CONFLICT METHODS ==========
  Future<void> insertConflict(Map<String, dynamic> conflict) async {
    Database db = await database;
    await db.insert(
      'conflicts',
      conflict,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getConflicts() async {
    Database db = await database;
    return await db.query('conflicts', orderBy: 'timestamp DESC');
  }

  Future<void> deleteConflict(String id) async {
    Database db = await database;
    await db.delete('conflicts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearConflicts() async {
    Database db = await database;
    await db.delete('conflicts');
  }

  Future<void> saveCache(String key, Map<String, dynamic> data) async {
    Database db = await database;
    await db.insert(
      'dashboard_cache',
      {
        'key': key,
        'value': jsonEncode(data),
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadCache(String key) async {
    Database db = await database;
    final res = await db.query(
      'dashboard_cache',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (res.isEmpty) return null;
    final value = res.first['value'];
    if (value is! String || value.isEmpty) return null;
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  // ========== LAST SYNC METHODS ==========
  Future<int?> getLastSync(String collection) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      'last_sync',
      where: 'collection = ?',
      whereArgs: [collection],
    );
    return results.isNotEmpty ? results.first['timestamp'] as int? : null;
  }

  Future<void> setLastSync(String collection, int timestamp) async {
    Database db = await database;
    await db.insert('last_sync', {
      'collection': collection,
      'timestamp': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========== BATCH OPERATIONS ==========
  Future<void> insertBatch(
    String table,
    List<Map<String, dynamic>> dataList,
  ) async {
    Database db = await database;
    await db.transaction((txn) async {
      for (var data in dataList) {
        final payload = _withWriteMetadata(
          data,
          markSynced: false,
        );
        await txn.insert(
          table,
          payload,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ========== METHOD FOR LAST SYNC TIMESTAMP ==========
  Future<int?> getLatestSyncTime() async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      'last_sync',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first['timestamp'] as int? : null;
  }

  // ========== PENDING DELETIONS (optional direct access) ==========
  Future<List<Map<String, dynamic>>> getPendingDeletions() async {
    Database db = await database;
    return await db.query('pending_deletions');
  }

  Future<void> clearPendingDeletion(String id) async {
    Database db = await database;
    await db.delete('pending_deletions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addPayment(
    String orderId,
    double amount,
    String method, {
    String type = 'payment',
    String? branchId,
    String? receivedBy,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero');
    }

    final order = await queryById('orders', orderId);
    if (order == null) {
      throw Exception('Order not found');
    }

    final currentPaid = (order['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final orderTotal = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;

    double newPaid = currentPaid + amount;
    double tipAmount = 0.0;
    if (type == 'refund') {
      if (amount > currentPaid) {
        throw Exception('Refund cannot exceed paid amount');
      }
      newPaid = currentPaid - amount;
    } else if (newPaid > orderTotal) {
      tipAmount = newPaid - orderTotal;
      newPaid = orderTotal;
    }

    final transactionId = DateTime.now().millisecondsSinceEpoch.toString();
    await insert('payment_transaction', {
      'id': transactionId,
      'orderId': orderId,
      'branchId': branchId ?? order['branchId'],
      'receivedBy': receivedBy,
      'date': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'amount': amount,
      'tip_amount': tipAmount,
    });
    await insert('payment_breakdown', {
      'id': '${transactionId}_$method',
      'payment_transaction_id': transactionId,
      'method': method,
      'amount': amount,
    });
    await update('orders', {'id': orderId, 'paid_amount': newPaid});
  }

  Future<List<Map<String, dynamic>>> getPaymentsForOrder(String orderId) async {
    final payments = List<Map<String, dynamic>>.from(
      await queryWhere('payment_transaction', 'orderId = ?', [orderId]),
    );
    for (final payment in payments) {
      final breakdowns = await queryWhere(
        'payment_breakdown',
        'payment_transaction_id = ?',
        [payment['id']],
      );
      if (breakdowns.isNotEmpty) {
        payment['method'] = breakdowns.first['method'];
      }
    }
    payments.sort(
      (a, b) => ((b['date'] as num?)?.toInt() ?? 0).compareTo(
        (a['date'] as num?)?.toInt() ?? 0,
      ),
    );
    return payments;
  }

  Future<void> clearPaymentsForOrder(String orderId) async {
    final db = await database;
    final payments = await getPaymentsForOrder(orderId);
    await db.transaction((txn) async {
      for (final payment in payments) {
        final breakdowns = await txn.query(
          'payment_breakdown',
          where: 'payment_transaction_id = ?',
          whereArgs: [payment['id']],
        );
        for (final breakdown in breakdowns) {
          await txn.insert('pending_deletions', {
            'id': 'payment_breakdown_${breakdown['id']}',
            'tableName': 'payment_breakdown',
            'recordId': breakdown['id'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.insert('pending_deletions', {
          'id': 'payment_transaction_${payment['id']}',
          'tableName': 'payment_transaction',
          'recordId': payment['id'],
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete(
          'payment_breakdown',
          where: 'payment_transaction_id = ?',
          whereArgs: [payment['id']],
        );
        await txn.delete(
          'payment_transaction',
          where: 'id = ?',
          whereArgs: [payment['id']],
        );
      }
      await txn.update(
        'orders',
        {
          'paid_amount': 0,
          'syncStatus': 'pending',
          'lastModified': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }
}
