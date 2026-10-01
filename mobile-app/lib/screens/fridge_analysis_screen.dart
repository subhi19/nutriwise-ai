import 'package:flutter/material.dart';

class FridgeAnalysisScreen extends StatelessWidget {
  const FridgeAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home Inventory Suggestion')),
      body: Center(
        child: Text('Home Inventory Based Meal Suggestion Screen',
            style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      ),
    );
  }
}