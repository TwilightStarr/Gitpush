import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/path_commit_info.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../services/github_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../utils/repo_actions.dart';
import '../utils/url_utils.dart';

/// Seçili dalın (veya tek bir dosyanın) commit geçmişi. Sayfa sayfa yüklenir.
class CommitsScreen extends StatefulWidget {
  /// Doluysa yalnızca bu yolu değiştiren commit'ler listelenir.
  final String? path;

  const CommitsScreen({super.key, this.path});

  @override
  State<CommitsScreen> createState() => _CommitsScreenState();
}

class _CommitsScreenState extends State<CommitsScreen> {
  static const int _pageSize = 30;

  final List<PathCommitInfo> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await repoProv.loadCommits(token, path: widget.path, page: _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(list);
        _hasMore = list.length >= _pageSize;
        _page++;
      });
    } on GitHubApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Geçmiş alınamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'az önce';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inDays < 1) return '${diff.inHours} sa önce';
    if (diff.inDays < 30) return '${diff.inDays} gün önce';
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branch = Provider.of<RepoProvider>(context).selectedBranch ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.path == null ? 'Commit geçmişi' : widget.path!.split('/').last),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.path ?? branch,
                style: AppTheme.monoStyle.copyWith(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _items.length + 1,
                  separatorBuilder: (_, __) => const Divider(indent: 16),
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      if (_items.isEmpty) {
                        return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Commit bulunamadı.')));
                      }
                      if (_error != null) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                        );
                      }
                      if (!_hasMore) return const SizedBox(height: 8);
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : OutlinedButton(onPressed: _load, child: const Text('Daha fazla yükle')),
                        ),
                      );
                    }
                    final c = _items[i];
                    return ListTile(
                      leading: Icon(Icons.commit, color: theme.colorScheme.primary),
                      title: Text(c.title.isEmpty ? '(mesaj yok)' : c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${c.authorName ?? 'bilinmiyor'} · ${_ago(c.date)} · ${shortSha(c.sha)}',
                        style: AppTheme.monoStyle.copyWith(fontSize: 11),
                      ),
                      onTap: c.htmlUrl == null ? null : () => openExternalUrl(context, c.htmlUrl!),
                      onLongPress: () => RepoActions.copy(context, c.sha, 'SHA kopyalandı.'),
                    );
                  },
                ),
    );
  }
}
