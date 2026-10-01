import 'package:flutter/material.dart';

class FamilyProfileScreen extends StatelessWidget {
  const FamilyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family Profile')),
      body: Center(
        child: Text('Family Profile Screen', style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}