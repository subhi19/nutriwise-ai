class InventoryItem {
  final String name;
  final String? quantity;
  final bool useSoon;

  InventoryItem({required this.name, this.quantity, this.useSoon = false});

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        name: j['name'],
        quantity: j['quantity'],
        useSoon: j['use_soon'] ?? false,
      );

  Map<String, dynamic> toJson() => {'name': name, 'quantity': quantity, 'use_soon': useSoon};
}

class FridgeInventory {
  final List<InventoryItem> items;
  FridgeInventory({required this.items});

  factory FridgeInventory.fromJson(Map<String, dynamic> j) => FridgeInventory(
        items: (j['items'] as List).map((e) => InventoryItem.fromJson(e)).toList(),
      );

  Map<String, dynamic> toJson() => {'items': items.map((i) => i.toJson()).toList()};
}