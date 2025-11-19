import 'package:flutter/foundation.dart';
import '../models/shop_models.dart';
import 'database_helper.dart';

class AprioriService {
  // Configuration
  static const double MIN_SUPPORT = 0.2; // Item must appear in 20% of transactions
  static const double MIN_CONFIDENCE = 0.5; // Rule must be 50% accurate

  /// Triggers the calculation in a background isolate
  Future<void> runApriori() async {
    // 1. Fetch raw data from main thread
    final transactionMap = await DatabaseHelper.instance.getAllTransactionSets();
    
    if (transactionMap.isEmpty) {
      debugPrint("Apriori: No transactions found.");
      return;
    }

    // 2. Run heavy calculation in background isolate
    // We pass the map of {TransactionID: [ProductId, ProductId]}
    final List<AssociationRule> rules = await compute(_calculateRules, transactionMap);

    // 3. Save results back to DB
    await DatabaseHelper.instance.saveAssociationRules(rules);
    debugPrint("Apriori: Saved ${rules.length} rules.");
  }

  /// This function runs in a separate isolate.
  /// It cannot access any Flutter UI or Plugins (like SQFlite) directly.
  static List<AssociationRule> _calculateRules(Map<int, List<int>> dataset) {
    final int totalTransactions = dataset.length;
    final List<AssociationRule> validRules = [];

    // ---------------------------------------------------------
    // Step 1: Calculate Support for Single Items (L1)
    // ---------------------------------------------------------
    Map<int, int> itemCounts = {};
    
    for (var items in dataset.values) {
      for (var item in items) {
        itemCounts[item] = (itemCounts[item] ?? 0) + 1;
      }
    }

    // Filter by Min Support
    List<int> frequentItems = [];
    itemCounts.forEach((item, count) {
      double support = count / totalTransactions;
      if (support >= MIN_SUPPORT) {
        frequentItems.add(item);
      }
    });

    // ---------------------------------------------------------
    // Step 2: Generate Pairs (L2) and Count
    // ---------------------------------------------------------
    Map<String, int> pairCounts = {};
    
    // We only look at pairs existing in actual transactions to save time
    for (var items in dataset.values) {
      // Sort to ensure {A,B} is same as {B,A}
      items.sort();
      
      // Generate combinations of size 2
      for (int i = 0; i < items.length; i++) {
        for (int j = i + 1; j < items.length; j++) {
          int a = items[i];
          int b = items[j];

          // Only consider if both individual items are frequent
          if (frequentItems.contains(a) && frequentItems.contains(b)) {
            String key = "$a,$b";
            pairCounts[key] = (pairCounts[key] ?? 0) + 1;
          }
        }
      }
    }

    // ---------------------------------------------------------
    // Step 3: Generate Rules from Frequent Pairs
    // ---------------------------------------------------------
    pairCounts.forEach((key, count) {
      double pairSupport = count / totalTransactions;

      if (pairSupport >= MIN_SUPPORT) {
        // Parse key back to ints
        final parts = key.split(',');
        int itemA = int.parse(parts[0]);
        int itemB = int.parse(parts[1]);

        // Calculate Confidence for A -> B
        // Confidence = Support(A,B) / Support(A)
        double supportA = (itemCounts[itemA] ?? 0) / totalTransactions;
        double confidenceAtoB = pairSupport / supportA;

        if (confidenceAtoB >= MIN_CONFIDENCE) {
          validRules.add(AssociationRule(
            antecedent: [itemA],
            consequent: [itemB],
            confidence: confidenceAtoB,
            support: pairSupport,
            lift: confidenceAtoB / ((itemCounts[itemB] ?? 1) / totalTransactions),
          ));
        }

        // Calculate Confidence for B -> A
        double supportB = (itemCounts[itemB] ?? 0) / totalTransactions;
        double confidenceBtoA = pairSupport / supportB;

        if (confidenceBtoA >= MIN_CONFIDENCE) {
          validRules.add(AssociationRule(
            antecedent: [itemB],
            consequent: [itemA],
            confidence: confidenceBtoA,
            support: pairSupport,
            lift: confidenceBtoA / ((itemCounts[itemA] ?? 1) / totalTransactions),
          ));
        }
      }
    });

    // Sort by confidence (strongest rules first)
    validRules.sort((a, b) => b.confidence.compareTo(a.confidence));

    return validRules;
  }
}