import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../services/database_helper.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  _CartScreenState createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isLoading = false;

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

    // 3. Show Success & Navigate Back
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order Successful!'),
        content: const Text('Transaction has been saved locally. \n\n(Step 4: This is where the Apriori algorithm will trigger in the background)'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to shop
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
          // PLACEHOLDER FOR STEP 5: Checkout Recommendations
          // ---------------------------------------------------------
          if (cart.items.isNotEmpty)
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(10),
               color: Colors.blue[50],
               child: const Text(
                 "Recommender System Placeholder (Step 5)", 
                 textAlign: TextAlign.center,
                 style: TextStyle(color: Colors.blueGrey),
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