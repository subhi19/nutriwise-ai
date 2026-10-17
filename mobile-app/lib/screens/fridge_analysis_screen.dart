import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants.dart';
import '../core/suggestion_quota.dart';
import '../core/theme.dart';
import '../models/family_member.dart';
import '../models/fridge_inventory.dart';
import '../models/recipe.dart';
import '../providers/providers.dart';
import '../services/local_storage_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';
import '../widgets/error_box.dart';
import '../widgets/recipe_cards.dart';
import '../widgets/recipe_export_card.dart';
import '../widgets/save_card_dialog.dart';
import '../widgets/photo_picker.dart';

class FridgeAnalysisScreen extends ConsumerStatefulWidget {
  const FridgeAnalysisScreen({super.key});

  @override
  ConsumerState<FridgeAnalysisScreen> createState() => _FridgeAnalysisScreenState();
}

class _FridgeAnalysisScreenState extends ConsumerState<FridgeAnalysisScreen> {
  Uint8List? _image;
  AsyncValue<FridgeInventory>? _fridge;
  List<InventoryItem> _items = [];
  AsyncValue<RecipeSuggestions>? _recipes;
  final _quota = SuggestionQuota();
  bool _saving = false;

  Future<void> _pick(ImageSource source) async {
    final bytes = await pickPhoto(context, source);
    if (bytes == null || !mounted) return;
    setState(() {
      _image = bytes;
      _fridge = null;
      _items = [];
      _recipes = null;
      _quota.reset(); // a new photo is a fresh start
    });
  }

  Future<void> _detect() async {
    if (_image == null) return;
    setState(() => _fridge = const AsyncLoading());
    try {
      final inv = await ref.read(apiProvider).analyzeFridge(_image!);
      if (!mounted) return;
      setState(() {
        _fridge = AsyncData(inv);
        _items = List.of(inv.items);
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _fridge = AsyncError(e, st));
    }
  }

  Future<void> _addItem() async {
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
      setState(() => _items.add(InventoryItem(name: name)));
    }
  }

  Future<void> _suggest(List<FamilyMember> family) async {
    if (_items.isEmpty || family.isEmpty) return;
    if (!_quota.canGenerate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You\'ve used all your new suggestions.')),
      );
      return;
    }
    setState(() => _recipes = const AsyncLoading());
    try {
      final r = await ref
          .read(apiProvider)
          .suggestRecipes(FridgeInventory(items: List.of(_items)), family);
      if (!mounted) return;
      setState(() {
        _quota.recordSuccess();
        _recipes = AsyncData(r);
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _recipes = AsyncError(e, st));
    }
  }

  List<String> _allergies(List<FamilyMember> family) => family
      .expand((m) => [...m.allergies, ...m.otherAllergies])
      .where((a) => a.trim().isNotEmpty)
      .map(AppVocab.displayLabel)
      .toSet()
      .toList();

  Future<void> _loveIt(RecipeSuggestions r, List<FamilyMember> family) async {
    setState(() => _saving = true);
    final saved = await confirmAndSaveCard(
      context,
      title: 'Save these recipes?',
      message: 'Would you like to save these recipe ideas as a card on your device?',
      card: RecipeExportCard(
        suggestions: r,
        imageBytes: _image,
        ingredients: _items.map((i) => i.name).toList(),
        allergiesAvoided: _allergies(family),
      ),
      filenamePrefix: 'nutriwise_recipes',
    );
    if (saved) {
      await LocalStorageService.saveRecipes(r);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final members =
        ref.watch(membersProvider).maybeWhen(data: (d) => d, orElse: () => <FamilyMember>[]);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBrandBar(backTo: '/dashboard', confirmLeave: _recipes is AsyncData),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🧊 Home Inventory', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Cook with what you already have',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Upload a photo of your fridge or groceries',
                                  style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 12),
                              if (_image != null) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.memory(_image!,
                                      height: 160, width: double.infinity, fit: BoxFit.cover),
                                ),
                                const SizedBox(height: 10),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.photo_camera_outlined),
                                      label: const Text('Camera'),
                                      onPressed: () => _pick(ImageSource.camera),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.photo_library_outlined),
                                      label: const Text('Gallery'),
                                      onPressed: () => _pick(ImageSource.gallery),
                                    ),
                                  ),
                                ],
                              ),
                              if (_image != null && _fridge == null) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.search),
                                    label: const Text('Detect Ingredients'),
                                    onPressed: _detect,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_fridge != null)
                        _fridge!.when(
                          loading: () => const _Loading(text: 'Looking at your groceries…'),
                          error: (e, _) => ErrorBox(error: e, onRetry: _detect),
                          data: (_) => _IngredientsCard(
                            items: _items,
                            onRemove: (i) => setState(() => _items.remove(i)),
                            onAdd: _addItem,
                            canSuggest: _items.isNotEmpty &&
                                members.isNotEmpty &&
                                _recipes is! AsyncLoading &&
                                _quota.canGenerate,
                            noMembers: members.isEmpty,
                            onSuggest: () => _suggest(members),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (_recipes != null)
                        _recipes!.when(
                          loading: () => const _Loading(text: 'Finding recipes with your ingredients…'),
                          error: (e, _) => ErrorBox(error: e, onRetry: () => _suggest(members)),
                          data: (r) => RecipeCards(
                            suggestions: r,
                            allergiesAvoided: _allergies(members),
                            actions: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.refresh),
                                        label: Text(_quota.canGenerate
                                            ? 'New Ideas (${_quota.newLeft} left)'
                                            : 'No new ideas left'),
                                        onPressed: _quota.canGenerate ? () => _suggest(members) : null,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: _saving
                                            ? const SizedBox(
                                                height: 16,
                                                width: 16,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2, color: Colors.white))
                                            : const Icon(Icons.favorite_border),
                                        label: const Text('Love It'),
                                        onPressed: _saving ? null : () => _loveIt(r, members),
                                      ),
                                    ),
                                  ],
                                ),
                                if (!_quota.canGenerate)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                        'You\'ve used all your new ideas. Upload a new photo to start over.',
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
}

class _Loading extends StatelessWidget {
  final String text;
  const _Loading({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text(text),
          ],
        ),
      ),
    );
  }
}

class _IngredientsCard extends StatelessWidget {
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onRemove;
  final VoidCallback onAdd;
  final bool canSuggest;
  final bool noMembers;
  final VoidCallback onSuggest;

  const _IngredientsCard({
    required this.items,
    required this.onRemove,
    required this.onAdd,
    required this.canSuggest,
    required this.noMembers,
    required this.onSuggest,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detected ingredients', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Tap ✕ to remove anything wrong, or add what we missed.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...items.map((item) => InputChip(
                      label: Text(item.quantity == null ? item.name : '${item.name} (${item.quantity})'),
                      avatar: item.useSoon ? const Text('⏰') : null,
                      backgroundColor: item.useSoon ? AppColors.secondary.withValues(alpha: 0.12) : null,
                      side: item.useSoon ? const BorderSide(color: AppColors.secondary) : null,
                      onDeleted: () => onRemove(item),
                    )),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Add item'),
                  onPressed: onAdd,
                ),
              ],
            ),
            if (items.any((i) => i.useSoon)) ...[
              const SizedBox(height: 8),
              Text('⏰ = use soon, we\'ll prioritize these.',
                  style: TextStyle(fontSize: 12, color: AppColors.secondary, fontStyle: FontStyle.italic)),
            ],
            if (noMembers) ...[
              const SizedBox(height: 8),
              Text('Add a family member first so we can avoid their allergens.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Suggest Recipes'),
                onPressed: canSuggest ? onSuggest : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}