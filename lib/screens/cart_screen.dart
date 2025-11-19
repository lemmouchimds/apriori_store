import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/shop_models.dart';
import '../providers/cart_provider.dart';
import '../services/database_helper.dart';
import '../services/apriori_service.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  _CartScreenState createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isLoading = false;

  // Trigger logic for Step 4 in the background
  Future<void> _triggerAprioriInBackground() async {
    // We don't await this because we don't want to block the UI success message
    AprioriService().runApriori(); 
  }

  Future<void> _processCheckout(CartProvider cart) async {
    if (cart.items.isEmpty) return;

    setState(() => _isLoading = true);

    // 1. Save to Database
    await DatabaseHelper.instance.createFullTransaction(
      cart.items,
      cart.totalAmount,
    );

    // 2. Clear UI
    cart.clearCart();

    setState(() => _isLoading = false);

    // 3. Trigger Re-calculation of rules
    _triggerAprioriInBackground();

    // 4. Show Success
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order Successful!'),
        content: const Text('Transaction saved.\n\nThe Apriori Algorithm is now updating association rules in the background...'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); 
              Navigator.of(context).pop(); 
            },
            child: const Text('Awesome'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Cart')),
      body: Column(
        children: [
          // Cart Items List
          Expanded(
            child: cart.items.isEmpty
                ? const Center(child: Text('Your cart is empty.'))
                : ListView.builder(
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return ListTile(
                        leading: const Icon(Icons.shopping_bag),
                        title: Text(item.name),
                        subtitle: Text('\$${item.price.toStringAsFixed(2)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => cart.removeItem(item),
                        ),
                      );
                    },
                  ),
          ),
          
          // ---------------------------------------------------------
          // STEP 5: CART-BASED RECOMMENDATIONS
          // ---------------------------------------------------------
          if (cart.items.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.blue[50],
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "You might be forgetting:",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Product>>(
                    // Re-fetch recommendations whenever cart changes
                    future: DatabaseHelper.instance.getCartRecommendations(
                      cart.items.map((e) => e.id!).toList()
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Text(
                          "No patterns detected yet.", 
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)
                        );
                      }

                      return SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final product = snapshot.data![index];
                            return Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              child: Card(
                                elevation: 2,
                                child: InkWell(
                                  onTap: () {
                                    cart.addItem(product);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('${product.name} added!'), duration: const Duration(milliseconds: 500)),
                                    );
                                  },
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: (product.imagePath.isNotEmpty && File(product.imagePath).existsSync())
                                          ? Image.file(File(product.imagePath), fit: BoxFit.cover)
                                          : const Icon(Icons.shopping_bag, size: 30, color: Colors.grey),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Text(product.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                                      ),
                                      const Icon(Icons.add_circle, color: Colors.green, size: 16),
                                      const SizedBox(height: 4),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

          // Checkout Footer
          Card(
            margin: const EdgeInsets.all(15),
            elevation: 5,
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 16)),
                      Text(
                        '\$${cart.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20, 
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: (cart.items.isEmpty || _isLoading) 
                        ? null 
                        : () => _processCheckout(cart),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    ),
                    child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Text('CHECKOUT', style: TextStyle(fontSize: 16)),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}