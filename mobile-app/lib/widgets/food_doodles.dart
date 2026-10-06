import 'package:flutter/material.dart';

class FoodDoodles extends StatelessWidget {
  const FoodDoodles({super.key});

  static const _items = [
    ('🍎', Alignment(-0.92, -0.88), 34.0),
    ('🥦', Alignment(0.88, -0.8), 30.0),
    ('🍊', Alignment(-0.88, 0.1), 32.0),
    ('🥕', Alignment(0.92, -0.05), 28.0),
    ('🍇', Alignment(-0.85, 0.75), 30.0),
    ('🍋', Alignment(0.86, 0.6), 28.0),
    ('🍗', Alignment(0.9, 0.95), 32.0),
    ('🐟', Alignment(-0.9, -0.4), 26.0),
    ('🥑', Alignment(0.3, -0.95), 26.0),
    ('🍅', Alignment(-0.4, 0.95), 26.0),
    ('🥚', Alignment(0.95, 0.3), 24.0),
    ('🍓', Alignment(-0.3, -0.6), 24.0),
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
              opacity: 0.30, // raised from 0.16 for visibility
              child: Text(emoji, style: TextStyle(fontSize: size)),
            ),
          );
        }).toList(),
      ),
    );
  }
}