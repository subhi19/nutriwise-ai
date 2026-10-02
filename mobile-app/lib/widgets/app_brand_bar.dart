import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import 'app_logo.dart';

class AppBrandBar extends StatelessWidget {
  final bool showTagline;
  const AppBrandBar({super.key, this.showTagline = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          const AppLogo(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppIdentity.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (showTagline)
                  Text(AppIdentity.subTagline,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w700,
                          )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}