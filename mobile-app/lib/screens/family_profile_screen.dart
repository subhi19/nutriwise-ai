import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/family_member.dart';
import '../providers/providers.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';
import '../widgets/screen_heading.dart';
import '../widgets/selectable_chip.dart';

class FamilyProfileScreen extends ConsumerWidget {
  const FamilyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              const AppBrandBar(),
              const ScreenHeading(
                emoji: '👨‍👩‍👧‍👦',
                title: 'Your Family',
                subtitle: 'Add everyone you\'re planning meals for',
              ),
              Expanded(
                child: membersAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Failed to load: $e')),
                  data: (members) => members.isEmpty
                      ? _EmptyState(onAdd: () => _openMemberForm(context))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          itemCount: members.length,
                          itemBuilder: (context, i) => _MemberCard(member: members[i]),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: membersAsync.maybeWhen(
        data: (members) => members.isEmpty
            ? null // No FAB until the first member exists
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => context.go('/dashboard'),
                    child: const Text('Continue'),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.extended(
                    onPressed: () => _openMemberForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Member'),
                  ),
                ],
              ),
        orElse: () => null,
      ),
    );
  }

  void _openMemberForm(BuildContext context, {FamilyMember? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // force the explicit close button, so changes aren't lost by an accidental tap-outside
      enableDrag: false,
      builder: (_) => _MemberFormSheet(existing: existing),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🏠', style: TextStyle(fontSize: 52))),
            ),
            const SizedBox(height: 20),
            Text('No family members yet',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Add your family so we can personalize meals for everyone — kids, adults, and grandparents alike.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Member'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends ConsumerWidget {
  final FamilyMember member;
  const _MemberCard({required this.member});

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _MemberFormSheet(existing: member),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ageStyle = AgeGroupStyle.forAge(member.age);
    final prefColor = FoodPrefStyle.colorFor(member.foodPreference);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openEdit(context), // tapping the card/name also opens edit
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: ageStyle.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(ageStyle.emoji, style: const TextStyle(fontSize: 28))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${member.age} yrs', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        _Badge(
                          color: prefColor,
                          label:
                              '${FoodPrefStyle.emojiFor(member.foodPreference)} ${AppVocab.displayLabel(member.foodPreference)}',
                        ),
                        if (member.allergies.isNotEmpty)
                          _Badge(
                            color: AppColors.danger,
                            label: '⚠️ ${member.allergies.length} allergen${member.allergies.length > 1 ? 's' : ''}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                tooltip: 'Edit',
                onPressed: () => _openEdit(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
                tooltip: 'Delete',
                onPressed: () async {
                  await ref.read(apiProvider).deleteMember(member.id!);
                  ref.invalidate(membersProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final String label;
  const _Badge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _MemberFormSheet extends ConsumerStatefulWidget {
  final FamilyMember? existing;
  const _MemberFormSheet({this.existing});

  @override
  ConsumerState<_MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends ConsumerState<_MemberFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _otherAllergyCtrl;

  String? _gender;
  String? _foodPref;
  final Set<String> _allergies = {};
  final Set<String> _cuisines = {};

  bool _saving = false;
  bool _submitted = false; // show validation errors only after a Save attempt
  bool _dirty = false;     // tracks unsaved changes, for the close-confirmation

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _ageCtrl = TextEditingController(text: m?.age.toString() ?? '');
    _otherAllergyCtrl = TextEditingController();

    _nameCtrl.addListener(_markDirty);
    _ageCtrl.addListener(_markDirty);
    _otherAllergyCtrl.addListener(_markDirty);

    if (m != null) {
      _gender = m.gender;
      _foodPref = m.foodPreference;
      _allergies.addAll(m.allergies.where((a) => AppVocab.allergies.contains(a)));
      _otherAllergyCtrl.text = m.otherAllergies.join(', ');
      if (m.cuisinePreferences.isEmpty) {
        _cuisines.add('any');
      } else {
        _cuisines.addAll(m.cuisinePreferences);
      }
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _otherAllergyCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Changes you\'ve made won\'t be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.existing == null ? '✨ Add Family Member' : '✏️ Edit Family Member',
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: _handleClose,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name *', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) =>
                    (v == null || v.trim().length < 2) ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age *', prefixIcon: Icon(Icons.cake_outlined)),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 100) return 'Enter a valid age';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text('Gender *', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Male', 'Female', 'Other'].map((g) {
                  return SelectableChip(
                    label: g,
                    selected: _gender == g,
                    color: AppColors.primary,
                    onSelected: (_) => setState(() { _gender = g; _dirty = true; }),
                  );
                }).toList(),
              ),
              if (_submitted && _gender == null)
                const _FieldError('Please select a gender'),

              const SizedBox(height: 20),
              Text('🍽️ Food Preference *', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: AppVocab.foodPreferences.map((f) {
                  return SelectableChip(
                    label: AppVocab.displayLabel(f),
                    emoji: FoodPrefStyle.emojiFor(f),
                    selected: _foodPref == f,
                    color: FoodPrefStyle.colorFor(f),
                    onSelected: (_) => setState(() { _foodPref = f; _dirty = true; }),
                  );
                }).toList(),
              ),
              if (_submitted && _foodPref == null)
                const _FieldError('Please select a food preference'),

              const SizedBox(height: 20),
              Text('⚠️ Allergies', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: AppVocab.allergies.map((a) {
                  return SelectableChip(
                    label: AppVocab.displayLabel(a),
                    selected: _allergies.contains(a),
                    color: AppColors.danger,
                    onSelected: (sel) => setState(() {
                      sel ? _allergies.add(a) : _allergies.remove(a);
                      _dirty = true;
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _otherAllergyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Other allergen(s)',
                  hintText: 'e.g. sesame, mustard',
                  prefixIcon: Icon(Icons.edit_note),
                ),
              ),

              const SizedBox(height: 20),
              Text('🌍 Cuisine Preference *', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: AppVocab.cuisineOptionsForUI.map((c) {
                  return SelectableChip(
                    label: AppVocab.cuisineLabel(c),
                    selected: _cuisines.contains(c),
                    color: AppColors.tertiary,
                    onSelected: (sel) => setState(() {
                      if (c == 'any') {
                        _cuisines
                          ..clear()
                          ..add('any');
                      } else {
                        _cuisines.remove('any');
                        sel ? _cuisines.add(c) : _cuisines.remove(c);
                      }
                      _dirty = true;
                    }),
                  );
                }).toList(),
              ),
              if (_submitted && _cuisines.isEmpty)
                const _FieldError('Please select at least one cuisine, or "Any Cuisine"'),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Member'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
  setState(() => _submitted = true);

  final formValid = _formKey.currentState!.validate();
  final allValid = formValid && _gender != null && _foodPref != null && _cuisines.isNotEmpty;
  if (!allValid) return;

  setState(() => _saving = true);

  final otherAllergies = _otherAllergyCtrl.text
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();

  final cuisinesToSend = _cuisines.contains('any') ? <String>[] : _cuisines.toList();

  final member = FamilyMember(
    id: widget.existing?.id,
    name: _nameCtrl.text.trim(),
    age: int.parse(_ageCtrl.text.trim()),
    gender: _gender!,
    allergies: _allergies.toList(),       // chip selections only
    otherAllergies: otherAllergies,       // free-text field -> anyother_specific_allergy
    foodPreference: _foodPref!,
    cuisinePreferences: cuisinesToSend,
  );

  try {
    final auth = ref.read(authProvider);
    final userId = auth?.userId ?? demoUserId;
    final api = ref.read(apiProvider);
    if (widget.existing == null) {
      await api.createMember(userId, member);
    } else {
      await api.updateMember(widget.existing!.id!, member);
    }
    ref.invalidate(membersProvider);
    if (mounted) Navigator.pop(context);
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}
}

class _FieldError extends StatelessWidget {
  final String message;
  const _FieldError(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(message, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
    );
  }
}