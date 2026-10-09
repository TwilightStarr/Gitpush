import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/upload_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../utils/url_utils.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

/// MainShell zaten AppBar sağlar; bu ekran kendi Scaffold/AppBar'ını taşımaz.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<UploadProvider>(context, listen: false).loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final upload = Provider.of<UploadProvider>(context);
    final history = upload.historyItems;

    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        message: 'Henüz bu uygulamadan bir gönderim yapılmadı.',
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, top: 4),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Geçmişi Temizle'),
              onPressed: () async {
                final ok = await ConfirmDialog.show(
                  context,
                  title: 'Geçmiş Temizlensin mi?',
                  content: 'Tüm yerel gönderim kayıtları silinecek.',
                  isDestructive: true,
                );
                if (ok) upload.clearHistory();
              },
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = history[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.commit, color: AppTheme.statusNew),
                  title: Text(item.commitMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${item.repoFullName} (${item.branch}) · ${shortSha(item.commitSha)}',
                    style: AppTheme.monoStyle.copyWith(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.open_in_browser, size: 18),
                  onTap: () => openExternalUrl(context, item.commitUrl),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
