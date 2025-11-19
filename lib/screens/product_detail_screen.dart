import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/shop_models.dart';
import '../services/database_helper.dart';
import '../providers/cart_provider.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({Key? key, required this.product}) : super(key: key);

  @override
  _ProductDetailScreenState createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<List<Product>> _recommendationsFuture;

  @override
  void initState() {
    super.initState();
    // Fetch products that are frequently bought with THIS product
    _recommendationsFuture = DatabaseHelper.instance.getRelatedProducts(widget.product.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product.name)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Product Image
            Container(
              height: 300,
              width: double.infinity,
              color: Colors.grey[200],
              child: (widget.product.imagePath.isNotEmpty && File(widget.product.imagePath).existsSync())
                  ? Image.file(File(widget.product.imagePath), fit: BoxFit.cover)
                  : const Icon(Icons.shopping_bag, size: 100, color: Colors.grey),
            ),
            
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.name,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '\$${widget.product.price.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 22, color: Colors.green),
                  ),
                  const SizedBox(height: 20),
                  
                  // "Add to Cart" Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Provider.of<CartProvider>(context, listen: false)
                            .addItem(widget.product);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Add to Cart'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // ---------------------------------------------------------
                  // STEP 5: LIVE RECOMMENDATIONS
                  // ---------------------------------------------------------
                  const Divider(),
                  const Text(
                    "Frequently bought together:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  
                  FutureBuilder<List<Product>>(
                    future: _recommendationsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                         return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.grey),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "No recommendations yet. Try running the Apriori Algorithm in Inventory Settings.",
                                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // Display Recommendations
                      return SizedBox(
                        height: 160,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final recProduct = snapshot.data![index];
                            return Container(
                              width: 120,
                              margin: const EdgeInsets.only(right: 10),
                              child: Card(
                                child: InkWell(
                                  onTap: () {
                                    // Navigate to the recommended product
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProductDetailScreen(product: recProduct),
                                      ),
                                    );
                                  },
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: (recProduct.imagePath.isNotEmpty && File(recProduct.imagePath).existsSync())
                                          ? Image.file(File(recProduct.imagePath), fit: BoxFit.cover)
                                          : const Icon(Icons.shopping_bag, color: Colors.grey),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Text(
                                          recProduct.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Text('\$${recProduct.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}