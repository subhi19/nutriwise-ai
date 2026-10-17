import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../models/grocery_list.dart';
import '../providers/providers.dart';
import '../services/local_storage_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';
import '../widgets/error_box.dart';
import '../widgets/grocery_export_card.dart';
import '../widgets/save_card_dialog.dart';

class GroceryListScreen extends ConsumerStatefulWidget {
  const GroceryListScreen({super.key});

  @override
  ConsumerState<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends ConsumerState<GroceryListScreen> {
  final _reqCtrl = TextEditingController();
  final List<String> _requirements = [];
  final Set<String> _checked = {};
  AsyncValue<GroceryList>? _result;
  bool _saving = false;

  @override
  void dispose() {
    _reqCtrl.dispose();
    super.dispose();
  }

  String _keyOf(GroceryItem i) => '${i.category}|${i.name}';

  void _addRequirement() {
    final v = _reqCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      if (!_requirements.any((r) => r.toLowerCase() == v.toLowerCase())) _requirements.add(v);
      _reqCtrl.clear();
    });
  }

  Future<void> _generate() async {
    final plan = ref.read(currentPlanProvider);
    if (plan == null) return;
    _addRequirement(); // don't lose something typed but not yet added
    final family = ref.read(planFamilyProvider);
    final inventory = ref.read(fridgeInventoryProvider);

    setState(() {
      _result = const AsyncLoading();
      _checked.clear();
    });
    try {
      final list = await ref
          .read(apiProvider)
          .generateGroceryList(family, plan, inventory, List.of(_requirements));
      if (!mounted) return;
      setState(() => _result = AsyncData(list));
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _result = AsyncError(e, st));
    }
  }

  Future<void> _save(GroceryList list) async {
    setState(() => _saving = true);
    final saved = await confirmAndSaveCard(
      context,
      title: 'Save this grocery list?',
      message: 'Would you like to save your grocery list as a card on your device?',
      card: GroceryExportCard(list: list, checked: _checked, keyOf: _keyOf),
      filenamePrefix: 'nutriwise_grocery_list',
    );
    if (saved) {
      await LocalStorageService.saveGroceryList(list, _checked);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(currentPlanProvider);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBrandBar(backTo: '/dashboard', confirmLeave: _checked.isNotEmpty),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🛒 Grocery List', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Only what you still need to buy',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      if (plan == null)
                        _NoPlan(onGo: () => context.go('/plan'))
                      else ...[
                        _ExtrasCard(
                          controller: _reqCtrl,
                          requirements: _requirements,
                          onAdd: _addRequirement,
                          onRemove: (r) => setState(() => _requirements.remove(r)),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.checklist_rounded),
                            label: Text(_result == null ? 'Generate Grocery List' : 'Regenerate List'),
                            onPressed: _result is AsyncLoading ? null : _generate,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_result != null)
                          _result!.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Column(
                                  children: [
                                    CircularProgressIndicator(color: AppColors.primary),
                                    SizedBox(height: 12),
                                    Text('Preparing your list…'),
                                  ],
                                ),
                              ),
                            ),
                            error: (e, _) => ErrorBox(error: e, onRetry: _generate),
                            data: (list) => _GroceryResult(
                              list: list,
                              checked: _checked,
                              keyOf: _keyOf,
                              saving: _saving,
                              onToggle: (item, v) => setState(() {
                                v ? _checked.add(_keyOf(item)) : _checked.remove(_keyOf(item));
                              }),
                              onSave: () => _save(list),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  final VoidCallback onGo;
  const _NoPlan({required this.onGo});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('📅', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text('No meal plan yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Create a 7-day plan first, then we\'ll build your shopping list from it.',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onGo, child: const Text('Go to Meal Planner')),
          ],
        ),
      ),
    );
  }
}

class _ExtrasCard extends StatelessWidget {
  final TextEditingController controller;
  final List<String> requirements;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _ExtrasCard({
    required this.controller,
    required this.requirements,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Anything else to add? (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onAdd(),
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      hintText: 'e.g. almond milk',
                      prefixIcon: Icon(Icons.add_shopping_cart),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onAdd,
                  tooltip: 'Add item',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    fixedSize: const Size(52, 52),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 30, color: Colors.white),
                ),
              ],
            ),
            if (requirements.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: requirements
                    .map((r) => InputChip(label: Text(r), onDeleted: () => onRemove(r)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroceryResult extends StatelessWidget {
  final GroceryList list;
  final Set<String> checked;
  final String Function(GroceryItem) keyOf;
  final void Function(GroceryItem, bool) onToggle;
  final bool saving;
  final VoidCallback onSave;

  const _GroceryResult({
    required this.list,
    required this.checked,
    required this.keyOf,
    required this.onToggle,
    required this.saving,
    required this.onSave,
  });

  static const _emoji = {
    'Vegetables': '🥦',
    'Fruits': '🍎',
    'Dairy': '🥛',
    'Grains': '🌾',
    'Protein': '🍗',
    'Pulses': '🌱',
    'Spices & Pantry': '🧂',
    'Other': '🛒',
  };

  @override
  Widget build(BuildContext context) {
    if (list.items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('🎉 You already have everything you need!',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
      );
    }

    final groups = <String, List<GroceryItem>>{};
    for (final item in list.items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final done = list.items.where((i) => checked.contains(keyOf(i))).length;
    final total = list.items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('$done of $total items', style: Theme.of(context).textTheme.titleSmall)),
            Text('${(done / total * 100).round()}%',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: done / total,
            minHeight: 8,
            color: AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 12),
        ...groups.entries.map((entry) => Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_emoji[entry.key] ?? '🛒'} ${entry.key}',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    ...entry.value.map((item) {
                      final isChecked = checked.contains(keyOf(item));
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.primary,
                        value: isChecked,
                        onChanged: (v) => onToggle(item, v ?? false),
                        title: Text(
                          item.name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                decoration: isChecked ? TextDecoration.lineThrough : null,
                                color: isChecked ? AppColors.textSecondary : null,
                              ),
                        ),
                        subtitle: Text(item.quantity),
                        secondary: item.source == 'user_added'
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.tertiary.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('Added by you',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                              )
                            : null,
                      );
                    }),
                  ],
                ),
              ),
            )),
        if (list.notInDatabase.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'We couldn\'t find nutrition details for: ${list.notInDatabase.join(', ')}. '
                    'They\'re still on your list.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.favorite_border),
            label: const Text('Save & Finish'),
            onPressed: saving ? null : onSave,
          ),
        ),
      ],
    );
  }
}