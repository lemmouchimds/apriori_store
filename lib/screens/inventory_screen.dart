import 'package:flutter/material.dart';
import '../models/shop_models.dart';
import '../services/database_helper.dart';
import '../services/apriori_service.dart';
import 'product_form_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  _InventoryScreenState createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<Product>> _productsFuture;
  final AprioriService _aprioriService = AprioriService();

  @override
  void initState() {
    super.initState();
    _refreshProducts();
  }

  void _refreshProducts() {
    setState(() {
      _productsFuture = DatabaseHelper.instance.readAllProducts();
    });
  }

  Future<void> _deleteProduct(int id) async {
    await DatabaseHelper.instance.deleteProduct(id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product deleted successfully')),
    );
    _refreshProducts();
  }

  // ---------------------------------------------------------
  // ACTIONS FOR APRIORI
  // ---------------------------------------------------------
  Future<void> _seedData() async {
    await DatabaseHelper.instance.seedDatabase();
    _refreshProducts();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Database Seeded! Transactions Created.')),
    );
  }

  Future<void> _runApriori() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Run Algo
    await _aprioriService.runApriori();

    // Close loading
    if (!mounted) return;
    Navigator.pop(context);

    // Fetch rules to show count
    final rules = await DatabaseHelper.instance.readAllRules();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Analysis Complete'),
        content: Text('Generated ${rules.length} association rules based on current transaction history.\n\nTop Rule: ${rules.isNotEmpty ? "${rules.first.antecedent} -> ${rules.first.consequent}" : "None"}'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _navigateToForm({Product? product}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductFormScreen(product: product),
      ),
    );

    if (result == true) {
      _refreshProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'seed') _seedData();
              if (value == 'apriori') _runApriori();
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(
                  value: 'seed',
                  child: Text('Seed Dummy Data'),
                ),
                const PopupMenuItem(
                  value: 'apriori',
                  child: Text('Force Run Apriori'),
                ),
              ];
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No products found.\nUse the top-right menu to SEED DATA.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final products = snapshot.data!;
          
          return RefreshIndicator(
            onRefresh: () async => _refreshProducts(),
            child: ListView.builder(
              itemCount: products.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                final product = products[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: product.imagePath.startsWith('http')
                          ? Image.network(product.imagePath, fit: BoxFit.cover, 
                              errorBuilder: (c, o, s) => const Icon(Icons.broken_image))
                          : const Icon(Icons.shopping_bag),
                    ),
                    title: Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _navigateToForm(product: product),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteProduct(product.id!),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}