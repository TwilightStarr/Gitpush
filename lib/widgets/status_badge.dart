import 'package:flutter/material.dart';
import '../models/git_file.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final GitFileStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case GitFileStatus.isNew:
        bg = AppTheme.statusNew.withValues(alpha: 0.15);
        fg = AppTheme.statusNew;
        icon = Icons.add_circle_outline;
        label = 'Yeni';
        break;
      case GitFileStatus.update:
        bg = AppTheme.statusUpdate.withValues(alpha: 0.15);
        fg = AppTheme.statusUpdate;
        icon = Icons.sync;
        label = 'Güncelleme';
        break;
      case GitFileStatus.delete:
        bg = AppTheme.statusDelete.withValues(alpha: 0.15);
        fg = AppTheme.statusDelete;
        icon = Icons.remove_circle_outline;
        label = 'Silinecek';
        break;
      case GitFileStatus.newFolder:
        bg = AppTheme.statusNewFolder.withValues(alpha: 0.15);
        fg = AppTheme.statusNewFolder;
        icon = Icons.create_new_folder_outlined;
        label = 'Yeni Klasör';
        break;
      case GitFileStatus.unchanged:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey;
        icon = Icons.check;
        label = 'Değişmedi';
        break;
      case GitFileStatus.conflict:
        bg = AppTheme.statusDelete.withValues(alpha: 0.15);
        fg = AppTheme.statusDelete;
        icon = Icons.error_outline;
        label = 'Çakışma';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
