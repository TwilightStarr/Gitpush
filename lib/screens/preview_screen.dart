import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/git_file.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/upload_provider.dart';
import '../services/repo_diff.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/progress_sheet.dart';
import '../widgets/send_bottom_bar.dart';
import 'result_screen.dart';

class PreviewScreen extends StatefulWidget {
  final PreviewSource source;
  final String commitMessage;

  const PreviewScreen({
    super.key,
    required this.source,
    required this.commitMessage,
  });

  /// Önizlemeye girmeden ÖNCE repo ağacını taze çeker. Alınamazsa önizlemeye
  /// geçilmez ("hepsi yeni" varsayılmaz).
  static Future<void> open(
    BuildContext context, {
    required PreviewSource source,
    required String commitMessage,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final token = auth.token;
    if (token == null || repoProv.selectedRepo == null || repoProv.selectedBranch == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Önce bir depo ve dal seçmelisiniz.')),
      );
      return;
    }

    // Yükleniyor göstergesi
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    final ok = await repoProv.refreshTree(token);
    navigator.pop(); // yükleniyor göstergesini kapat

    if (!ok || repoProv.treeIndex == null) {
      final reason = repoProv.treeError;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Repo dosya listesi alınamadı, yeniden deneyin.${reason != null ? '\n$reason' : ''}',
          ),
        ),
      );
      return;
    }

    upload.reclassifyAll(repoProv.treeIndex, truncated: repoProv.treeTruncated);
    if (!context.mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(source: source, commitMessage: commitMessage),
      ),
    );
  }

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final TextEditingController _commitMsgCtrl;

  /// Push başladığında plan dondurulur (push sonrası sıfırlanan provider
  /// durumu ekranda "değişiklik yok" gibi görünmesin).
  PushPlan? _frozenPlan;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    _commitMsgCtrl = TextEditingController(text: widget.commitMessage);
  }

  @override
  void dispose() {
    _commitMsgCtrl.dispose();
    super.dispose();
  }

  Future<void> _startPush(PushPlan plan) async {
    if (_pushing) return; // çift dokunuş koruması
    if (plan.hasBlockers || !plan.hasChanges) return;

    // Silme varsa çift onay
    if (plan.deletes.isNotEmpty) {
      final first = await ConfirmDialog.show(
        context,
        title: 'Dosyalar silinecek',
        content: '${plan.deletes.length} dosya depodan kalıcı olarak silinecek. Devam edilsin mi?',
        isDestructive: true,
      );
      if (!first || !mounted) return;

      final second = await ConfirmDialog.show(
        context,
        title: 'Son onay',
        content: '${plan.deletes.length} dosyanın silinmesini onaylıyor musunuz? '
            'Bu işlem commit geçmişinden geri alınabilir ancak yine de dikkatli olun.',
        isDestructive: true,
        confirmLabel: 'Evet, sil',
      );
      if (!second || !mounted) return;
    }

    await _runPush(plan);
  }

  Future<void> _runPush(PushPlan plan) async {
    if (_pushing) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    final token = auth.token;
    if (repo == null || branch == null || token == null) return;

    setState(() {
      _pushing = true;
      _frozenPlan = plan;
    });

    // ignore: unawaited_futures
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer<UploadProvider>(
          builder: (context, up, _) {
            return ProgressSheet(
              currentStep: up.uploadStep,
              current: up.uploadProgressCurrent,
              total: up.uploadProgressTotal,
              error: up.uploadError,
              onRetry: () {
                Navigator.pop(sheetContext);
                // Güncel sınıflandırmayla yeniden dene
                final fresh = upload.planFor(widget.source);
                if (!fresh.hasBlockers && fresh.hasChanges) {
                  _runPush(fresh);
                }
              },
              onCancel: () => Navigator.pop(sheetContext),
            );
          },
        );
      },
    );

    final commitMessage = _commitMsgCtrl.text.trim().isEmpty
        ? 'Gitpush: güncelleme'
        : _commitMsgCtrl.text.trim();
    final hasAuthor = (auth.authorName ?? '').trim().isNotEmpty &&
        (auth.authorEmail ?? '').trim().isNotEmpty;

    final success = await upload.executePush(
      token: token,
      owner: repo.owner,
      repo: repo.name,
      branch: branch,
      commitMessage: commitMessage,
      plan: plan,
      authorName: hasAuthor ? auth.authorName : null,
      authorEmail: hasAuthor ? auth.authorEmail : null,
    );

    if (!mounted) return;

    if (!success) {
      setState(() {
        _pushing = false;
        _frozenPlan = null;
      });
      // Dal siz işlem yaparken değiştiyse ağacı yenile ve yeniden sınıflandır.
      if (upload.uploadErrorKind == 'branch_moved' || upload.uploadErrorKind == 'safety_net') {
        final ok = await repoProv.refreshTree(token);
        if (ok) {
          upload.reclassifyAll(repoProv.treeIndex, truncated: repoProv.treeTruncated);
        }
      }
      return; // hata, ProgressSheet içinde gösteriliyor
    }

    navigator.pop(); // Progress modalını kapat
    final result = upload.lastResult;

    if (result == null || result.noChanges) {
      setState(() {
        _pushing = false;
        _frozenPlan = null;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Değişiklik yok: Repodaki dosyalarla aynı, commit atılmadı.')),
      );
      return;
    }

    // Başarılı: yükleme durumunu temizle, ağacı ve Actions'ı yenile
    final owner = repo.owner;
    final repoName = repo.name;
    final isPrivate = repo.isPrivate;
    final commitUrl = upload.lastCommitUrl ?? '';

    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: result,
          commitUrl: commitUrl,
          owner: owner,
          repo: repoName,
          branch: branch,
          isPrivate: isPrivate,
        ),
      ),
    );
    upload.resetAfterPush();
    // ignore: unawaited_futures
    repoProv.refreshTree(token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upload = Provider.of<UploadProvider>(context);
    final repoProv = Provider.of<RepoProvider>(context);

    final plan = _frozenPlan ?? upload.planFor(widget.source);
    final addList = plan.adds;
    final updateList = plan.updates;
    final deleteList = plan.deletes;
    final unchangedList = plan.unchanged;
    final conflictList = plan.conflicts;

    final canPush = !plan.hasBlockers && plan.hasChanges && !_pushing && !upload.isUploading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gönderim Önizlemesi'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Üstte Sayaç Çipleri
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCounterChip('+${addList.length} eklenecek', AppTheme.statusNew),
                  _buildCounterChip('~${updateList.length} güncellenecek', AppTheme.statusUpdate),
                  _buildCounterChip('-${deleteList.length} silinecek', AppTheme.statusDelete),
                  _buildCounterChip('=${unchangedList.length} değişmedi', Colors.grey),
                ],
              ),
              const SizedBox(height: 16),

              if (repoProv.treeTruncated) ...[
                _buildBanner(
                  'Repo çok büyük; durum tahminleri eksik olabilir.',
                  Icons.info_outline,
                  const Color(0xFFD29922).withValues(alpha: 0.18),
                  theme.colorScheme.onSurface,
                ),
                const SizedBox(height: 12),
              ],

              if (plan.treeUnknown) ...[
                _buildBanner(
                  'Repo dosya listesi alınamadı; gönderim engellendi. Geri dönüp tekrar deneyin.',
                  Icons.error_outline,
                  theme.colorScheme.errorContainer,
                  theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 12),
              ],

              if (conflictList.isNotEmpty) ...[
                _buildBanner(
                  '${conflictList.length} dosyada sorun var; düzeltilene kadar gönderim engellendi.',
                  Icons.block,
                  theme.colorScheme.errorContainer,
                  theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 12),
              ],

              // Silinecek Dosya Varsa Kırmızı Uyarı Bandı
              if (deleteList.isNotEmpty) ...[
                _buildBanner(
                  'DİKKAT: ${deleteList.length} dosya depodan kalıcı olarak silinecek!',
                  Icons.warning_amber_rounded,
                  theme.colorScheme.errorContainer,
                  theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 12),
              ],

              if (!plan.hasChanges && !plan.hasBlockers) ...[
                _buildBanner(
                  'Değişiklik yok: Seçilen dosyalar repodakilerle aynı. Commit atılmayacak.',
                  Icons.info_outline,
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.onSurface,
                ),
                const SizedBox(height: 12),
              ],

              // Gruplu Listeler
              if (conflictList.isNotEmpty)
                _buildGroupTile('Engellenen Dosyalar (${conflictList.length})', conflictList, AppTheme.statusDelete, showMessage: true),
              if (addList.isNotEmpty)
                _buildGroupTile('Eklenecek Dosyalar (${addList.length})', addList, AppTheme.statusNew),
              if (updateList.isNotEmpty)
                _buildGroupTile('Güncellenecek Dosyalar (${updateList.length})', updateList, AppTheme.statusUpdate),
              if (deleteList.isNotEmpty)
                _buildGroupTile('Silinecek Dosyalar (${deleteList.length})', deleteList, AppTheme.statusDelete),
              if (plan.skipped.isNotEmpty)
                _buildGroupTile(
                  'Atlanacak - üzerine yazılmıyor (${plan.skipped.length})',
                  plan.skipped,
                  Colors.grey,
                  initiallyExpanded: false,
                ),
              if (unchangedList.isNotEmpty)
                _buildGroupTile(
                  'Değişmeyen Dosyalar - gönderilmez (${unchangedList.length})',
                  unchangedList,
                  Colors.grey,
                  initiallyExpanded: false,
                ),

              const SizedBox(height: 16),
              // Commit Mesajı
              Card(
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Commit Mesajı',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commitMsgCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'feat: add changes...',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SendBottomBar(
        summaryText: '${plan.pushItems.length} dosya işlenecek · ${unchangedList.length} değişmedi',
        buttonLabel: 'Onayla ve Gönder',
        onButtonPressed: canPush ? () => _startPush(plan) : null,
      ),
    );
  }

  Widget _buildBanner(String text, IconData icon, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildGroupTile(
    String title,
    List<GitFileItem> items,
    Color color, {
    bool initiallyExpanded = true,
    bool showMessage = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(Icons.circle, color: color, size: 12),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        children: items.map((f) {
          final path = f.status == GitFileStatus.delete ? f.repoPath : f.targetPath;
          final subtitle = showMessage
              ? (f.conflictMessage ?? 'Çakışma')
              : (f.status == GitFileStatus.delete ? 'Repodan silinecek' : f.formattedSize);
          return ListTile(
            dense: true,
            title: Text(path, style: AppTheme.monoStyle.copyWith(fontSize: 12)),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: showMessage ? AppTheme.statusDelete : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
