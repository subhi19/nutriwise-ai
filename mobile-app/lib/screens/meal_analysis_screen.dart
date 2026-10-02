import 'package:flutter/material.dart';

class MealAnalysisScreen extends StatelessWidget {
  const MealAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nutrient Analyzer')),
      body: Center(
        child: Text('Nutrient Analyzer Screen', style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}