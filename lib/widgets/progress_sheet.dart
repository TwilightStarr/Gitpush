import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProgressSheet extends StatelessWidget {
  final String currentStep;
  final int current;
  final int total;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const ProgressSheet({
    super.key,
    required this.currentStep,
    required this.current,
    required this.total,
    this.error,
    this.onRetry,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double progress = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

    return PopScope(
      canPop: false, // Gönderim sırasında geri tuşu engellenir
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (error == null)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Text(
                  error == null ? 'Gönderim Sürüyor' : 'Gönderim Başarısız Oldu',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: error != null ? 1.0 : (total > 0 ? progress : null),
              color: error != null ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              currentStep,
              style: AppTheme.monoStyle.copyWith(
                fontSize: 13,
                color: error != null ? theme.colorScheme.error : theme.colorScheme.onSurface,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('İptal'),
                    ),
                  const SizedBox(width: 8),
                  if (onRetry != null)
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Tekrar Dene'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
