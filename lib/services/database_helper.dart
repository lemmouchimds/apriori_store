import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/shop_models.dart';

class DatabaseHelper {
  // Singleton pattern
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('basket_tech.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Products Table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        image_path TEXT NOT NULL
      )
    ''');

    // 2. Transactions Table
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        total_amount REAL NOT NULL
      )
    ''');

    // 3. Transaction Items (Junction) Table
    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        FOREIGN KEY (transaction_id) REFERENCES transactions (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // 4. Association Rules Table
    await db.execute('''
      CREATE TABLE association_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        antecedent TEXT NOT NULL,
        consequent TEXT NOT NULL,
        confidence REAL NOT NULL,
        support REAL NOT NULL,
        lift REAL NOT NULL
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // Product Methods
  // ---------------------------------------------------------------------------

  Future<int> createProduct(Product product) async {
    final db = await instance.database;
    return await db.insert('products', product.toMap());
  }

  Future<Product?> readProduct(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'products',
      columns: ['id', 'name', 'price', 'image_path'],
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<List<Product>> readAllProducts() async {
    final db = await instance.database;
    final result = await db.query('products');
    return result.map((json) => Product.fromMap(json)).toList();
  }

  Future<int> updateProduct(Product product) async {
    final db = await instance.database;
    return db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    // Note: Soft delete is preferred in production, but strict delete requested in scope
    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Transaction Methods
  // ---------------------------------------------------------------------------

  /// Inserts a transaction header and all its associated items atomically.
  Future<int> createFullTransaction(List<Product> cartItems, double total) async {
    final db = await instance.database;
    
    // Use a Transaction block to ensure data integrity
    return await db.transaction((txn) async {
      // 1. Insert the Transaction Header
      final transactionId = await txn.insert('transactions', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'total_amount': total,
      });

      // 2. Insert each Item in the Cart linked to this Transaction ID
      for (var product in cartItems) {
        await txn.insert('transaction_items', {
          'transaction_id': transactionId,
          'product_id': product.id,
        });
      }

      return transactionId;
    });
  }

  Future<List<SalesTransaction>> readAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'timestamp DESC');
    return result.map((json) => SalesTransaction.fromMap(json)).toList();
  }

  // ---------------------------------------------------------------------------
  // Apriori Data Fetching Methods
  // ---------------------------------------------------------------------------

  /// Fetches all transaction items to be fed into the Apriori Algorithm.
  /// Returns a Map where Key = transactionId and Value = List of productIds.
  Future<Map<int, List<int>>> getAllTransactionSets() async {
    final db = await instance.database;
    final result = await db.query('transaction_items');
    
    Map<int, List<int>> transactionSets = {};

    for (var row in result) {
      int tId = row['transaction_id'] as int;
      int pId = row['product_id'] as int;

      if (!transactionSets.containsKey(tId)) {
        transactionSets[tId] = [];
      }
      transactionSets[tId]!.add(pId);
    }

    return transactionSets;
  }
  
  // ---------------------------------------------------------------------------
  // Rule Methods
  // ---------------------------------------------------------------------------

  Future<void> saveAssociationRules(List<AssociationRule> rules) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // Clear old rules first - we only want the latest analysis
      await txn.delete('association_rules');
      
      for (var rule in rules) {
        await txn.insert('association_rules', rule.toMap());
      }
    });
  }

  Future<List<AssociationRule>> readAllRules() async {
    final db = await instance.database;
    final result = await db.query('association_rules', orderBy: 'confidence DESC');
    return result.map((json) => AssociationRule.fromMap(json)).toList();
  }

  // ---------------------------------------------------------------------------
  // SEEDING HELPERS (For Demo Purposes)
  // ---------------------------------------------------------------------------
  
  Future<void> seedDatabase() async {
    final db = await instance.database;
    
    // 1. Check if products exist, if so, don't overwrite
    var count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products'));
    if (count != null && count > 0) return; 

    // 2. Add Products
    List<Product> demoProducts = [
      Product(name: 'Bread', price: 2.50, imagePath: ''), // ID 1
      Product(name: 'Milk', price: 3.00, imagePath: ''),  // ID 2
      Product(name: 'Diapers', price: 15.00, imagePath: ''), // ID 3
      Product(name: 'Beer', price: 8.00, imagePath: ''), // ID 4
      Product(name: 'Eggs', price: 4.00, imagePath: ''), // ID 5
      Product(name: 'Cola', price: 1.50, imagePath: ''), // ID 6
    ];

    for (var p in demoProducts) {
      await createProduct(p);
    }

    // 3. Generate 20 Dummy Transactions to create patterns
    // Pattern 1: Bread & Milk often go together
    // Pattern 2: Diapers & Beer often go together
    
    Random rng = Random();
    
    for (int i = 0; i < 30; i++) {
      List<Product> cart = [];
      
      // 50% chance to buy Bread
      if (rng.nextBool()) {
        cart.add(demoProducts[0]); // Bread
        // 80% chance to buy Milk if buying Bread
        if (rng.nextDouble() > 0.2) cart.add(demoProducts[1]); // Milk
      }

      // 30% chance to buy Diapers
      if (rng.nextDouble() > 0.7) {
        cart.add(demoProducts[2]); // Diapers
        // 90% chance to buy Beer if buying Diapers (Classic Apriori example)
        if (rng.nextDouble() > 0.1) cart.add(demoProducts[3]); // Beer
      }

      // Random noise (Eggs or Cola)
      if (rng.nextBool()) cart.add(demoProducts[4]); // Eggs
      if (rng.nextBool()) cart.add(demoProducts[5]); // Cola
      
      if (cart.isNotEmpty) {
        await createFullTransaction(
          cart, 
          cart.fold(0, (sum, item) => sum + item.price)
        );
      }
    }
    debugPrint("Database Seeded with 30 transactions.");
  }
}