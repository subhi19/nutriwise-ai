import 'package:flutter/material.dart';

class MealPlanScreen extends StatelessWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meal Planner')),
      body: Center(
        child: Text('Meal Planner Tab', style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}