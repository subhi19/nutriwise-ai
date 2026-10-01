import 'package:flutter/material.dart';

class GroceryListScreen extends StatelessWidget {
  const GroceryListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grocery List')),
      body: Center(
        child: Text('Grocery List Screen', style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}