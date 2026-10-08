import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/day_preference.dart';
import '../models/family_member.dart';
import '../models/fridge_inventory.dart';
import '../models/meal_plan.dart';
import '../models/meal_type.dart';
import '../providers/providers.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';
import '../widgets/error_box.dart';
import '../widgets/selectable_chip.dart';

class MealPlanScreen extends ConsumerStatefulWidget {
  const MealPlanScreen({super.key});

  @override
  ConsumerState<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends ConsumerState<MealPlanScreen> {
  // Step 1: optional fridge photo
  Uint8List? _fridgeImage;
  AsyncValue<FridgeInventory>? _fridgeResult;
  List<InventoryItem> _inventoryItems = [];

  // Step 2: who is eating
  final Set<String> _excludedMembers = {};

  // Step 3: per-day preferences
  List<DayPreference> _prefs = defaultWeekPreferences();

  // Result
  AsyncValue<WeeklyPlan>? _planResult;
  int _selectedDay = 0;

  // ---------- Step 1 ----------

  Future<void> _pickFridge(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 1024, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _fridgeImage = bytes;
      _fridgeResult = null;
      _inventoryItems = [];
    });
  }

  Future<void> _analyzeFridge() async {
    if (_fridgeImage == null) return;
    setState(() => _fridgeResult = const AsyncLoading());
    try {
      final inv = await ref.read(apiProvider).analyzeFridge(_fridgeImage!);
      if (!mounted) return;
      setState(() {
        _fridgeResult = AsyncData(inv);
        _inventoryItems = List.of(inv.items);
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _fridgeResult = AsyncError(e, st));
    }
  }

  Future<void> _addInventoryItem() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add an item'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Item name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => _inventoryItems.add(InventoryItem(name: name)));
    }
  }

  // ---------- Step 3 ----------

  Future<void> _pickMealType(int index) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MealTypeSheet(currentCode: _prefs[index].mealTypeCode),
    );
    if (selected != null) {
      setState(() => _prefs[index] = _prefs[index].copyWith(mealTypeCode: selected));
    }
  }

  void _applyMondayToAll() {
    final first = _prefs.first;
    setState(() {
      _prefs = _prefs
          .map((d) => d.copyWith(
                mealTypeCode: first.mealTypeCode,
                cuisinePreferences: List.of(first.cuisinePreferences),
              ))
          .toList();
    });
  }

  // ---------- Generate ----------

  Future<void> _generate(List<FamilyMember> members) async {
    final family = members.where((m) => !_excludedMembers.contains(m.id ?? m.name)).toList();
    if (family.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one family member.')),
      );
      return;
    }
    final inventory = _inventoryItems.isEmpty ? null : FridgeInventory(items: List.of(_inventoryItems));

    setState(() {
      _planResult = const AsyncLoading();
      _selectedDay = 0;
    });
    try {
      final plan = await ref.read(apiProvider).generateMealPlan(family, inventory, _prefs);
      if (!mounted) return;
      // Carry everything forward for the Grocery List screen
      ref.read(currentPlanProvider.notifier).state = plan;
      ref.read(fridgeInventoryProvider.notifier).state = inventory;
      ref.read(planFamilyProvider.notifier).state = family;
      setState(() => _planResult = AsyncData(plan));
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _planResult = AsyncError(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final members = membersAsync.maybeWhen(data: (d) => d, orElse: () => <FamilyMember>[]);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              const AppBrandBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📅 Meal Planner', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('A personalized 7-day plan for your family',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),

                      // ---- Step 1 ----
                      _StepCard(
                        number: 1,
                        title: 'Groceries at home? (optional)',
                        child: _buildFridgeStep(),
                      ),

                      // ---- Step 2 ----
                      _StepCard(
                        number: 2,
                        title: 'Who is eating this week?',
                        child: members.isEmpty
                            ? Text('Add family members first.', style: Theme.of(context).textTheme.bodySmall)
                            : Column(
                                children: members.map((m) {
                                  final key = m.id ?? m.name;
                                  return CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: AppColors.primary,
                                    value: !_excludedMembers.contains(key),
                                    title: Text(m.name),
                                    subtitle: Text('${m.age} yrs · ${AppVocab.displayLabel(m.foodPreference)}'),
                                    onChanged: (v) => setState(() {
                                      v == true ? _excludedMembers.remove(key) : _excludedMembers.add(key);
                                    }),
                                  );
                                }).toList(),
                              ),
                      ),

                      // ---- Step 3 ----
                      _StepCard(
                        number: 3,
                        title: 'Plan the week',
                        trailing: TextButton(
                          onPressed: _applyMondayToAll,
                          child: const Text('Same as Monday'),
                        ),
                        child: Column(
                          children: List.generate(_prefs.length, (i) {
                            final pref = _prefs[i];
                            final type = mealTypeByCode(pref.mealTypeCode);
                            return _DayPrefRow(
                              pref: pref,
                              typeLabel: type.label,
                              onPickType: () => _pickMealType(i),
                              onCuisineToggled: (c, sel) {
                                final list = List<String>.from(pref.cuisinePreferences);
                                sel ? list.add(c) : list.remove(c);
                                setState(() => _prefs[i] = pref.copyWith(cuisinePreferences: list));
                              },
                            );
                          }),
                        ),
                      ),

                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generate My Plan'),
                          onPressed: (members.isEmpty || _planResult is AsyncLoading)
                              ? null
                              : () => _generate(members),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_planResult != null)
                        _planResult!.when(
                          loading: () => const _PlanLoading(),
                          error: (e, _) => ErrorBox(error: e, onRetry: () => _generate(members)),
                          data: (plan) => _PlanView(
                            plan: plan,
                            selectedDay: _selectedDay,
                            pantry: _inventoryItems.map((i) => i.name).toList(),
                            onDayChanged: (i) => setState(() => _selectedDay = i),
                            onNewPlan: () => _generate(members),
                            onGrocery: () => context.push('/grocery'),
                          ),
                        ),
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

  Widget _buildFridgeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload a photo of your fridge or groceries and we\'ll plan around what you already have — '
          'so your grocery list only has what you still need. Or just skip this step.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_fridgeImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(_fridgeImage!, height: 140, width: double.infinity, fit: BoxFit.cover),
          ),
        if (_fridgeImage != null) const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
                onPressed: () => _pickFridge(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
                onPressed: () => _pickFridge(ImageSource.gallery),
              ),
            ),
          ],
        ),
        if (_fridgeImage != null && _fridgeResult == null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: _analyzeFridge, child: const Text('Detect Ingredients')),
          ),
        ],
        if (_fridgeResult != null)
          _fridgeResult!.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ErrorBox(error: e, onRetry: _analyzeFridge),
            ),
            data: (_) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detected ingredients (tap ✕ to remove)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      ..._inventoryItems.map((item) => InputChip(
                            label: Text(item.quantity == null ? item.name : '${item.name} (${item.quantity})'),
                            avatar: item.useSoon ? const Text('⏰') : null,
                            backgroundColor:
                                item.useSoon ? AppColors.secondary.withValues(alpha: 0.12) : null,
                            side: item.useSoon ? const BorderSide(color: AppColors.secondary) : null,
                            onDeleted: () => setState(() => _inventoryItems.remove(item)),
                          )),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('Add item'),
                        onPressed: _addInventoryItem,
                      ),
                    ],
                  ),
                  if (_inventoryItems.any((i) => i.useSoon)) ...[
                    const SizedBox(height: 6),
                    Text('⏰ = use soon, we\'ll prioritize these.',
                        style: TextStyle(fontSize: 12, color: AppColors.secondary, fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- Supporting widgets ----------------

class _StepCard extends StatelessWidget {
  final int number;
  final String title;
  final Widget child;
  final Widget? trailing;
  const _StepCard({required this.number, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary,
                  child: Text('$number',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DayPrefRow extends StatelessWidget {
  final DayPreference pref;
  final String typeLabel;
  final VoidCallback onPickType;
  final void Function(String cuisine, bool selected) onCuisineToggled;

  const _DayPrefRow({
    required this.pref,
    required this.typeLabel,
    required this.onPickType,
    required this.onCuisineToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onPickType,
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(pref.day, style: Theme.of(context).textTheme.titleSmall),
                ),
                Expanded(
                  child: Text(typeLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.primaryDark)),
                ),
                const Icon(Icons.expand_more, size: 22),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: AppVocab.cuisinePreferences.map((c) {
              return SelectableChip(
                label: AppVocab.displayLabel(c),
                selected: pref.cuisinePreferences.contains(c),
                color: AppColors.tertiary,
                onSelected: (sel) => onCuisineToggled(c, sel),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _MealTypeSheet extends StatelessWidget {
  final String currentCode;
  const _MealTypeSheet({required this.currentCode});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Choose meal type', style: Theme.of(context).textTheme.titleLarge),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: kMealTypes.length,
              itemBuilder: (context, i) {
                final m = kMealTypes[i];
                return RadioListTile<String>(
                  value: m.code,
                  groupValue: currentCode,
                  activeColor: AppColors.primary,
                  title: Text(m.label),
                  subtitle: Text(m.description),
                  onChanged: (v) => Navigator.pop(context, v),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanLoading extends StatelessWidget {
  const _PlanLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text('Building your family\'s week…', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('This can take up to a minute.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  final WeeklyPlan plan;
  final int selectedDay;
  final List<String> pantry;
  final ValueChanged<int> onDayChanged;
  final VoidCallback onNewPlan;
  final VoidCallback onGrocery;

  const _PlanView({
    required this.plan,
    required this.selectedDay,
    required this.pantry,
    required this.onDayChanged,
    required this.onNewPlan,
    required this.onGrocery,
  });

  bool _inPantry(List<String> ingredients) {
    final p = pantry.map((e) => e.toLowerCase()).toList();
    return ingredients.any((ing) {
      final i = ing.toLowerCase();
      return p.any((x) => i.contains(x) || x.contains(i));
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = plan.days[selectedDay.clamp(0, plan.days.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your 7-Day Plan', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(plan.days.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SelectableChip(
                  label: plan.days[i].day.substring(0, 3),
                  selected: i == selectedDay,
                  color: AppColors.secondary,
                  onSelected: (_) => onDayChanged(i),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        _MealRow(emoji: '🌅', label: 'Breakfast', meal: day.breakfast, have: _inPantry(day.breakfast.ingredients)),
        _MealRow(emoji: '☀️', label: 'Lunch', meal: day.lunch, have: _inPantry(day.lunch.ingredients)),
        _MealRow(emoji: '🌙', label: 'Dinner', meal: day.dinner, have: _inPantry(day.dinner.ingredients)),
        if (day.snack != null)
          _MealRow(emoji: '🍎', label: 'Snack', meal: day.snack!, have: _inPantry(day.snack!.ingredients)),
        if (plan.notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...plan.notes.map((n) => Text('• $n', style: Theme.of(context).textTheme.bodySmall)),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text('AI-generated suggestions, not medical advice.',
              style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('New Plan'),
                onPressed: onNewPlan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Grocery List'),
                onPressed: onGrocery,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MealRow extends StatelessWidget {
  final String emoji;
  final String label;
  final PlannedMeal meal;
  final bool have;
  const _MealRow({required this.emoji, required this.label, required this.meal, required this.have});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary, letterSpacing: 0.5)),
                      if (have) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('✓ you have some of this',
                              style: TextStyle(fontSize: 10.5, color: AppColors.success, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meal.name, style: Theme.of(context).textTheme.titleSmall),
                  if (meal.ingredients.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(meal.ingredients.join(', '), style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (meal.notes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(meal.notes!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic, color: AppColors.primaryDark)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}