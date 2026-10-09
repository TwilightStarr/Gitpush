import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/path_commit_info.dart';
import '../models/repo_listing.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../services/github_service.dart';
import '../theme/app_theme.dart';
import '../utils/file_icons.dart';
import '../utils/format_utils.dart';
import '../utils/repo_actions.dart';
import '../utils/url_utils.dart';
import 'commits_screen.dart';
import 'file_editor_screen.dart';

/// Tek bir dosyanın ayrıntıları: bilgi, son commit, içerik önizlemesi ve
/// işlemler (kopyala, GitHub'da aç, taşı/yeniden adlandır, sil).
class FileDetailScreen extends StatefulWidget {
  final RepoEntry entry;

  const FileDetailScreen({super.key, required this.entry});

  @override
  State<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends State<FileDetailScreen> {
  static const int _maxRenderedLines = 3000;

  late final PreviewKind _kind = previewKindFor(widget.entry.name);

  bool _loading = true;
  String? _error;
  String? _notice; // önizleme yok açıklaması (sınır, ikili dosya...)
  Uint8List? _imageBytes;
  String? _text;
  int _totalLines = 0;
  bool? _wrap;

  PathCommitInfo? _commit;
  bool _commitLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadContent();
      _loadCommit();
    });
  }

  String? get _token => Provider.of<AuthProvider>(context, listen: false).token;

  Future<void> _loadContent() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false).settings;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final token = _token;
    final entry = widget.entry;

    if (entry.isSubmodule) {
      setState(() {
        _loading = false;
        _notice = 'Bu bir alt modül (submodule); içeriği başka bir depoda tutulur.';
      });
      return;
    }
    if (_kind == PreviewKind.binary) {
      setState(() {
        _loading = false;
        _notice = 'İkili dosya (${formatBytes(entry.size)}); önizleme desteklenmiyor.';
      });
      return;
    }

    // Hem metin hem görsel için kullanıcının ayarladığı sınır geçerlidir.
    final limit = settings.previewMaxKb * 1024;
    if (entry.size > limit) {
      setState(() {
        _loading = false;
        _notice = 'Dosya (${formatBytes(entry.size)}) önizleme sınırından büyük '
            '(${formatBytes(limit)}). Ayarlardan sınırı yükseltebilir veya GitHub\'da açabilirsiniz.';
      });
      return;
    }
    if (token == null) return;

    try {
      final bytes = await repoProv.readFileBytes(token, entry, maxBytes: limit);
      if (!mounted) return;

      if (_kind == PreviewKind.image) {
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
        return;
      }

      // Metin: NUL bayt içeriyorsa veya UTF-8 değilse ikili say.
      if (bytes.contains(0)) {
        setState(() {
          _loading = false;
          _notice = 'Dosya ikili içerik gibi görünüyor; önizleme gösterilmiyor.';
        });
        return;
      }
      String decoded;
      try {
        decoded = utf8.decode(bytes);
      } on FormatException {
        setState(() {
          _loading = false;
          _notice = 'Dosya UTF-8 metin değil; önizleme gösterilmiyor.';
        });
        return;
      }
      if (decoded.startsWith('﻿')) decoded = decoded.substring(1);
      final lines = decoded.split('\n');
      setState(() {
        _text = decoded;
        _totalLines = decoded.isEmpty ? 0 : (decoded.endsWith('\n') ? lines.length - 1 : lines.length);
        _loading = false;
      });
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'İçerik alınamadı: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadCommit() async {
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final token = _token;
    if (token == null) return;
    try {
      final c = await repoProv.lastCommitFor(token, widget.entry.path);
      if (!mounted) return;
      setState(() {
        _commit = c;
        _commitLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commitLoading = false);
    }
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _delete() async {
    final done = await RepoActions.deleteEntries(context, [widget.entry]);
    if (done && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _edit() async {
    final text = _text;
    if (text == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FileEditorScreen(path: widget.entry.path, initialText: text, mode: widget.entry.mode),
      ),
    );
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  void _history() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommitsScreen(path: widget.entry.path)));
  }

  Future<void> _move() async {
    final newPath = await RepoActions.renameOrMove(context, widget.entry);
    if (newPath != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repoProv = Provider.of<RepoProvider>(context);
    final settings = Provider.of<SettingsProvider>(context).settings;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    final entry = widget.entry;
    final visual = fileVisualFor(entry.extension);
    final wrap = _wrap ?? settings.previewWrapLines;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_text != null)
            IconButton(
              tooltip: 'Düzenle',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
          if (_text != null)
            IconButton(
              tooltip: 'İçeriği kopyala',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => RepoActions.copy(context, _text!, 'İçerik kopyalandı.'),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'github':
                  if (repo != null && branch != null) {
                    openExternalUrl(context, RepoActions.githubUrlFor(repo, branch, entry));
                  }
                  break;
                case 'path':
                  RepoActions.copy(context, entry.path, 'Yol kopyalandı.');
                  break;
                case 'raw':
                  if (repo != null && branch != null) {
                    RepoActions.copy(context, RepoActions.rawUrlFor(repo, branch, entry), 'Ham bağlantı kopyalandı.');
                  }
                  break;
                case 'sha':
                  if (entry.sha != null) RepoActions.copy(context, entry.sha!, 'SHA kopyalandı.');
                  break;
                case 'history':
                  _history();
                  break;
                case 'move':
                  _move();
                  break;
                case 'delete':
                  _delete();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'history', child: _MenuRow(Icons.history, 'Dosya geçmişi')),
              const PopupMenuItem(value: 'github', child: _MenuRow(Icons.open_in_new, 'GitHub\'da aç')),
              const PopupMenuItem(value: 'path', child: _MenuRow(Icons.copy, 'Yolu kopyala')),
              const PopupMenuItem(value: 'raw', child: _MenuRow(Icons.link, 'Ham bağlantıyı kopyala')),
              if (entry.sha != null) const PopupMenuItem(value: 'sha', child: _MenuRow(Icons.tag, 'SHA kopyala')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'move', child: _MenuRow(Icons.drive_file_move_outlined, 'Taşı / yeniden adlandır')),
              const PopupMenuItem(
                value: 'delete',
                child: _MenuRow(Icons.delete_outline, 'Dosyayı sil', color: AppTheme.statusDelete),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Başlık kartı
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.path,
                          style: AppTheme.monoStyle.copyWith(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Ayrıntılar
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  _InfoTile(label: 'Boyut', value: '${formatBytes(entry.size)} (${entry.size} bayt)'),
                  if (_totalLines > 0) _InfoTile(label: 'Satır', value: '$_totalLines'),
                  _InfoTile(label: 'Dal', value: branch ?? '-'),
                  if (entry.mode != null) _InfoTile(label: 'Kip', value: _modeLabel(entry.mode!)),
                  if (entry.sha != null)
                    _InfoTile(
                      label: 'SHA',
                      value: shortSha(entry.sha!, length: 12),
                      onTap: () => RepoActions.copy(context, entry.sha!, 'SHA kopyalandı.'),
                    ),
                  _InfoTile(
                    label: 'Son değişiklik',
                    value: _commitLoading
                        ? 'Yükleniyor...'
                        : _commit == null
                            ? 'Bilinmiyor'
                            : '${_commit!.title}${_commit!.date != null ? '\n${_fmtDate(_commit!.date!)}' : ''}'
                                '${_commit!.authorName != null ? ' · ${_commit!.authorName}' : ''}',
                    onTap: _commit?.htmlUrl == null ? null : () => openExternalUrl(context, _commit!.htmlUrl!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Önizleme
          _buildPreview(theme, wrap),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _move,
                  icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                  label: const Text('Taşı / Ad'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.statusDelete),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Sil'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case '100644':
        return '100644 (normal dosya)';
      case '100755':
        return '100755 (çalıştırılabilir)';
      case '120000':
        return '120000 (sembolik bağlantı)';
      case '160000':
        return '160000 (alt modül)';
      default:
        return mode;
    }
  }

  Widget _buildPreview(ThemeData theme, bool wrap) {
    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadContent();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      );
    } else if (_notice != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.visibility_off_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(_notice!, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    } else if (_imageBytes != null) {
      body = ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          constraints: const BoxConstraints(maxHeight: 420),
          child: InteractiveViewer(
            maxScale: 6,
            child: Image.memory(
              _imageBytes!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Görsel çözülemedi.')),
              ),
            ),
          ),
        ),
      );
    } else if (_text != null) {
      body = _buildText(theme, wrap);
    } else {
      body = const SizedBox.shrink();
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Text('ÖNİZLEME', style: AppTheme.monoBold.copyWith(fontSize: 11, color: theme.colorScheme.primary)),
                const Spacer(),
                if (_text != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _wrap = !wrap),
                    icon: Icon(wrap ? Icons.wrap_text : Icons.notes, size: 16),
                    label: Text(wrap ? 'Kaydır: açık' : 'Kaydır: kapalı', style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const Divider(),
          body,
        ],
      ),
    );
  }

  Widget _buildText(ThemeData theme, bool wrap) {
    final settings = Provider.of<SettingsProvider>(context).settings;
    final fontSize = settings.previewFontSize;
    final style = AppTheme.monoStyle.copyWith(fontSize: fontSize, height: 1.45, color: theme.colorScheme.onSurface);
    final numStyle = style.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7));

    if (_text!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Dosya boş.'),
      );
    }

    var lines = _text!.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines = lines.sublist(0, lines.length - 1);
    final truncated = lines.length > _maxRenderedLines;
    if (truncated) lines = lines.sublist(0, _maxRenderedLines);

    final gutterWidth = (lines.length.toString().length * (fontSize * 0.62)) + 8;
    final numbers = List<String>.generate(lines.length, (i) => '${i + 1}').join('\n');
    final content = lines.join('\n');

    final code = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: gutterWidth,
          padding: const EdgeInsets.only(left: 4, right: 4, top: 12, bottom: 12),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Text(numbers, textAlign: TextAlign.right, style: numStyle),
        ),
        const SizedBox(width: 10),
        if (wrap)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
              child: SelectableText(content, style: style),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12, right: 16),
            child: SelectableText(content, style: style),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wrap)
          code
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: code,
          ),
        if (truncated)
          Container(
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(12),
            child: Text(
              'İlk $_maxRenderedLines satır gösteriliyor (toplam $_totalLines). '
              'Tamamını kopyalamak için üstteki "İçeriği kopyala" düğmesini veya GitHub\'ı kullanın.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoTile({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onTap != null ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
