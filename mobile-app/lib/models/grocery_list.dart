class GroceryItem {
  final String name;
  final int? foodId;
  final String quantity;
  final String category;
  final String source; // missing_ingredient | preference | user_added

  GroceryItem({
    required this.name,
    this.foodId,
    required this.quantity,
    required this.category,
    required this.source,
  });

  factory GroceryItem.fromJson(Map<String, dynamic> j) => GroceryItem(
        name: j['name'],
        foodId: j['food_id'],
        quantity: j['quantity'] ?? '',
        category: j['category'] ?? 'Other',
        source: j['source'] ?? 'missing_ingredient',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'food_id': foodId,
        'quantity': quantity,
        'category': category,
        'source': source,
      };
}

class GroceryList {
  final List<GroceryItem> items;
  final List<String> notInDatabase;

  GroceryList({required this.items, this.notInDatabase = const []});

  factory GroceryList.fromJson(Map<String, dynamic> j) => GroceryList(
        items: (j['items'] as List).map((e) => GroceryItem.fromJson(e)).toList(),
        notInDatabase: List<String>.from(j['not_in_database'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'items': items.map((i) => i.toJson()).toList(),
        'not_in_database': notInDatabase,
      };
}