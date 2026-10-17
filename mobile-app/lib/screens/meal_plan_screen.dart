import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants.dart';
import '../core/suggestion_quota.dart';
import '../core/theme.dart';
import '../models/day_preference.dart';
import '../models/family_member.dart';
import '../models/fridge_inventory.dart';
import '../models/meal_type.dart';
import '../models/meal_plan.dart';
import '../providers/providers.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';
import '../widgets/error_box.dart';
import '../widgets/plan_export_card.dart';
import '../widgets/plan_view.dart';
import '../widgets/save_card_dialog.dart';
import '../widgets/selectable_chip.dart';
import '../widgets/photo_picker.dart';

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

  // Step 3: per-day preferences + one note for the whole week
  List<DayPreference> _prefs = defaultWeekPreferences();
  final _notesCtrl = TextEditingController();

  // Result
  AsyncValue<WeeklyPlan>? _planResult;
  int _selectedDay = 0;

  // Limit: the first plan plus 2 new ones
  final _quota = SuggestionQuota();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ---------- Step 1: fridge photo ----------

  Future<void> _pickFridge(ImageSource source) async {
    final bytes = await pickPhoto(context, source);
    if (bytes == null || !mounted) return;
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

  // ---------- Step 3: preferences ----------

  Future<void> _pickMealType(int index) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MealTypeSheet(initial: _prefs[index].mealTypeCodes),
    );
    if (selected != null && selected.isNotEmpty) {
      setState(() => _prefs[index] = _prefs[index].copyWith(mealTypeCodes: List.of(selected)));
    }
  }

  void _applyMondayToAll() {
    final first = _prefs.first;
    setState(() {
      _prefs = _prefs
          .map((d) => d.copyWith(
                mealTypeCodes: List.of(first.mealTypeCodes),
                cuisinePreferences: List.of(first.cuisinePreferences),
              ))
          .toList();
    });
  }

  // ---------- Generate ----------

  Future<void> _generate(List<FamilyMember> members) async {
    // Limit check comes first
    if (!_quota.canGenerate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You\'ve used all your new-plan suggestions.')),
      );
      return;
    }

    final family = members.where((m) => !_excludedMembers.contains(m.id ?? m.name)).toList();
    if (family.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one family member.')),
      );
      return;
    }

    final inventory = _inventoryItems.isEmpty ? null : FridgeInventory(items: List.of(_inventoryItems));
    final weekNote = _notesCtrl.text.trim();
    final prefsToSend = _prefs.map((d) => d.copyWith(notes: weekNote)).toList();

    setState(() {
      _planResult = const AsyncLoading();
      _selectedDay = 0;
    });
    try {
      final plan = await ref.read(apiProvider).generateMealPlan(family, inventory, prefsToSend);
      if (!mounted) return;
      // Carry everything forward for the Grocery List screen
      ref.read(currentPlanProvider.notifier).state = plan;
      ref.read(fridgeInventoryProvider.notifier).state = inventory;
      ref.read(planFamilyProvider.notifier).state = family;
      setState(() {
        _quota.recordSuccess(); // only successful plans count towards the limit
        _planResult = AsyncData(plan);
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _planResult = AsyncError(e, st));
    }
  }

  // ---------- Grocery List: offer to save the plan card first ----------

  Future<void> _onGroceryTapped(WeeklyPlan plan) async {
    final familyNames = ref.read(planFamilyProvider).map((m) => m.name).toList();
    await confirmAndSaveCard(
      context,
      title: 'Save this plan?',
      message: 'Would you like to save your 7-day plan as a card on your device?',
      card: PlanExportCard(plan: plan, familyNames: familyNames),
      filenamePrefix: 'nutriwise_meal_plan',
    );
    if (!mounted) return;
    context.push('/grocery'); // Yes or No, we continue to the grocery list
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
              AppBrandBar(backTo: '/dashboard', confirmLeave: _planResult is AsyncData),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📅 Meal Planner', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('A personalized 7-day plan for your family',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),

                      _StepCard(
                        number: 1,
                        title: 'Groceries at home? (optional)',
                        child: _buildFridgeStep(),
                      ),

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

                      _StepCard(
                        number: 3,
                        title: 'Plan the week',
                        trailing: TextButton(
                          onPressed: _applyMondayToAll,
                          child: const Text('Same as Monday'),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...List.generate(_prefs.length, (i) {
                              final pref = _prefs[i];
                              return _DayPrefRow(
                                pref: pref,
                                onPickType: () => _pickMealType(i),
                                onCuisineToggled: (c, sel) {
                                  final list = List<String>.from(pref.cuisinePreferences);
                                  sel ? list.add(c) : list.remove(c);
                                  setState(() => _prefs[i] = pref.copyWith(cuisinePreferences: list));
                                },
                              );
                            }),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _notesCtrl,
                              minLines: 2,
                              maxLines: 3,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: 'Ask Gemini AI (optional)',
                                hintText: 'e.g. light dinners, high protein, no spicy food',
                                prefixIcon: Icon(Icons.edit_note),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generate My Plan'),
                          onPressed: (members.isEmpty || _planResult is AsyncLoading || !_quota.canGenerate)
                              ? null
                              : () => _generate(members),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_planResult != null)
                        _planResult!.when(
                          loading: () => const _PlanLoading(),
                          error: (e, _) => ErrorBox(error: e, onRetry: () => _generate(members)),
                          data: (plan) => PlanView(
                            plan: plan,
                            selectedDay: _selectedDay,
                            pantry: _inventoryItems.map((i) => i.name).toList(),
                            onDayChanged: (i) => setState(() => _selectedDay = i),
                            actions: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.refresh),
                                        label: Text(_quota.canGenerate
                                            ? 'New Plan (${_quota.newLeft} left)'
                                            : 'No new plans left'),
                                        onPressed: _quota.canGenerate ? () => _generate(members) : null,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.shopping_cart_outlined),
                                        label: const Text('Grocery List'),
                                        onPressed: () => _onGroceryTapped(plan),
                                      ),
                                    ),
                                  ],
                                ),
                                if (!_quota.canGenerate)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('You\'ve used all your new-plan suggestions.',
                                        style: Theme.of(context).textTheme.bodySmall),
                                  ),
                              ],
                            ),
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
                    spacing: 8,
                    runSpacing: 8,
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
                        style: TextStyle(
                            fontSize: 12, color: AppColors.secondary, fontStyle: FontStyle.italic)),
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
                ?trailing,
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
  final VoidCallback onPickType;
  final void Function(String cuisine, bool selected) onCuisineToggled;

  const _DayPrefRow({
    required this.pref,
    required this.onPickType,
    required this.onCuisineToggled,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabels = pref.mealTypeCodes.map((c) => mealTypeByCode(c).label).join(' + ');
    final cuisineFull = pref.cuisinePreferences.length >= kMaxCuisines;

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
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 100),
                  child: Text(pref.day,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(typeLabels,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.expand_more, size: 22),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Cuisine (up to $kMaxCuisines)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: AppVocab.cuisinePreferences.map((c) {
              final selected = pref.cuisinePreferences.contains(c);
              return SelectableChip(
                label: AppVocab.displayLabel(c),
                selected: selected,
                enabled: selected || !cuisineFull,
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

class _MealTypeSheet extends StatefulWidget {
  final List<String> initial;
  const _MealTypeSheet({required this.initial});

  @override
  State<_MealTypeSheet> createState() => _MealTypeSheetState();
}

class _MealTypeSheetState extends State<_MealTypeSheet> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('Choose meal type', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pick up to $kMaxMealTypes  ·  ${_selected.length}/$kMaxMealTypes selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: kMealTypes.length,
              itemBuilder: (context, i) {
                final m = kMealTypes[i];
                final checked = _selected.contains(m.code);
                final locked = !checked && _selected.length >= kMaxMealTypes;
                return CheckboxListTile(
                  value: checked,
                  activeColor: AppColors.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(m.label),
                  subtitle: Text(m.description),
                  onChanged: locked
                      ? null
                      : (v) => setState(() {
                            v == true ? _selected.add(m.code) : _selected.remove(m.code);
                          }),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
                child: const Text('Done'),
              ),
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