import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RepoBranchChip extends StatelessWidget {
  final String? repoFullName;
  final String? branchName;
  final VoidCallback onTap;

  const RepoBranchChip({
    super.key,
    required this.repoFullName,
    required this.branchName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = repoFullName != null && repoFullName!.isNotEmpty;

    return Semantics(
      button: true,
      label: 'Repository ve branch değiştir',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.source_outlined,
                  size: 16,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isSelected ? '$repoFullName · $branchName' : 'Depo seçiniz',
                    style: AppTheme.monoBold.copyWith(
                      fontSize: 12,
                      color: isSelected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
