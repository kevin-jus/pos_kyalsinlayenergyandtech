import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi_sql;

/// Local SQLite persistence for the POS.
///
/// The database is the durable source of truth. The existing JSON backup/import
/// format is intentionally preserved by storing the model JSON alongside the
/// indexed columns used by reports and queries.
class PosDatabase {
  PosDatabase._();

  static final PosDatabase instance = PosDatabase._();

  static const int _version = 1;
  static const String _fileName = 'pos_app.db';

  sql.Database? _db;

  sql.Database get database {
    final db = _db;
    if (db == null) {
      throw StateError('POS database has not been opened yet.');
    }
    return db;
  }

  Future<void> open() async {
    if (_db != null) return;

    final directory = await getApplicationSupportDirectory();
    final dbPath = '${directory.path}/$_fileName';

    // Android/iOS use the native sqflite plugin. The FFI factory is only used
    // on desktop platforms where sqflite itself does not provide a database
    // implementation. The Wi-Fi sync server/client never shares this SQLite
    // file over the network. Each device keeps its own local database so it
    // can continue operating while offline.
    sql.DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      ffi_sql.sqfliteFfiInit();
      factory = ffi_sql.databaseFactoryFfi;
    } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      factory = sql.databaseFactory;
    } else {
      factory = sql.databaseFactory;
    }

    _db = await factory.openDatabase(
      dbPath,
      options: sql.OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = OFF');
        },
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          // Keep migrations additive. Future versions can add ALTER TABLE or
          // new indexes here without destroying existing records.
        },
      ),
    );

    // Do not issue `PRAGMA journal_mode = WAL` here. Android's sqflite
    // backend treats that particular PRAGMA differently from ordinary
    // execute() statements and can report SQLITE_OK as a query-method error.
    // Android WAL is configured in the manifest when desired; SQLite also works
    // correctly without WAL, which keeps startup reliable across platforms.
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await db.close();
  }

  Future<void> _createSchema(sql.Database db) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        subtype TEXT NOT NULL,
        stock REAL NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE people (
        row_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        voucher_number TEXT PRIMARY KEY,
        date_ms INTEGER NOT NULL,
        customer TEXT NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        row_id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucher_number TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product TEXT NOT NULL,
        quantity REAL NOT NULL,
        selling_price REAL NOT NULL,
        profit REAL NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE incoming_supplies (
        id TEXT PRIMARY KEY,
        date_ms INTEGER NOT NULL,
        supplier TEXT NOT NULL,
        product TEXT NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE payment_transactions (
        id TEXT PRIMARY KEY,
        linked_type TEXT NOT NULL,
        linked_id TEXT NOT NULL,
        date_ms INTEGER NOT NULL,
        method TEXT NOT NULL,
        amount REAL NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        date_ms INTEGER NOT NULL,
        reason TEXT NOT NULL,
        amount REAL NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE income_expense (
        id TEXT PRIMARY KEY,
        date_ms INTEGER NOT NULL,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cylinder_rows (
        row_no INTEGER PRIMARY KEY,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cylinder_types (
        id TEXT PRIMARY KEY,
        base_type TEXT NOT NULL,
        name TEXT NOT NULL,
        total_quantity REAL NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cylinder_cycles (
        id TEXT PRIMARY KEY,
        cylinder_type_id TEXT NOT NULL,
        customer TEXT NOT NULL,
        date_ms INTEGER NOT NULL,
        given_quantity REAL NOT NULL,
        received_quantity REAL NOT NULL,
        data_json TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_sales_date ON sales(date_ms)');
    await db.execute('CREATE INDEX idx_sales_customer ON sales(customer)');
    await db.execute('CREATE INDEX idx_sale_items_voucher ON sale_items(voucher_number)');
    await db.execute('CREATE INDEX idx_sale_items_product ON sale_items(product_id)');
    await db.execute('CREATE INDEX idx_payments_linked ON payment_transactions(linked_type, linked_id)');
    await db.execute('CREATE INDEX idx_payments_date ON payment_transactions(date_ms)');
    await db.execute('CREATE INDEX idx_supplies_date ON incoming_supplies(date_ms)');
    await db.execute('CREATE INDEX idx_expenses_date ON expenses(date_ms)');
    await db.execute('CREATE INDEX idx_income_expense_date ON income_expense(date_ms)');
    await db.execute('CREATE INDEX idx_cylinder_cycles_date ON cylinder_cycles(date_ms)');
    await db.execute('CREATE INDEX idx_cylinder_cycles_customer ON cylinder_cycles(customer)');
  }

  int _date(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.millisecondsSinceEpoch ?? 0;
  }

  Map<String, dynamic> _jsonRow(Object? value) {
    final decoded = jsonDecode(value as String);
    if (decoded is! Map) {
      throw const FormatException('SQLite row JSON is not an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<bool> isEmpty() async {
    final result = await database.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM products) +
        (SELECT COUNT(*) FROM people) +
        (SELECT COUNT(*) FROM sales) +
        (SELECT COUNT(*) FROM incoming_supplies) +
        (SELECT COUNT(*) FROM payment_transactions) +
        (SELECT COUNT(*) FROM expenses) +
        (SELECT COUNT(*) FROM income_expense) +
        (SELECT COUNT(*) FROM cylinder_rows) +
        (SELECT COUNT(*) FROM cylinder_types) +
        (SELECT COUNT(*) FROM cylinder_cycles) AS total
    ''');
    final count = (result.first['total'] as num?)?.toInt() ?? 0;
    return count == 0;
  }

  Future<Map<String, dynamic>> readSnapshot() async {
    final result = <String, dynamic>{};

    final products = await database.query('products', orderBy: 'rowid ASC');
    final people = await database.query('people', orderBy: 'row_id ASC');
    final sales = await database.query('sales', orderBy: 'date_ms ASC, voucher_number ASC');
    final saleItems = await database.query('sale_items', orderBy: 'row_id ASC');
    final supplies = await database.query('incoming_supplies', orderBy: 'date_ms ASC, id ASC');
    final payments = await database.query('payment_transactions', orderBy: 'date_ms ASC, id ASC');
    final expenses = await database.query('expenses', orderBy: 'date_ms ASC, id ASC');
    final incomeExpense = await database.query('income_expense', orderBy: 'date_ms ASC, id ASC');
    final cylinderRows = await database.query('cylinder_rows', orderBy: 'row_no ASC');
    final cylinderTypes = await database.query('cylinder_types', orderBy: 'rowid ASC');
    final cylinderCycles = await database.query('cylinder_cycles', orderBy: 'date_ms ASC, id ASC');

    result['products'] = products.map((r) => _jsonRow(r['data_json'])).toList();
    result['people'] = people.map((r) => _jsonRow(r['data_json'])).toList();
    result['sales'] = sales.map((r) => _jsonRow(r['data_json'])).toList();
    result['saleItems'] = saleItems.map((r) => _jsonRow(r['data_json'])).toList();
    result['incomingSupplies'] = supplies.map((r) => _jsonRow(r['data_json'])).toList();
    result['paymentTransactions'] = payments.map((r) => _jsonRow(r['data_json'])).toList();
    result['expenses'] = expenses.map((r) => _jsonRow(r['data_json'])).toList();
    result['incomeExpense'] = incomeExpense.map((r) => _jsonRow(r['data_json'])).toList();
    result['cylinderRows'] = cylinderRows.map((r) => _jsonRow(r['data_json'])).toList();
    result['cylinderTypes'] = cylinderTypes.map((r) => _jsonRow(r['data_json'])).toList();
    result['cylinderCycles'] = cylinderCycles.map((r) => _jsonRow(r['data_json'])).toList();

    return result;
  }

  Future<void> replaceSnapshot(Map<String, dynamic> snapshot) async {
    await database.transaction((txn) async {
      for (final table in const [
        'products',
        'people',
        'sales',
        'sale_items',
        'incoming_supplies',
        'payment_transactions',
        'expenses',
        'income_expense',
        'cylinder_rows',
        'cylinder_types',
        'cylinder_cycles',
      ]) {
        await txn.delete(table);
      }

      await _insertProducts(txn, snapshot['products'] as List? ?? const []);
      await _insertPeople(txn, snapshot['people'] as List? ?? const []);
      await _insertSales(txn, snapshot['sales'] as List? ?? const []);
      await _insertSaleItems(txn, snapshot['saleItems'] as List? ?? const []);
      await _insertSupplies(txn, snapshot['incomingSupplies'] as List? ?? const []);
      await _insertPayments(txn, snapshot['paymentTransactions'] as List? ?? const []);
      await _insertExpenses(txn, snapshot['expenses'] as List? ?? const []);
      await _insertIncomeExpense(txn, snapshot['incomeExpense'] as List? ?? const []);
      await _insertCylinderRows(txn, snapshot['cylinderRows'] as List? ?? const []);
      await _insertCylinderTypes(txn, snapshot['cylinderTypes'] as List? ?? const []);
      await _insertCylinderCycles(txn, snapshot['cylinderCycles'] as List? ?? const []);
    });
  }

  Future<void> _insertProducts(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('products', {
        'id': j['id'] ?? '',
        'name': j['name'] ?? '',
        'type': j['type'] ?? '',
        'subtype': j['subType'] ?? '',
        'stock': (j['stock'] as num?)?.toDouble() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertPeople(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('people', {
        'name': j['name'] ?? '',
        'category': j['category'] ?? 'Customer',
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertSales(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('sales', {
        'voucher_number': j['voucherNumber'] ?? '',
        'date_ms': _date(j['date']),
        'customer': j['customer'] ?? '',
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertSaleItems(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('sale_items', {
        'voucher_number': j['saleVoucherNumber'] ?? '',
        'product_id': j['productId'] ?? '',
        'product': j['product'] ?? j['name'] ?? '',
        'quantity': (j['quantity'] as num?)?.toDouble() ?? 0,
        'selling_price': (j['sellingPrice'] as num?)?.toDouble() ?? 0,
        'profit': (j['profit'] as num?)?.toDouble() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertSupplies(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('incoming_supplies', {
        'id': j['id'] ?? '',
        'date_ms': _date(j['date']),
        'supplier': j['supplier'] ?? '',
        'product': j['product'] ?? '',
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertPayments(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('payment_transactions', {
        'id': j['id'] ?? '',
        'linked_type': j['linkedType'] ?? '',
        'linked_id': j['linkedId'] ?? '',
        'date_ms': _date(j['date']),
        'method': j['method'] ?? '',
        'amount': (j['amount'] as num?)?.toDouble() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertExpenses(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('expenses', {
        'id': j['id'] ?? '',
        'date_ms': _date(j['date']),
        'reason': j['reason'] ?? '',
        'amount': (j['amount'] as num?)?.toDouble() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertIncomeExpense(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('income_expense', {
        'id': j['id'] ?? '',
        'date_ms': _date(j['date']),
        'type': j['type'] ?? '',
        'name': j['name'] ?? '',
        'amount': (j['amount'] as num?)?.toDouble() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertCylinderRows(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('cylinder_rows', {
        'row_no': (j['no'] as num?)?.toInt() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertCylinderTypes(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('cylinder_types', {
        'id': j['id'] ?? '',
        'base_type': j['baseType'] ?? '',
        'name': j['name'] ?? '',
        'total_quantity': (j['totalQuantity'] as num?)?.toDouble() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }

  Future<void> _insertCylinderCycles(sql.DatabaseExecutor db, List rows) async {
    for (final raw in rows) {
      final j = Map<String, dynamic>.from(raw as Map);
      await db.insert('cylinder_cycles', {
        'id': j['id'] ?? '',
        'cylinder_type_id': j['cylinderTypeId'] ?? '',
        'customer': j['customer'] ?? '',
        'date_ms': _date(j['date']),
        'given_quantity': (j['givenQuantity'] as num?)?.toDouble() ?? 0,
        'received_quantity': (j['receivedQuantity'] as num?)?.toDouble() ?? 0,
        'data_json': jsonEncode(j),
      });
    }
  }


  Future<void> saveIncomingBundle({
    required Map<String, dynamic> product,
    required Map<String, dynamic> supply,
    Map<String, dynamic>? payment,
  }) async {
    await database.transaction((txn) async {
      await _upsertProduct(txn, product);
      await _upsertSupply(txn, supply);
      if (payment != null) await _upsertPayment(txn, payment);
    });
  }

  Future<void> deleteIncomingBundle({
    required String id,
    required Map<String, dynamic>? product,
  }) async {
    await database.transaction((txn) async {
      if (product != null) await _upsertProduct(txn, product);
      await txn.delete('payment_transactions',
          where: 'linked_type = ? AND linked_id = ?',
          whereArgs: ['supply', id]);
      await txn.delete('incoming_supplies', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> updateIncomingPaymentBundle({
    required Map<String, dynamic> supply,
    Map<String, dynamic>? payment,
  }) async {
    await database.transaction((txn) async {
      await _upsertSupply(txn, supply);
      if (payment != null) await _upsertPayment(txn, payment);
    });
  }

  Future<void> saveSaleBundle({
    required Map<String, dynamic> sale,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> products,
    List<Map<String, dynamic>> payments = const [],
  }) async {
    await database.transaction((txn) async {
      await _upsertSale(txn, sale);
      await txn.delete('sale_items',
          where: 'voucher_number = ?', whereArgs: [sale['voucherNumber']]);
      await txn.delete('payment_transactions',
          where: 'linked_type = ? AND linked_id = ?',
          whereArgs: ['sale', sale['voucherNumber']]);
      for (final item in items) {
        await _insertSaleItem(txn, item);
      }
      for (final payment in payments) {
        await _upsertPayment(txn, payment);
      }
      for (final product in products) {
        await _upsertProduct(txn, product);
      }
    });
  }

  Future<void> updateSalePaymentBundle({
    required Map<String, dynamic> sale,
    Map<String, dynamic>? payment,
  }) async {
    await database.transaction((txn) async {
      await _upsertSale(txn, sale);
      if (payment != null) await _upsertPayment(txn, payment);
    });
  }

  Future<void> deleteSaleBundle({
    required String voucherNumber,
    required List<Map<String, dynamic>> products,
  }) async {
    await database.transaction((txn) async {
      await txn.delete('sale_items',
          where: 'voucher_number = ?', whereArgs: [voucherNumber]);
      await txn.delete('payment_transactions',
          where: 'linked_type = ? AND linked_id = ?',
          whereArgs: ['sale', voucherNumber]);
      await txn.delete('sales',
          where: 'voucher_number = ?', whereArgs: [voucherNumber]);
      for (final product in products) {
        await _upsertProduct(txn, product);
      }
    });
  }

  Future<void> saveIncomeExpenseBundle({
    required Map<String, dynamic> entry,
    Map<String, dynamic>? expense,
  }) async {
    await database.transaction((txn) async {
      await _upsertIncomeExpense(txn, entry);
      if (expense != null) await _upsertExpense(txn, expense);
    });
  }

  Future<void> deleteIncomeExpenseBundle({
    required String id,
    required bool isExpense,
  }) async {
    await database.transaction((txn) async {
      await txn.delete('income_expense', where: 'id = ?', whereArgs: [id]);
      if (isExpense) await txn.delete('expenses', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> saveCylinderCycleBundle({
    required Map<String, dynamic> cycle,
    required Map<String, dynamic> type,
  }) async {
    await database.transaction((txn) async {
      await _upsertCylinderType(txn, type);
      await _upsertCylinderCycle(txn, cycle);
    });
  }

  Future<void> deleteCylinderCycleBundle({
    required String id,
    required Map<String, dynamic>? type,
  }) async {
    await database.transaction((txn) async {
      await txn.delete('cylinder_cycles', where: 'id = ?', whereArgs: [id]);
      if (type != null) await _upsertCylinderType(txn, type);
    });
  }

  Future<void> replaceCylinderTypeBundle(Map<String, dynamic> type) async {
    await _upsertCylinderType(database, type);
  }

  Future<void> deleteCylinderTypeBundle(String id) async {
    await database.delete('cylinder_types', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceCylinderRows(List<Map<String, dynamic>> rows) async {
    await database.transaction((txn) async {
      await txn.delete('cylinder_rows');
      await _insertCylinderRows(txn, rows);
    });
  }

  Future<void> _upsertProduct(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('products', {
      'id': j['id'] ?? '',
      'name': j['name'] ?? '',
      'type': j['type'] ?? '',
      'subtype': j['subType'] ?? '',
      'stock': (j['stock'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> _upsertSale(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('sales', {
      'voucher_number': j['voucherNumber'] ?? '',
      'date_ms': _date(j['date']),
      'customer': j['customer'] ?? '',
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> _insertSaleItem(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('sale_items', {
      'voucher_number': j['saleVoucherNumber'] ?? '',
      'product_id': j['productId'] ?? '',
      'product': j['product'] ?? '',
      'quantity': (j['quantity'] as num?)?.toDouble() ?? 0,
      'selling_price': (j['sellingPrice'] as num?)?.toDouble() ?? 0,
      'profit': (j['profit'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    });
  }

  Future<void> _upsertPayment(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('payment_transactions', {
      'id': j['id'] ?? '',
      'linked_type': j['linkedType'] ?? '',
      'linked_id': j['linkedId'] ?? '',
      'date_ms': _date(j['date']),
      'method': j['method'] ?? '',
      'amount': (j['amount'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> _upsertSupply(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('incoming_supplies', {
      'id': j['id'] ?? '',
      'date_ms': _date(j['date']),
      'supplier': j['supplier'] ?? '',
      'product': j['product'] ?? '',
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> _upsertIncomeExpense(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('income_expense', {
      'id': j['id'] ?? '',
      'date_ms': _date(j['date']),
      'type': j['type'] ?? '',
      'name': j['name'] ?? '',
      'amount': (j['amount'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> _upsertExpense(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('expenses', {
      'id': j['id'] ?? '',
      'date_ms': _date(j['date']),
      'reason': j['reason'] ?? '',
      'amount': (j['amount'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> _upsertCylinderType(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('cylinder_types', {
      'id': j['id'] ?? '',
      'base_type': j['baseType'] ?? '',
      'name': j['name'] ?? '',
      'total_quantity': (j['totalQuantity'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> _upsertCylinderCycle(sql.DatabaseExecutor db, Map<String, dynamic> j) async {
    await db.insert('cylinder_cycles', {
      'id': j['id'] ?? '',
      'cylinder_type_id': j['cylinderTypeId'] ?? '',
      'customer': j['customer'] ?? '',
      'date_ms': _date(j['date']),
      'given_quantity': (j['givenQuantity'] as num?)?.toDouble() ?? 0,
      'received_quantity': (j['receivedQuantity'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> upsertProduct(Map<String, dynamic> j) async {
    await database.insert('products', {
      'id': j['id'] ?? '',
      'name': j['name'] ?? '',
      'type': j['type'] ?? '',
      'subtype': j['subType'] ?? '',
      'stock': (j['stock'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteProduct(String id) async {
    await database.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteProductBundle({
    required String productId,
    required List<String> incomingIds,
  }) async {
    await database.transaction((txn) async {
      if (incomingIds.isNotEmpty) {
        await txn.delete(
          'payment_transactions',
          where: 'linked_type = ? AND linked_id IN (${List.filled(incomingIds.length, '?').join(',')})',
          whereArgs: ['supply', ...incomingIds],
        );
        await txn.delete(
          'incoming_supplies',
          where: 'id IN (${List.filled(incomingIds.length, '?').join(',')})',
          whereArgs: incomingIds,
        );
      }
      await txn.delete('products', where: 'id = ?', whereArgs: [productId]);
    });
  }

  Future<void> insertPerson(Map<String, dynamic> j) async {
    await database.insert('people', {
      'name': j['name'] ?? '',
      'category': j['category'] ?? 'Customer',
      'data_json': jsonEncode(j),
    });
  }

  Future<void> deletePerson(Map<String, dynamic> j) async {
    await database.delete(
      'people',
      where: 'name = ? AND category = ?',
      whereArgs: [j['name'] ?? '', j['category'] ?? 'Customer'],
    );
  }

  Future<void> upsertSale(Map<String, dynamic> j) async {
    await database.insert('sales', {
      'voucher_number': j['voucherNumber'] ?? '',
      'date_ms': _date(j['date']),
      'customer': j['customer'] ?? '',
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> updateSale(Map<String, dynamic> j) => upsertSale(j);

  Future<void> deleteSale(String voucherNumber) async {
    await database.transaction((txn) async {
      await txn.delete('sale_items', where: 'voucher_number = ?', whereArgs: [voucherNumber]);
      await txn.delete('payment_transactions', where: 'linked_type = ? AND linked_id = ?', whereArgs: ['sale', voucherNumber]);
      await txn.delete('sales', where: 'voucher_number = ?', whereArgs: [voucherNumber]);
    });
  }

  Future<void> replaceSaleItems(String voucherNumber, List<Map<String, dynamic>> items) async {
    await database.transaction((txn) async {
      await txn.delete('sale_items', where: 'voucher_number = ?', whereArgs: [voucherNumber]);
      for (final j in items) {
        await txn.insert('sale_items', {
          'voucher_number': j['saleVoucherNumber'] ?? voucherNumber,
          'product_id': j['productId'] ?? '',
          'product': j['product'] ?? '',
          'quantity': (j['quantity'] as num?)?.toDouble() ?? 0,
          'selling_price': (j['sellingPrice'] as num?)?.toDouble() ?? 0,
          'profit': (j['profit'] as num?)?.toDouble() ?? 0,
          'data_json': jsonEncode(j),
        });
      }
    });
  }

  Future<void> insertPayment(Map<String, dynamic> j) async {
    await database.insert('payment_transactions', {
      'id': j['id'] ?? '',
      'linked_type': j['linkedType'] ?? '',
      'linked_id': j['linkedId'] ?? '',
      'date_ms': _date(j['date']),
      'method': j['method'] ?? '',
      'amount': (j['amount'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteLinkedPayments(String linkedType, String linkedId) async {
    await database.delete(
      'payment_transactions',
      where: 'linked_type = ? AND linked_id = ?',
      whereArgs: [linkedType, linkedId],
    );
  }

  Future<void> upsertSupply(Map<String, dynamic> j) async {
    await database.insert('incoming_supplies', {
      'id': j['id'] ?? '',
      'date_ms': _date(j['date']),
      'supplier': j['supplier'] ?? '',
      'product': j['product'] ?? '',
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteSupply(String id) async {
    await database.transaction((txn) async {
      await txn.delete('payment_transactions', where: 'linked_type = ? AND linked_id = ?', whereArgs: ['supply', id]);
      await txn.delete('incoming_supplies', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> upsertExpense(Map<String, dynamic> j) async {
    await database.insert('expenses', {
      'id': j['id'] ?? '',
      'date_ms': _date(j['date']),
      'reason': j['reason'] ?? '',
      'amount': (j['amount'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteExpense(String id) async {
    await database.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertIncomeExpense(Map<String, dynamic> j) async {
    await database.insert('income_expense', {
      'id': j['id'] ?? '',
      'date_ms': _date(j['date']),
      'type': j['type'] ?? '',
      'name': j['name'] ?? '',
      'amount': (j['amount'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteIncomeExpense(String id) async {
    await database.delete('income_expense', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertCylinderType(Map<String, dynamic> j) async {
    await database.insert('cylinder_types', {
      'id': j['id'] ?? '',
      'base_type': j['baseType'] ?? '',
      'name': j['name'] ?? '',
      'total_quantity': (j['totalQuantity'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteCylinderType(String id) async {
    await database.delete('cylinder_types', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertCylinderCycle(Map<String, dynamic> j) async {
    await database.insert('cylinder_cycles', {
      'id': j['id'] ?? '',
      'cylinder_type_id': j['cylinderTypeId'] ?? '',
      'customer': j['customer'] ?? '',
      'date_ms': _date(j['date']),
      'given_quantity': (j['givenQuantity'] as num?)?.toDouble() ?? 0,
      'received_quantity': (j['receivedQuantity'] as num?)?.toDouble() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteCylinderCycle(String id) async {
    await database.delete('cylinder_cycles', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertCylinderRow(Map<String, dynamic> j) async {
    await database.insert('cylinder_rows', {
      'row_no': (j['no'] as num?)?.toInt() ?? 0,
      'data_json': jsonEncode(j),
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  // -------------------------------------------------------------------------
  // Report-friendly, bounded queries. These return only the requested window
  // instead of requiring the entire sales history to be materialized.
  // -------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> querySales({
    required int startMs,
    required int endMs,
    int? limit,
    int? offset,
  }) async {
    return database.query(
      'sales',
      columns: const ['voucher_number', 'date_ms', 'customer', 'data_json'],
      where: 'date_ms >= ? AND date_ms < ?',
      whereArgs: [startMs, endMs],
      orderBy: 'date_ms ASC, voucher_number ASC',
      limit: limit,
      offset: offset,
    );
  }

  Future<int> countSales({required int startMs, required int endMs}) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM sales WHERE date_ms >= ? AND date_ms < ?',
      [startMs, endMs],
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, Object?>>> querySaleItems(String voucherNumber) async {
    return database.query(
      'sale_items',
      columns: const ['voucher_number', 'product_id', 'product', 'quantity', 'selling_price', 'profit', 'data_json'],
      where: 'voucher_number = ?',
      whereArgs: [voucherNumber],
      orderBy: 'row_id ASC',
    );
  }

  Future<List<Map<String, Object?>>> queryPaymentsForSale(String voucherNumber) async {
    return database.query(
      'payment_transactions',
      columns: const ['id', 'linked_type', 'linked_id', 'date_ms', 'method', 'amount', 'data_json'],
      where: 'linked_type = ? AND linked_id = ?',
      whereArgs: ['sale', voucherNumber],
      orderBy: 'date_ms ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> queryExpenses({required int startMs, required int endMs}) async {
    return database.query(
      'income_expense',
      columns: const ['id', 'date_ms', 'type', 'name', 'amount', 'data_json'],
      where: 'type = ? AND date_ms >= ? AND date_ms < ?',
      whereArgs: ['expense', startMs, endMs],
      orderBy: 'date_ms ASC, id ASC',
    );
  }

  Future<Map<String, double>> paymentTotalsForPeriod({required int startMs, required int endMs}) async {
    final rows = await database.rawQuery('''
      SELECT COALESCE(NULLIF(method, ''), 'Unspecified') AS method,
             SUM(amount) AS amount
      FROM payment_transactions
      WHERE linked_type = 'sale'
        AND date_ms >= ? AND date_ms < ?
      GROUP BY COALESCE(NULLIF(method, ''), 'Unspecified')
      ORDER BY amount DESC
    ''', [startMs, endMs]);
    return {
      for (final row in rows)
        (row['method'] as String): ((row['amount'] as num?)?.toDouble() ?? 0),
    };
  }
}
