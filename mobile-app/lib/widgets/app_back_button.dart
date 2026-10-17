import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';

/// "← Back" pill. Goes back one page if there is one, otherwise to [fallback].
/// With [confirm] set it asks first, for screens holding results that aren't saved yet.
class AppBackButton extends StatelessWidget {
  final String fallback;
  final bool confirm;
  const AppBackButton({super.key, required this.fallback, this.confirm = false});

  Future<void> _onTap(BuildContext context) async {
    if (confirm) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('Leave this page?'),
          content: const Text('Your current results haven\'t been saved and will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (leave != true || !context.mounted) return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallback);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _onTap(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.primaryDark),
                  SizedBox(width: 6),
                  Text('Back',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}