import 'package:flutter/material.dart';
import '../models/action_run.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';

class ActionRunTile extends StatelessWidget {
  final ActionRun run;
  final VoidCallback onTap;

  const ActionRunTile({
    super.key,
    required this.run,
    required this.onTap,
  });

  Widget _buildStatusIcon(BuildContext context) {
    final theme = Theme.of(context);

    if (run.isRunning) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (run.isSuccess) {
      return const Icon(Icons.check_circle, color: AppTheme.statusNew, size: 22);
    }
    if (run.isFailed || run.isTimedOut || run.isStartupFailure) {
      return Icon(Icons.cancel, color: theme.colorScheme.error, size: 22);
    }
    if (run.isCancelled) {
      return Icon(Icons.block, color: theme.colorScheme.onSurfaceVariant, size: 22);
    }
    return Icon(Icons.hourglass_empty, color: theme.colorScheme.onSurfaceVariant, size: 22);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        leading: _buildStatusIcon(context),
        title: Text(
          run.name,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              run.commitMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  run.headBranch,
                  style: AppTheme.monoStyle.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  shortSha(run.headSha),
                  style: AppTheme.monoStyle.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  run.statusLabel,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.open_in_new, size: 16),
      ),
    );
  }
}
