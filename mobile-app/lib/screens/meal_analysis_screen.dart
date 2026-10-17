import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../models/family_member.dart';
import '../models/meal_analysis.dart';
import '../models/nutrient_totals.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../services/image_saver.dart';
import '../services/local_storage_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';
import '../widgets/error_box.dart';
import '../widgets/photo_picker.dart';

String _nameKey(String name) => name.trim().toLowerCase();

/// Red = the AI wasn't sure AND the user hasn't confirmed or corrected it yet.
bool _isFlagged(MealItem i, Set<String> reviewed) =>
    i.needsReview && !i.userCorrected && !reviewed.contains(_nameKey(i.name));

/// One editable row in the Correct Meal dialog.
class _CorrectionRow {
  final int? index; // position in the detected list; null for a new item
  final MealItem? original;
  final bool flagged; // was red when the dialog opened
  bool confirmed = false; // the user ticked it or edited it
  final TextEditingController nameCtrl;
  final TextEditingController weightCtrl;

  _CorrectionRow({
    this.index,
    this.original,
    this.flagged = false,
    required this.nameCtrl,
    required this.weightCtrl,
  });

  bool get stillRed => flagged && !confirmed;
}

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

  /// Lower-cased names of items the user has confirmed or corrected.
  final Set<String> _reviewed = {};

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final bytes = await pickPhoto(context, source);
    if (bytes == null || !mounted) return;
    setState(() {
      _imageBytes = bytes;
      _result = null; // clear any previous result on a new photo
      _reviewed.clear();
    });
  }

  FamilyMember? _effectiveMember(List<FamilyMember> members) {
    if (members.isEmpty) return null;
    return ref.read(selectedMemberProvider) ?? members.first;
  }

  Future<void> _analyze(FamilyMember member) async {
    if (_imageBytes == null) return;
    setState(() {
      _result = const AsyncLoading();
      _reviewed.clear();
    });
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
    // One pre-filled row per detected item, so users edit in place
    final rows = <_CorrectionRow>[
      for (final e in current.items.asMap().entries)
        _CorrectionRow(
          index: e.key,
          original: e.value,
          flagged: _isFlagged(e.value, _reviewed),
          nameCtrl: TextEditingController(text: e.value.name),
          weightCtrl: TextEditingController(text: e.value.weightG.round().toString()),
        ),
    ];
    final newRows = <_CorrectionRow>[];

    final maxW = MediaQuery.of(context).size.width * 0.8;
    final dialogWidth = maxW < 420 ? maxW : 420.0;
    final headerStyle = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700);

    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: 1.4),
        );

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final stillRed = rows.where((r) => r.stillRed).length;
          final anyFlagged = rows.any((r) => r.flagged);

          void markConfirmed(_CorrectionRow r) {
            if (r.flagged && !r.confirmed) setDialogState(() => r.confirmed = true);
          }

          Widget existingRow(_CorrectionRow r) {
            final red = r.stillRed;
            final ok = r.flagged && r.confirmed;
            final InputBorder? rowBorder =
                red ? border(AppColors.danger) : (ok ? border(AppColors.success) : null);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: r.nameCtrl,
                      onChanged: (_) => markConfirmed(r), // editing counts as reviewing
                      style: TextStyle(color: red ? AppColors.danger : null),
                      decoration: InputDecoration(
                        hintText: 'Dish name',
                        enabledBorder: rowBorder,
                        focusedBorder: rowBorder,
                        suffixIcon: r.flagged
                            ? IconButton(
                                tooltip: r.confirmed ? 'Confirmed' : 'Mark as correct',
                                icon: Icon(
                                  r.confirmed ? Icons.check_circle : Icons.check_circle_outline,
                                  color: r.confirmed ? AppColors.success : AppColors.danger,
                                ),
                                onPressed: () => setDialogState(() => r.confirmed = !r.confirmed),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: r.weightCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => markConfirmed(r),
                      decoration: const InputDecoration(hintText: 'grams'),
                    ),
                  ),
                ],
              ),
            );
          }

          Widget newRow(_CorrectionRow r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: r.nameCtrl,
                        decoration: const InputDecoration(hintText: 'New dish name'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: r.weightCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'grams (optional)'),
                      ),
                    ),
                  ],
                ),
              );

          Widget note(Color color, IconData icon, String text) => Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
                  ],
                ),
              );

          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: const Text('Correct Meal'),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Edit detected items or add new ones.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 14),
                    // Column headers sit above the boxes, so nothing floats over a border
                    Row(
                      children: [
                        Expanded(flex: 3, child: Text('Dish name', style: headerStyle)),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('Weight (g)', style: headerStyle)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...rows.map(existingRow),
                    ...newRows.map(newRow),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add new item'),
                      onPressed: () => setDialogState(() => newRows.add(_CorrectionRow(
                            nameCtrl: TextEditingController(),
                            weightCtrl: TextEditingController(),
                          ))),
                    ),
                    if (stillRed > 0)
                      note(
                        AppColors.danger,
                        Icons.warning_amber,
                        '$stillRed item${stillRed > 1 ? 's' : ''} in red need a look. '
                        'Tap ✓ if it\'s correct, or edit it.',
                      )
                    else if (anyFlagged)
                      note(AppColors.success, Icons.check_circle, 'All items confirmed.'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Re-analyze')),
            ],
          );
        },
      ),
    );

    if (submitted != true) return;

    // Only send what actually changed
    final corrections = <ItemCorrection>[];
    for (final r in rows) {
      final old = r.original!;
      final newName = r.nameCtrl.text.trim();
      final newWeight = double.tryParse(r.weightCtrl.text.trim());
      final nameChanged = newName.isNotEmpty && newName != old.name;
      final weightChanged =
          newWeight != null && newWeight > 0 && newWeight != old.weightG.roundToDouble();
      if (nameChanged || weightChanged) {
        corrections.add(ItemCorrection(
          itemIndex: r.index,
          name: newName.isEmpty ? old.name : newName,
          weightG: weightChanged ? newWeight : null, // null = keep the old weight
        ));
      }
    }
    for (final r in newRows) {
      final name = r.nameCtrl.text.trim();
      if (name.isEmpty) continue;
      corrections.add(ItemCorrection(
        itemIndex: null,
        name: name,
        weightG: double.tryParse(r.weightCtrl.text.trim()),
      ));
    }

    // Everything the user ticked, edited or added counts as reviewed
    final newlyReviewed = <String>{};
    for (final r in rows) {
      final edited = corrections.any((c) => c.itemIndex == r.index);
      if (r.confirmed || edited) newlyReviewed.add(_nameKey(r.nameCtrl.text));
    }
    for (final r in newRows) {
      if (r.nameCtrl.text.trim().isNotEmpty) newlyReviewed.add(_nameKey(r.nameCtrl.text));
    }

    if (corrections.isEmpty) {
      // Nothing to recalculate: just clear the red marks on what was confirmed
      if (newlyReviewed.isNotEmpty) setState(() => _reviewed.addAll(newlyReviewed));
      return;
    }

    setState(() => _result = const AsyncLoading());
    try {
      final updated = await ref.read(apiProvider).correctMeal(current, corrections, member);
      if (!mounted) return;
      setState(() {
        _reviewed.addAll(newlyReviewed);
        _result = AsyncData(updated);
      });
    } catch (e) {
      if (!mounted) return;
      // Keep the previous result on screen so nothing is lost, and say what went wrong
      setState(() => _result = AsyncData(current));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException
              ? e.message
              : 'We couldn\'t apply your changes. Please try again.'),
        ),
      );
    }
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
          bytes,
          'nutriwise_meal_${DateTime.now().millisecondsSinceEpoch}.png',
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

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final members = membersAsync.maybeWhen(data: (d) => d, orElse: () => <FamilyMember>[]);
    final member = _effectiveMember(members);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBrandBar(backTo: '/dashboard', confirmLeave: _result is AsyncData),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📸 Nutrient Analyzer', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Snap a photo of a meal to see its nutrients',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
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
                        data: (_) {
                          if (member == null) {
                            return const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: _InfoBanner(
                                text: 'Add a family member first so we can personalize this analysis.',
                              ),
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
                          error: (e, _) => ErrorBox(
                            error: e,
                            onRetry: member == null ? null : () => _analyze(member),
                          ),
                          data: (analysis) => _ResultCard(
                            cardKey: _cardKey,
                            analysis: analysis,
                            imageBytes: _imageBytes,
                            reviewed: _reviewed,
                            saving: _saving,
                            onCorrectMeal: () {
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
              decoration:
                  BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
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
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text('Analyzing your meal…', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final GlobalKey cardKey;
  final MealAnalysis analysis;
  final Uint8List? imageBytes;
  final Set<String> reviewed;
  final bool saving;
  final VoidCallback onCorrectMeal;
  final VoidCallback onLoveIt;

  const _ResultCard({
    required this.cardKey,
    required this.analysis,
    required this.imageBytes,
    required this.reviewed,
    required this.saving,
    required this.onCorrectMeal,
    required this.onLoveIt,
  });

  static const _nutrientLabels = ['Protein', 'Fiber', 'Iron', 'Calcium', 'Vitamin A', 'Vitamin C'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final presentNutrients =
        _nutrientLabels.where((k) => !analysis.missingNutrients.contains(k)).toList();
    final flaggedCount = analysis.items.where((i) => _isFlagged(i, reviewed)).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Everything captured for the saved image lives inside this boundary
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
                        child: Image.memory(imageBytes!,
                            height: 160, width: double.infinity, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Detected Foods', style: t.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: analysis.items.map((item) {
                        final flagged = _isFlagged(item, reviewed);
                        final verified = item.userCorrected || reviewed.contains(_nameKey(item.name));
                        return Chip(
                          label: Text(
                            '${item.name} (${item.weightG.round()}g, ${item.nutrients.calories.round()} kcal)',
                            style: flagged ? const TextStyle(color: AppColors.danger) : null,
                          ),
                          backgroundColor: flagged ? AppColors.danger.withValues(alpha: 0.08) : null,
                          side: flagged
                              ? const BorderSide(color: AppColors.danger, width: 1.2)
                              : BorderSide(color: Colors.grey.shade300),
                          avatar: flagged
                              ? const Icon(Icons.warning_amber, size: 16, color: AppColors.danger)
                              : (verified
                                  ? const Icon(Icons.check_circle, size: 16, color: AppColors.success)
                                  : null),
                        );
                      }).toList(),
                    ),
                    if (flaggedCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '⚠️ Items in red had low confidence or weren\'t matched in our database — '
                        'use Correct Meal to confirm or fix them.',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.danger, fontStyle: FontStyle.italic),
                      ),
                    ],
                    if (analysis.unmatchedItems.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'We couldn\'t match these in our nutrition database, so their values may be '
                        'estimates: ${analysis.unmatchedItems.join(', ')}.',
                        style: t.bodySmall?.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const Divider(height: 28),
                    Text('Nutrients Present', style: t.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          presentNutrients.map((n) => _NutrientChip(label: n, positive: true)).toList(),
                    ),
                    if (analysis.missingNutrients.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('Missing Nutrients', style: t.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: analysis.missingNutrients
                            .map((n) => _NutrientChip(label: n, positive: false))
                            .toList(),
                      ),
                    ],
                    if (analysis.suggestions.isNotEmpty) ...[
                      const Divider(height: 28),
                      Text('💡 Suggestions', style: t.titleSmall),
                      const SizedBox(height: 8),
                      ...analysis.suggestions.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('• $s', style: t.bodySmall),
                          )),
                    ],
                    const SizedBox(height: 18),
                    _SummaryBar(total: analysis.total),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        'AI-generated suggestions, not medical advice.',
                        style: t.bodySmall,
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
                        ? const SizedBox(
                            height: 16,
                            width: 16,
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
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
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
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.3)),
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
      decoration:
          BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
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