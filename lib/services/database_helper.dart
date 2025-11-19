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
    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Transaction Methods
  // ---------------------------------------------------------------------------

  Future<int> createFullTransaction(List<Product> cartItems, double total) async {
    final db = await instance.database;
    
    return await db.transaction((txn) async {
      final transactionId = await txn.insert('transactions', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'total_amount': total,
      });

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
  // RECOMMENDATION LOGIC (STEP 5 IMPLEMENTATION)
  // ---------------------------------------------------------------------------

  /// Scenario A: Product Page
  /// Returns products that appear in the 'Consequent' of rules where
  /// the 'Antecedent' contains this [productId].
  Future<List<Product>> getRelatedProducts(int productId) async {
    // 1. Get all rules (In a real large app, you'd optimize this query)
    final rules = await readAllRules();
    
    // 2. Filter: Find rules where 'productId' is in the antecedent
    final relevantRules = rules.where((r) => r.antecedent.contains(productId)).toList();
    
    if (relevantRules.isEmpty) return [];

    // 3. Collect Consequent IDs (Take top 3 strongest rules)
    Set<int> recommendedIds = {};
    for (var rule in relevantRules.take(3)) {
      recommendedIds.addAll(rule.consequent);
    }

    if (recommendedIds.isEmpty) return [];
    
    // 4. Fetch actual Product objects
    final db = await instance.database;
    final idList = recommendedIds.join(',');
    final result = await db.rawQuery('SELECT * FROM products WHERE id IN ($idList)');
    
    return result.map((json) => Product.fromMap(json)).toList();
  }

  /// Scenario B: Checkout Page
  /// Returns products that pattern-match the current cart contents.
  Future<List<Product>> getCartRecommendations(List<int> cartItemIds) async {
    if (cartItemIds.isEmpty) return [];

    final rules = await readAllRules();
    Set<int> recommendedIds = {};

    // Strategy: Find any rule where the antecedent is a subset of the cart
    // e.g. Rule: [Milk] -> [Bread]. Cart has: [Milk, Diapers]. Match!
    
    for (var rule in rules) {
      // Check if rule.antecedent is fully present in cartItemIds
      bool isMatch = rule.antecedent.every((id) => cartItemIds.contains(id));
      
      if (isMatch) {
        // Add consequents that are NOT already in the cart
        for (var conId in rule.consequent) {
          if (!cartItemIds.contains(conId)) {
            recommendedIds.add(conId);
          }
        }
      }
      // Limit to 5 distinct recommendations to avoid clutter
      if (recommendedIds.length >= 5) break; 
    }

    if (recommendedIds.isEmpty) return [];

    final db = await instance.database;
    final idList = recommendedIds.join(',');
    final result = await db.rawQuery('SELECT * FROM products WHERE id IN ($idList)');
    
    return result.map((json) => Product.fromMap(json)).toList();
  }

  // ---------------------------------------------------------------------------
  // SEEDING HELPERS
  // ---------------------------------------------------------------------------
  
  Future<void> seedDatabase() async {
    final db = await instance.database;
    
    var count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products'));
    if (count != null && count > 0) return; 

    List<Product> demoProducts = [
      Product(name: 'Bread', price: 2.50, imagePath: ''), 
      Product(name: 'Milk', price: 3.00, imagePath: ''),  
      Product(name: 'Eggs', price: 4.00, imagePath: ''), 
      Product(name: 'Hamoud', price: 1.50, imagePath: ''), 
    ];

    for (var p in demoProducts) {
      await createProduct(p);
    }

    Random rng = Random();
    
    for (int i = 0; i < 30; i++) {
      List<Product> cart = [];
      if (rng.nextBool()) {
        cart.add(demoProducts[0]);
        if (rng.nextDouble() > 0.2) cart.add(demoProducts[1]);
      }
      if (rng.nextDouble() > 0.7) {
        cart.add(demoProducts[2]);
        if (rng.nextDouble() > 0.1) cart.add(demoProducts[3]);
      }
      if (rng.nextBool()) cart.add(demoProducts[4]);
      if (rng.nextBool()) cart.add(demoProducts[5]);
      
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