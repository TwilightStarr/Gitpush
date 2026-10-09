import 'package:flutter/material.dart';
import '../models/git_file.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';

class FileTreeView extends StatelessWidget {
  final List<GitFileItem> files;
  final ValueChanged<int> onToggle;

  const FileTreeView({
    super.key,
    required this.files,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        final hasConflict = item.isSelected && item.status == GitFileStatus.conflict;
        return CheckboxListTile(
          value: item.isSelected,
          onChanged: (_) => onToggle(index),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            item.repoPath,
            style: AppTheme.monoStyle.copyWith(
              fontSize: 12,
              color: item.isSelected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          subtitle: hasConflict
              ? Text(
                  item.conflictMessage ?? 'Çakışma',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                )
              : null,
          secondary: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.statusKnown) StatusBadge(status: item.status),
              const SizedBox(height: 2),
              Text(
                item.formattedSize,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}
