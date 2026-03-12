import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

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
      version: 13, // Incremented to 13
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
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
      await db.execute('ALTER TABLE orders ADD COLUMN delivery_fee REAL DEFAULT 0');
      await db.execute('ALTER TABLE users ADD COLUMN delivery_commission_type TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN delivery_commission_value REAL DEFAULT 0');
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
      await db.execute('ALTER TABLE orders ADD COLUMN discount_value REAL DEFAULT 0');
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
      await db.execute('ALTER TABLE products ADD COLUMN productionOrderId TEXT');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE order_assignments ADD COLUMN commission_amount REAL DEFAULT 0');
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE equipment ADD COLUMN registration_expiry INTEGER');
      await db.execute('ALTER TABLE equipment ADD COLUMN insurance_policy TEXT');
      await db.execute('ALTER TABLE equipment ADD COLUMN insurance_expiry INTEGER');
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
      await db.execute('ALTER TABLE branches ADD COLUMN currency TEXT DEFAULT "ETB"');
    }
    if (oldVersion < 13) {
      await db.execute('ALTER TABLE orders ADD COLUMN currency TEXT');
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
        syncStatus TEXT DEFAULT 'synced',
        lastModified INTEGER
      )
    ''');

    // Branches table (with currency)
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

    // Orders table (with currency)
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
        stock INTEGER,
        minimumLevel INTEGER,
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
  }

  // ========== CRUD METHODS ==========
  Future<void> insert(String table, Map<String, dynamic> data, {bool markSynced = false}) async {
    Database db = await database;
    data['syncStatus'] = markSynced ? 'synced' : 'pending';
    data['lastModified'] = DateTime.now().millisecondsSinceEpoch;
    await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(String table, Map<String, dynamic> data, {bool markSynced = false}) async {
    Database db = await database;
    data['syncStatus'] = markSynced ? 'synced' : 'pending';
    data['lastModified'] = DateTime.now().millisecondsSinceEpoch;
    await db.update(table, data, where: 'id = ?', whereArgs: [data['id']]);
  }

  Future<void> delete(String table, String id) async {
    Database db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> query(String table) async {
    Database db = await database;
    return await db.query(table);
  }

  Future<Map<String, dynamic>?> queryById(String table, String id) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(table, where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> queryWhere(String table, String whereClause, List<dynamic> whereArgs) async {
    Database db = await database;
    return await db.query(table, where: whereClause, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> getPendingRecords(String table) async {
    Database db = await database;
    return await db.query(table, where: 'syncStatus = ?', whereArgs: ['pending']);
  }

  Future<void> markAsSynced(String table, String id) async {
    Database db = await database;
    await db.update(table, {'syncStatus': 'synced'}, where: 'id = ?', whereArgs: [id]);
  }

  // ========== CONFLICT METHODS ==========
  Future<void> insertConflict(Map<String, dynamic> conflict) async {
    Database db = await database;
    await db.insert('conflicts', conflict);
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

  // ========== LAST SYNC METHODS ==========
  Future<int?> getLastSync(String collection) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query('last_sync', where: 'collection = ?', whereArgs: [collection]);
    return results.isNotEmpty ? results.first['timestamp'] as int? : null;
  }

  Future<void> setLastSync(String collection, int timestamp) async {
    Database db = await database;
    await db.insert('last_sync', {'collection': collection, 'timestamp': timestamp}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========== BATCH OPERATIONS ==========
  Future<void> insertBatch(String table, List<Map<String, dynamic>> dataList) async {
    Database db = await database;
    await db.transaction((txn) async {
      for (var data in dataList) {
        data['syncStatus'] = 'pending';
        data['lastModified'] = DateTime.now().millisecondsSinceEpoch;
        await txn.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
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
}