import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class ErrorBox extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorBox({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isApi = error is ApiException;
    // Unexpected errors (e.g. a response that doesn't match our models) show a generic
    // message to the user. Print the real cause for developers.
    if (!isApi && kDebugMode) debugPrint('Unexpected error: $error');

    final message = isApi ? (error as ApiException).message : 'Something went wrong. Please try again.';
    final canRetry = (isApi ? (error as ApiException).retry : true) && onRetry != null;

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