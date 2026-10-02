import 'package:flutter/material.dart';

class FoodDoodles extends StatelessWidget {
  const FoodDoodles({super.key});

  static const _items = [
    ('🍎', Alignment(-0.9, -0.85), 30.0),
    ('🥦', Alignment(0.88, -0.75), 26.0),
    ('🍊', Alignment(-0.85, 0.15), 28.0),
    ('🥕', Alignment(0.9, 0.05), 24.0),
    ('🍇', Alignment(-0.8, 0.85), 26.0),
    ('🍋', Alignment(0.85, 0.8), 24.0),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: _items.map((item) {
          final (emoji, alignment, size) = item;
          return Align(
            alignment: alignment,
            child: Opacity(
              opacity: 0.16,
              child: Text(emoji, style: TextStyle(fontSize: size)),
            ),
          );
        }).toList(),
      ),
    );
  }
}