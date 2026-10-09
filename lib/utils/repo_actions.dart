import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/path_commit_info.dart';
import '../models/repo.dart';
import '../models/repo_listing.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/upload_provider.dart';
import '../services/github_service.dart';
import '../widgets/confirm_dialog.dart';
import 'format_utils.dart';

/// Repo tarayıcı ve dosya detay ekranlarının ortak işlemleri: silme, taşıma /
/// yeniden adlandırma, bağlantı üretme. Hepsi tek commit'tir ve geçmişe yazılır.
class RepoActions {
  RepoActions._();

  static String _enc(String path) => path.split('/').map(Uri.encodeComponent).join('/');

  /// Dosya/klasörün github.com üzerindeki sayfası.
  static String githubUrlFor(GitHubRepo repo, String branch, RepoEntry e) {
    final kind = e.isDir ? 'tree' : 'blob';
    return 'https://github.com/${repo.owner}/${repo.name}/$kind/${_enc(branch)}/${_enc(e.path)}';
  }

  /// Ham içerik adresi (yalnızca kopyalamak için; uygulama içinde açılmaz).
  static String rawUrlFor(GitHubRepo repo, String branch, RepoEntry e) {
    return 'https://raw.githubusercontent.com/${repo.owner}/${repo.name}/${_enc(branch)}/${_enc(e.path)}';
  }

  static Future<void> copy(BuildContext context, String text, String doneMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(doneMessage)));
  }

  static void _showBusy(BuildContext context, String label) {
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 18),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }

  static String? _authorName(AuthProvider a) =>
      (a.authorName ?? '').trim().isNotEmpty && (a.authorEmail ?? '').trim().isNotEmpty ? a.authorName : null;

  static String? _authorEmail(AuthProvider a) =>
      (a.authorName ?? '').trim().isNotEmpty && (a.authorEmail ?? '').trim().isNotEmpty ? a.authorEmail : null;

  /// Seçili öğeleri tek commit'te siler. Klasör içeren veya çok öğeli
  /// silmelerde onay için kelimenin yazılması istenir. Silindiyse true.
  static Future<bool> deleteEntries(BuildContext context, List<RepoEntry> entries) async {
    if (entries.isEmpty) return false;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final token = auth.token;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    if (token == null || repo == null || branch == null) return false;

    var fileCount = 0;
    var folderCount = 0;
    var bytes = 0;
    for (final e in entries) {
      if (e.isDir) {
        folderCount++;
        fileCount += e.fileCount;
      } else {
        fileCount++;
      }
      bytes += e.size;
    }
    if (fileCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçilen klasörler boş; silinecek dosya yok.')),
      );
      return false;
    }

    final single = entries.length == 1 ? entries.first : null;
    final title = single != null
        ? (single.isDir ? 'Klasör silinsin mi?' : 'Dosya silinsin mi?')
        : '${entries.length} öğe silinsin mi?';
    final summary = single != null && !single.isDir
        ? '${single.path} dalda ($branch) silinecek.'
        : '$fileCount dosya${folderCount > 0 ? ' ($folderCount klasör dahil)' : ''}, toplam ${formatBytes(bytes)}, '
            '"$branch" dalından tek bir commit ile silinecek. Commit geçmişinden geri alınabilir.';

    final needsTyping = folderCount > 0 || entries.length > 5;
    final bool ok;
    if (needsTyping) {
      final expected = single != null ? single.name : 'sil';
      ok = await showDialog<bool>(
            context: context,
            builder: (_) => _TypedConfirmDialog(title: title, content: summary, expected: expected),
          ) ??
          false;
    } else {
      ok = await ConfirmDialog.show(
        context,
        title: title,
        content: summary,
        confirmLabel: 'Sil',
        isDestructive: true,
      );
    }
    if (!ok || !context.mounted) return false;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final message = single != null
        ? 'chore: delete ${single.path} via Gitpush'
        : 'chore: delete ${entries.length} items via Gitpush';

    _showBusy(context, 'Siliniyor...');
    try {
      final res = await repoProv.deleteEntries(
        token: token,
        entries: entries,
        message: message,
        authorName: _authorName(auth),
        authorEmail: _authorEmail(auth),
      );
      navigator.pop();
      await upload.recordExternalCommit(
        owner: repo.owner,
        repo: repo.name,
        branch: branch,
        commitMessage: message,
        commitSha: res.commitSha,
        filesCount: res.fileCount,
      );
      settings.success();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${res.fileCount} dosya silindi (${shortSha(res.commitSha)}).')));
      return true;
    } on GitHubApiException catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Beklenmeyen hata: $e')));
      return false;
    }
  }

  /// Yeni yol sorar; dosyayı/klasörü içeriği yeniden yüklemeden taşır
  /// (tek commit). Başarılıysa yeni yolu, değilse null döner.
  static Future<String?> renameOrMove(BuildContext context, RepoEntry entry) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final token = auth.token;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    if (token == null || repo == null || branch == null) return null;

    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => _PathPromptDialog(entry: entry),
    );
    if (newPath == null || !context.mounted) return null;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    final List<RepoMove> moves;
    try {
      moves = repoProv.planMove(entry, newPath);
    } on GitHubApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return null;
    }

    final message = 'refactor: move ${entry.path} to ${newPath.trim()} via Gitpush';
    _showBusy(context, 'Taşınıyor...');
    try {
      final sha = await repoProv.applyMoves(
        token: token,
        moves: moves,
        message: message,
        authorName: _authorName(auth),
        authorEmail: _authorEmail(auth),
      );
      navigator.pop();
      await upload.recordExternalCommit(
        owner: repo.owner,
        repo: repo.name,
        branch: branch,
        commitMessage: message,
        commitSha: sha,
        filesCount: moves.length,
      );
      settings.success();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Taşındı (${shortSha(sha)}).')));
      return newPath.trim();
    } on GitHubApiException catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return null;
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Beklenmeyen hata: $e')));
      return null;
    }
  }
}

/// Geri alınması zor işlemler için "şunu yazarak onayla" penceresi.
class _TypedConfirmDialog extends StatefulWidget {
  final String title;
  final String content;
  final String expected;

  const _TypedConfirmDialog({required this.title, required this.content, required this.expected});

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _matches => _ctrl.text.trim().toLowerCase() == widget.expected.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.content),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              text: 'Onaylamak için ',
              children: [
                TextSpan(text: widget.expected, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const TextSpan(text: ' yazın:'),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: const Text('Sil'),
        ),
      ],
    );
  }
}

class _PathPromptDialog extends StatefulWidget {
  final RepoEntry entry;

  const _PathPromptDialog({required this.entry});

  @override
  State<_PathPromptDialog> createState() => _PathPromptDialogState();
}

class _PathPromptDialogState extends State<_PathPromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.entry.path);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return AlertDialog(
      title: Text(e.isDir ? 'Klasörü taşı / yeniden adlandır' : 'Dosyayı taşı / yeniden adlandır'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.isDir
                ? '${e.fileCount} dosya, içerikleri yeniden yüklenmeden tek commit ile taşınır.'
                : 'İçerik yeniden yüklenmeden tek commit ile taşınır. Klasör eklemek için yolu değiştirin (ör. lib/yeni/ad.dart).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Yeni yol'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Taşı')),
      ],
    );
  }
}
