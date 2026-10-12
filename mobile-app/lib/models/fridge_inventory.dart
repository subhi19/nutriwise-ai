class InventoryItem {
  final String name;
  final String? quantity;
  final bool useSoon;

  InventoryItem({required this.name, this.quantity, this.useSoon = false});

  // Accepts a plain string ("paneer") or an object {name, quantity, use_soon}
  factory InventoryItem.fromJson(dynamic j) {
    if (j is String) return InventoryItem(name: j);
    final m = Map<String, dynamic>.from(j as Map);
    return InventoryItem(
      name: (m['name'] ?? '').toString(),
      quantity: m['quantity']?.toString(),
      useSoon: m['use_soon'] == true,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'quantity': quantity, 'use_soon': useSoon};
}

class FridgeInventory {
  final List<InventoryItem> items;
  FridgeInventory({required this.items});

  /// Reads {items: [...]} or {detected_items: ["paneer", ...]}
  factory FridgeInventory.fromJson(Map<String, dynamic> j) {
    final raw = (j['items'] ?? j['detected_items'] ?? const []) as List;
    return FridgeInventory(items: raw.map(InventoryItem.fromJson).toList());
  }

  Map<String, dynamic> toJson() => {'items': items.map((i) => i.toJson()).toList()};

  /// What we send to the server: both shapes, so it works with either contract.
  /// TODO: keep only the shape the backend confirms. Note that `detected_items`
  /// has no "use soon" flag, so that feature only works if `items` is supported.
  Map<String, dynamic> toRequestJson() => {
        'items': items.map((i) => i.toJson()).toList(),
        'detected_items': items.map((i) => i.name).toList(),
      };
}