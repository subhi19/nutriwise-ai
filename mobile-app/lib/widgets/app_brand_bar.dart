import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import 'account_menu_button.dart';
import 'app_logo.dart';

class AppBrandBar extends StatelessWidget {
  final String? trailingTagline;
  const AppBrandBar({super.key, this.trailingTagline});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // On narrow screens there's no room beside the name, so the extra tagline goes underneath.
    final compact = MediaQuery.sizeOf(context).width < 600;
    final extraStyle = t.bodySmall?.copyWith(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w700,
      color: AppColors.secondary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const AppLogo(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppIdentity.name, style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(AppIdentity.tagline, style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                  Text(
                    AppIdentity.subTagline,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trailingTagline != null && compact) Text(trailingTagline!, style: extraStyle),
                ],
              ),
            ),
            if (trailingTagline != null && !compact) ...[
              const SizedBox(width: 10),
              Text(trailingTagline!, style: extraStyle),
            ],
            const SizedBox(width: 4),
            const AccountMenuButton(),
          ],
        ),
      ),
    );
  }
}