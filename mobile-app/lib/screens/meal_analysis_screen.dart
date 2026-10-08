import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../models/family_member.dart';
import '../models/meal_analysis.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../services/image_saver.dart';
import '../models/nutrient_totals.dart';

class MealAnalysisScreen extends ConsumerStatefulWidget {
  const MealAnalysisScreen({super.key});

  @override
  ConsumerState<MealAnalysisScreen> createState() => _MealAnalysisScreenState();
}

class _MealAnalysisScreenState extends ConsumerState<MealAnalysisScreen> {
  Uint8List? _imageBytes;
  final _notesCtrl = TextEditingController();
  AsyncValue<MealAnalysis>? _result;
  bool _saving = false;
  final GlobalKey _cardKey = GlobalKey();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source, maxWidth: 1024, imageQuality: 80);
    if (x != null) {
      final bytes = await x.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _result = null;
      });
    }
  }

  FamilyMember? _effectiveMember(List<FamilyMember> members) {
    if (members.isEmpty) return null;
    return ref.read(selectedMemberProvider) ?? members.first;
  }

  Future<void> _analyze(FamilyMember member) async {
    if (_imageBytes == null) return;
    setState(() => _result = const AsyncLoading());
    try {
      final analysis = await ref.read(apiProvider).analyzeMeal(_imageBytes!, member);
      if (!mounted) return;
      setState(() => _result = AsyncData(analysis));
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _result = AsyncError(e, st));
    }
  }

  Future<void> _openCorrectMealDialog(MealAnalysis current, FamilyMember member) async {
    // Pre-fill one row per existing detected item, so users edit in place
    final existingRows = current.items.asMap().entries.map((entry) {
      return {
        'index': entry.key,
        'name': TextEditingController(text: entry.value.name),
        'weight': TextEditingController(text: entry.value.weightG.round().toString()),
        'needsReview': entry.value.needsReview,
      };
    }).toList();

    final newRows = <Map<String, dynamic>>[];
    final hasReviewItems = existingRows.any((r) => r['needsReview'] == true);

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Correct Meal'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit detected items or add new ones:',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),

                  ...existingRows.map((row) {
                    final needsReview = row['needsReview'] as bool;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: row['name'] as TextEditingController,
                              style: TextStyle(color: needsReview ? AppColors.danger : null),
                              decoration: InputDecoration(
                                labelText: 'Dish name',
                                labelStyle: TextStyle(color: needsReview ? AppColors.danger : null),
                                enabledBorder: needsReview
                                    ? OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: row['weight'] as TextEditingController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Weight (g)'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  ...newRows.asMap().entries.map((entry) {
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: row['name'] as TextEditingController,
                              decoration: const InputDecoration(labelText: 'New dish name'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: row['weight'] as TextEditingController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Weight (g)'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add new item'),
                    onPressed: () => setDialogState(() => newRows.add(
                        {'name': TextEditingController(), 'weight': TextEditingController()})),
                  ),

                  if (hasReviewItems) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 16, color: AppColors.danger),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Items highlighted in red had low confidence or weren\'t matched — please confirm or correct them.',
                              style: TextStyle(fontSize: 12, color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Re-analyze')),
          ],
        ),
      ),
    );

    if (submitted != true) return;

    final corrections = <ItemCorrection>[
      // Existing items: send a correction only if the user actually changed the name or weight
      for (final row in existingRows)
        if ((row['name'] as TextEditingController).text.trim() != current.items[row['index'] as int].name ||
            double.tryParse((row['weight'] as TextEditingController).text.trim()) !=
                current.items[row['index'] as int].weightG)
          ItemCorrection(
            itemIndex: row['index'] as int,
            name: (row['name'] as TextEditingController).text.trim(),
            weightG: double.tryParse((row['weight'] as TextEditingController).text.trim()),
          ),
      // New items
      for (final row in newRows)
        if ((row['name'] as TextEditingController).text.trim().isNotEmpty)
          ItemCorrection(
            itemIndex: null,
            name: (row['name'] as TextEditingController).text.trim(),
            weightG: double.tryParse((row['weight'] as TextEditingController).text.trim()),
          ),
    ];

    if (corrections.isEmpty) return;

    setState(() => _result = const AsyncLoading());
    try {
      final updated = await ref.read(apiProvider).correctMeal(current, corrections, member);
      if (!mounted) return;
      setState(() => _result = AsyncData(updated));
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _result = AsyncError(e, st));
    }
  }

  Future<void> _loveIt(MealAnalysis analysis) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Save this meal card?'),
        content: const Text('Would you like to save this result to your device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, thanks')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, save')),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _saving = true);
      final bytes = await _captureCardImage();
      if (bytes != null) {
        final message = await saveImageBytes(
          bytes, 'nutriwise_meal_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      }
      if (_imageBytes != null) {
        await LocalStorageService.saveMealRecord(_imageBytes!, analysis);
      }
      if (!mounted) return;
      setState(() => _saving = false);
    }

    if (!mounted) return;
    context.go('/dashboard');
  }

  Future<Uint8List?> _captureCardImage() async {
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              const AppBrandBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📸 Nutrient Analyzer', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Snap a photo of a meal to see its nutrients',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),

                      _ImagePickerCard(imageBytes: _imageBytes, onPick: _pickImage),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'e.g. extra spicy, homemade',
                          prefixIcon: Icon(Icons.edit_note),
                        ),
                      ),
                      const SizedBox(height: 16),

                      membersAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (members) {
                          final member = _effectiveMember(members);
                          if (member == null) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoBanner(
                                  text: 'Add a family member first so we can personalize this analysis.',
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          }
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Analyze Meal'),
                              onPressed: _imageBytes == null ? null : () => _analyze(member),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      if (_result != null)
                        _result!.when(
                          loading: () => const _LoadingView(),
                          error: (e, _) => _ErrorView(
                            error: e,
                            onRetry: () {
                              final members = membersAsync.maybeWhen(data: (d) => d, orElse: () => <FamilyMember>[]);
                              final member = _effectiveMember(members);
                              if (member != null) _analyze(member);
                            },
                          ),
                          data: (analysis) => _ResultCard(
                            cardKey: _cardKey,
                            analysis: analysis,
                            imageBytes: _imageBytes,
                            saving: _saving,
                            onCorrectMeal: () {
                              final members = membersAsync.maybeWhen(data: (d) => d, orElse: () => <FamilyMember>[]);
                              final member = _effectiveMember(members);
                              if (member != null) _openCorrectMealDialog(analysis, member);
                            },
                            onLoveIt: () => _loveIt(analysis),
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

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.tertiary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _ImagePickerCard extends StatelessWidget {
  final Uint8List? imageBytes;
  final void Function(ImageSource) onPick;
  const _ImagePickerCard({required this.imageBytes, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          if (imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(imageBytes!, height: 180, width: double.infinity, fit: BoxFit.cover),
            )
          else
            Container(
              height: 140,
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
              child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 48))),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                  onPressed: () => onPick(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                  onPressed: () => onPick(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 12),
          Text('Analyzing your meal…', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isApiError = error is ApiException;
    final message = isApiError ? (error as ApiException).message : 'Something went wrong. Please try again.';
    final canRetry = isApiError ? (error as ApiException).retry : true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: const TextStyle(color: AppColors.danger))),
            ],
          ),
          if (canRetry) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final GlobalKey cardKey;
  final MealAnalysis analysis;
  final Uint8List? imageBytes;
  final bool saving;
  final VoidCallback onCorrectMeal;
  final VoidCallback onLoveIt;

  const _ResultCard({
    required this.cardKey,
    required this.analysis,
    required this.imageBytes,
    required this.saving,
    required this.onCorrectMeal,
    required this.onLoveIt,
  });

  static const _nutrientLabels = ['Protein', 'Fiber', 'Iron', 'Calcium', 'Vitamin A', 'Vitamin C'];

  @override
  Widget build(BuildContext context) {
    final presentNutrients = _nutrientLabels.where((k) => !analysis.missingNutrients.contains(k)).toList();
    final hasReviewItems = analysis.items.any((i) => i.needsReview);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Everything captured for the saved image lives inside this boundary,
            // with equal padding on all sides so the photo never touches the edge.
            RepaintBoundary(
              key: cardKey,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(imageBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Detected Foods', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: analysis.items.map((item) {
                        return Chip(
                          label: Text(
                            '${item.name} (${item.weightG.round()}g, ${item.nutrients.calories.round()} kcal)',
                            style: item.needsReview ? const TextStyle(color: AppColors.danger) : null,
                          ),
                          backgroundColor: item.needsReview ? AppColors.danger.withValues(alpha: 0.08) : null,
                          side: item.needsReview
                              ? const BorderSide(color: AppColors.danger, width: 1.2)
                              : BorderSide(color: Colors.grey.shade300),
                          avatar: item.needsReview
                              ? const Icon(Icons.warning_amber, size: 16, color: AppColors.danger)
                              : null,
                        );
                      }).toList(),
                    ),
                    if (hasReviewItems) ...[
                      const SizedBox(height: 6),
                      Text(
                        '⚠️ Items in red had low confidence or weren\'t matched in our database — use Correct Meal to fix them.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.danger, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const Divider(height: 28),

                    Text('Nutrients Present', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: presentNutrients.map((n) => _NutrientChip(label: n, positive: true)).toList(),
                    ),
                    if (analysis.missingNutrients.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('Missing Nutrients', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6, runSpacing: 6,
                        children: analysis.missingNutrients.map((n) => _NutrientChip(label: n, positive: false)).toList(),
                      ),
                    ],

                    if (analysis.suggestions.isNotEmpty) ...[
                      const Divider(height: 28),
                      Text('💡 Suggestions', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...analysis.suggestions.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• $s', style: Theme.of(context).textTheme.bodySmall),
                          )),
                    ],

                    const SizedBox(height: 18),
                    _SummaryBar(total: analysis.total),

                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        'AI-generated suggestions, not medical advice.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Correct Meal'),
                    onPressed: onCorrectMeal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: saving
                        ? const SizedBox(height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.favorite_border),
                    label: const Text('Love It'),
                    onPressed: saving ? null : onLoveIt,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final NutrientTotals total;
  const _SummaryBar({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryColumn(label: 'CALORIES', value: '${total.calories.round()} Kcal'),
          _SummaryColumn(label: 'PROTEIN', value: '${total.proteinG.round()} g'),
          _SummaryColumn(label: 'CARBS', value: '${total.carbsG.round()} g'),
          _SummaryColumn(label: 'FAT', value: '${total.fatG.round()} g'),
        ],
      ),
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _NutrientChip extends StatelessWidget {
  final String label;
  final bool positive;
  const _NutrientChip({required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(positive ? Icons.check_circle : Icons.warning_amber, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}