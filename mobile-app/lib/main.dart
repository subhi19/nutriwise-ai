import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/theme.dart';

void main() {
  runApp(const ProviderScope(child: NutriWiseApp()));
}

class NutriWiseApp extends StatelessWidget {
  const NutriWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            // Respects the phone's own accessibility font-size setting,
            // capped at 1.3x so layouts don't break
            textScaler: TextScaler.linear(mq.textScaler.scale(1.0).clamp(1.0, 1.3)),
          ),
          child: child!,
        );
      },
    );
  }
}