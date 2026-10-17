import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../providers/providers.dart';

class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authProvider)?.name;

    return PopupMenuButton<String>(
      tooltip: 'Account',
      padding: const EdgeInsets.all(4),
      icon: const Icon(Icons.account_circle_outlined, size: 30, color: AppColors.primaryDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        if (value == 'family') {
          if (GoRouterState.of(context).uri.path != '/profile') context.push('/profile');
        } else if (value == 'logout') {
          _confirmAndLogout(context, ref);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Signed in as',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text(name ?? 'Guest',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'family',
          child: Row(
            children: [
              Icon(Icons.family_restroom_outlined, size: 20, color: AppColors.primary),
              SizedBox(width: 10),
              Text('My family'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 20, color: AppColors.danger),
              SizedBox(width: 10),
              Text('Log out'),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text('Log out?'),
      content: const Text(
        'You\'ll need to log in again to see your family\'s plans. '
        'Anything you haven\'t saved will be cleared.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  // Grab these first: the current screen is replaced as soon as we log out.
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);

  performLogout(ref);
  router.go('/login');
  messenger.showSnackBar(const SnackBar(content: Text('You\'ve been logged out.')));
}