import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/upload_provider.dart';
import '../services/github_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';

/// Metin dosyasını uygulama içinde düzenleyip tek commit ile kaydeder; ya da
/// yeni dosya oluşturur ([isNew]). Kayıttan önce gizli bilgi taraması yapılır.
class FileEditorScreen extends StatefulWidget {
  final String path;
  final String initialText;
  final bool isNew;
  final String? mode;

  const FileEditorScreen({
    super.key,
    required this.path,
    this.initialText = '',
    this.isNew = false,
    this.mode,
  });

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late final TextEditingController _pathCtrl = TextEditingController(text: widget.path);
  late final TextEditingController _textCtrl = TextEditingController(text: widget.initialText);
  late final TextEditingController _msgCtrl = TextEditingController(
    text: widget.isNew ? 'feat: add ${widget.path.split('/').last} via Gitpush' : 'chore: update ${widget.path} via Gitpush',
  );
  bool _saving = false;
  String? _error;

  bool get _dirty => widget.isNew ? _textCtrl.text.isNotEmpty : _textCtrl.text != widget.initialText;

  @override
  void dispose() {
    _pathCtrl.dispose();
    _textCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Değişiklikler atılsın mı?'),
        content: const Text('Kaydedilmemiş değişiklikler kaybolacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Düzenlemeye dön')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('At')),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _save() async {
    if (_saving) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final token = auth.token;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    if (token == null || repo == null || branch == null) return;

    final path = _pathCtrl.text.trim();
    final message = _msgCtrl.text.trim().isEmpty ? 'chore: update $path via Gitpush' : _msgCtrl.text.trim();

    if (widget.isNew) {
      final problem = repoProv.newFilePathProblem(path);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    } else if (!_dirty) {
      setState(() => _error = 'Değişiklik yok.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final bytes = Uint8List.fromList(utf8.encode(_textCtrl.text));
      final hasAuthor = (auth.authorName ?? '').trim().isNotEmpty && (auth.authorEmail ?? '').trim().isNotEmpty;
      final sha = await repoProv.saveFile(
        token: token,
        path: path,
        bytes: bytes,
        message: message,
        mode: widget.mode,
        authorName: hasAuthor ? auth.authorName : null,
        authorEmail: hasAuthor ? auth.authorEmail : null,
      );
      await upload.recordExternalCommit(
        owner: repo.owner,
        repo: repo.name,
        branch: branch,
        commitMessage: message,
        commitSha: sha,
        filesCount: 1,
      );
      settings.success();
      messenger.showSnackBar(SnackBar(content: Text('Kaydedildi (${shortSha(sha)}).')));
      navigator.pop(true);
    } on GitHubApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = Provider.of<SettingsProvider>(context).settings.previewFontSize;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'Yeni dosya' : 'Düzenle'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Kaydet'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _pathCtrl,
                    enabled: widget.isNew && !_saving,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Dosya yolu', isDense: true),
                    style: AppTheme.monoStyle.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _msgCtrl,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Commit mesajı', isDense: true),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12.5)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                enabled: !_saving,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                style: AppTheme.monoStyle.copyWith(fontSize: fontSize, height: 1.4),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.all(16),
                  hintText: 'İçerik...',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
