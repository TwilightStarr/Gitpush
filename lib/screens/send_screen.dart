import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/upload_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../widgets/empty_state.dart';
import '../widgets/mode_card.dart';
import '../widgets/section_card.dart';
import 'multi_file_screen.dart';
import 'repo_picker_screen.dart';
import 'zip_transfer_screen.dart';

class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repoProvider = Provider.of<RepoProvider>(context);
    final uploadProvider = Provider.of<UploadProvider>(context);

    if (repoProvider.selectedRepo == null) {
      return EmptyState(
        icon: Icons.source_outlined,
        message: 'Dosya göndermek için önce bir GitHub deposu seçmelisiniz.',
        actionLabel: 'Depo Seç',
        onAction: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RepoPickerScreen()),
          );
        },
      );
    }

    final repo = repoProvider.selectedRepo!;
    final branch = repoProvider.selectedBranch ?? repo.defaultBranch;

    return RefreshIndicator(
      onRefresh: () async {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final token = auth.token;
        if (token != null) {
          // Dalları ve repo ağacını yenile
          await repoProvider.loadBranches(token, repo);
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Repo / Branch Özeti Kartı
          SectionCard(
            title: 'Aktif Hedef Depo',
            trailing: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RepoPickerScreen()),
                );
              },
              child: const Text('Değiştir'),
            ),
            child: Row(
              children: [
                Icon(
                  repo.isPrivate ? Icons.lock : Icons.public,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo.fullName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Dal: $branch',
                        style: AppTheme.monoStyle.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mod A: ZIP'ten Aktar
          ModeCard(
            title: "ZIP'ten Aktar",
            description: 'Telefonda seçtiğiniz bir ZIP arşivini açın, dosya ağacını inceleyin ve tek seferde repoya yükleyin.',
            icon: Icons.folder_zip_outlined,
            iconColor: AppTheme.statusUpdate,
            badgeText: 'MOD A',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ZipTransferScreen()),
              );
            },
          ),
          const SizedBox(height: 12),

          // Mod B: Dosyaları Güncelle
          ModeCard(
            title: 'Dosyaları Güncelle',
            description: 'Birden fazla dosyayı, her biri farklı repo yoluna (klasör yoksa otomatik oluşturularak) tek commit ile yükleyin.',
            icon: Icons.upload_file_outlined,
            iconColor: AppTheme.statusNew,
            badgeText: 'MOD B',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MultiFileScreen()),
              );
            },
          ),
          const SizedBox(height: 16),

          // Son Gönderim Kartı
          if (uploadProvider.historyItems.isNotEmpty) ...[
            SectionCard(
              title: 'Son Gönderim',
              child: Builder(
                builder: (context) {
                  final last = uploadProvider.historyItems.first;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        last.commitMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            shortSha(last.commitSha),
                            style: AppTheme.monoStyle.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${last.filesCount} dosya',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
