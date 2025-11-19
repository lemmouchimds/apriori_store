import 'dart:convert';

// 1. Product Model
class Product {
  final int? id;
  final String name;
  final double price;
  final String imagePath;

  Product({
    this.id,
    required this.name,
    required this.price,
    required this.imagePath,
  });

  // Convert a Product into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'image_path': imagePath,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      name: map['name'],
      price: map['price'],
      imagePath: map['image_path'],
    );
  }
}

// 2. Transaction Model (Renamed to SalesTransaction to avoid conflict with SQFlite Transaction)
class SalesTransaction {
  final int? id;
  final int timestamp; // Unix epoch
  final double totalAmount;

  SalesTransaction({
    this.id,
    required this.timestamp,
    required this.totalAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'total_amount': totalAmount,
    };
  }

  factory SalesTransaction.fromMap(Map<String, dynamic> map) {
    return SalesTransaction(
      id: map['id'],
      timestamp: map['timestamp'],
      totalAmount: map['total_amount'],
    );
  }
}

// 3. Transaction Item (Junction Table Model)
class TransactionItem {
  final int? id;
  final int transactionId;
  final int productId;

  TransactionItem({
    this.id,
    required this.transactionId,
    required this.productId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'product_id': productId,
    };
  }
}

// 4. Association Rule Model (For the Apriori Algorithm results)
class AssociationRule {
  final int? id;
  final List<int> antecedent; // Stored as JSON string in DB
  final List<int> consequent; // Stored as JSON string in DB
  final double confidence;
  final double support;
  final double lift;

  AssociationRule({
    this.id,
    required this.antecedent,
    required this.consequent,
    required this.confidence,
    required this.support,
    required this.lift,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'antecedent': jsonEncode(antecedent),
      'consequent': jsonEncode(consequent),
      'confidence': confidence,
      'support': support,
      'lift': lift,
    };
  }

  factory AssociationRule.fromMap(Map<String, dynamic> map) {
    return AssociationRule(
      id: map['id'],
      // JSON decoding is required here because SQFlite doesn't support Arrays
      antecedent: List<int>.from(jsonDecode(map['antecedent'])),
      consequent: List<int>.from(jsonDecode(map['consequent'])),
      confidence: map['confidence'],
      support: map['support'],
      lift: map['lift'],
    );
  }
}