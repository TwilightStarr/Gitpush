import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/repo_listing.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/file_icons.dart';
import '../utils/format_utils.dart';
import '../utils/repo_actions.dart';
import '../utils/url_utils.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import 'commits_screen.dart';
import 'file_detail_screen.dart';
import 'file_editor_screen.dart';

/// Repo tarayıcı: klasörler her zaman üstte, sıralama ve arama, çoklu seçim,
/// klasör özetleri (dosya sayısı / boyut), dosya detay ekranı ve toplu işlemler.
class RepoBrowserScreen extends StatefulWidget {
  const RepoBrowserScreen({super.key});

  @override
  State<RepoBrowserScreen> createState() => _RepoBrowserScreenState();
}

class _RepoBrowserScreenState extends State<RepoBrowserScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _crumbScroll = ScrollController();

  String _currentDir = '';
  String _query = '';
  bool _searching = false;
  final Set<String> _selected = <String>{};

  // Önbellek: ağaç değişmedikçe dizin / istatistik yeniden hesaplanmaz.
  int _cacheRevision = -1;
  String _cacheDir = '\u0000';
  RepoSortMode _cacheSort = RepoSortMode.nameAsc;
  bool _cacheHidden = true;
  List<RepoEntry> _entries = const <RepoEntry>[];
  int _statFiles = 0;
  int _statFolders = 0;
  int _statBytes = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _crumbScroll.dispose();
    super.dispose();
  }

  bool get _selecting => _selected.isNotEmpty;

  void _recompute(RepoProvider repoProv, AppSettings settings) {
    final rev = repoProv.treeRevision;
    if (rev == _cacheRevision &&
        _currentDir == _cacheDir &&
        settings.repoSort == _cacheSort &&
        settings.showHiddenFiles == _cacheHidden) {
      return;
    }
    final treeChanged = rev != _cacheRevision;
    _cacheRevision = rev;
    _cacheDir = _currentDir;
    _cacheSort = settings.repoSort;
    _cacheHidden = settings.showHiddenFiles;

    final tree = repoProv.currentTree;
    _entries = buildDirectoryListing(
      tree,
      _currentDir,
      sort: settings.repoSort,
      showHidden: settings.showHiddenFiles,
    );

    if (treeChanged) {
      var files = 0;
      var folders = 0;
      var bytes = 0;
      for (final e in tree) {
        final type = e['type'];
        if (type == 'tree') {
          folders++;
        } else {
          files++;
          final s = e['size'];
          if (s is num) bytes += s.toInt();
        }
      }
      _statFiles = files;
      _statFolders = folders;
      _statBytes = bytes;
    }
  }

  void _enterDir(String path) {
    setState(() {
      _currentDir = path;
      _query = '';
      _searching = false;
      _searchCtrl.clear();
      _selected.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_crumbScroll.hasClients) {
        _crumbScroll.animateTo(
          _crumbScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _newFile() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FileEditorScreen(path: _currentDir.isEmpty ? '' : '$_currentDir/', isNew: true),
      ),
    );
  }

  void _goUp() {
    final idx = _currentDir.lastIndexOf('/');
    _enterDir(idx == -1 ? '' : _currentDir.substring(0, idx));
  }

  Future<void> _refresh() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    if (token != null) await repoProv.refreshTree(token);
  }

  void _toggleSelect(RepoEntry e) {
    Provider.of<SettingsProvider>(context, listen: false).tap();
    setState(() {
      if (!_selected.remove(e.path)) _selected.add(e.path);
    });
  }

  Future<void> _open(RepoEntry e) async {
    if (_selecting) {
      _toggleSelect(e);
      return;
    }
    if (e.isDir) {
      _enterDir(e.path);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FileDetailScreen(entry: e)),
    );
  }

  List<RepoEntry> _selectedEntries(List<RepoEntry> visible) {
    return visible.where((e) => _selected.contains(e.path)).toList();
  }

  Future<void> _deleteSelected(List<RepoEntry> visible) async {
    final chosen = _selectedEntries(visible);
    final done = await RepoActions.deleteEntries(context, chosen);
    if (done && mounted) setState(_selected.clear);
  }

  void _showEntryActions(RepoEntry e) {
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) {
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(label, style: TextStyle(color: color)),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    e.path,
                    style: AppTheme.monoBold.copyWith(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                item(e.isDir ? Icons.folder_open : Icons.visibility_outlined, e.isDir ? 'Klasörü aç' : 'Ayrıntılar ve önizleme',
                    () => _open(e)),
                item(Icons.checklist, 'Seç', () => _toggleSelect(e)),
                item(Icons.copy, 'Yolu kopyala', () => RepoActions.copy(context, e.path, 'Yol kopyalandı.')),
                if (repo != null && branch != null)
                  item(Icons.open_in_new, 'GitHub\'da aç',
                      () => openExternalUrl(context, RepoActions.githubUrlFor(repo, branch, e))),
                if (!e.isSubmodule)
                  item(Icons.drive_file_move_outlined, 'Taşı / yeniden adlandır', () => RepoActions.renameOrMove(context, e)),
                if (!e.isSubmodule)
                  item(
                    Icons.delete_outline,
                    e.isDir ? 'Klasörü sil' : 'Dosyayı sil',
                    () => RepoActions.deleteEntries(context, [e]),
                    color: AppTheme.statusDelete,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repoProvider = Provider.of<RepoProvider>(context);
    final settingsProv = Provider.of<SettingsProvider>(context);
    final settings = settingsProv.settings;

    if (repoProvider.selectedRepo == null) {
      return const EmptyState(
        icon: Icons.folder_open,
        message: 'Lütfen önce üst kısımdan bir depo seçin.',
      );
    }

    if (repoProvider.treeError != null) {
      return ErrorView(
        message: 'Repo dosya listesi alınamadı: ${repoProvider.treeError}',
        onRetry: _refresh,
      );
    }
    if (repoProvider.isTreeLoading && repoProvider.currentTree.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    _recompute(repoProvider, settings);

    final searching = _query.trim().isNotEmpty;
    final List<RepoEntry> visible = searching
        ? searchRepoTree(repoProvider.currentTree, _query, showHidden: settings.showHiddenFiles)
        : _entries;

    // Silinmiş/yenilenmiş öğeleri seçimden düşür
    _selected.removeWhere((p) => !visible.any((e) => e.path == p));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _newFile,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Yeni dosya'),
            ),
      body: Column(
      children: [
        _buildToolbar(theme, settings, settingsProv, visible),
        if (!searching) _buildBreadcrumbs(theme),
        if (repoProvider.treeTruncated)
          Container(
            width: double.infinity,
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Bu depo çok büyük; GitHub dosya listesini kesti. Bazı dosyalar burada görünmeyebilir.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (!searching) _buildStatsLine(theme, repoProvider.isTreeLoading),
        const Divider(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 260,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                searching ? Icons.search_off : Icons.folder_off_outlined,
                                size: 44,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 10),
                              Text(searching ? 'Eşleşen dosya yok' : 'Bu klasör boş'),
                              if (!settings.showHiddenFiles && !searching)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Gizli (.) dosyalar kapalı',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(indent: 72),
                    itemBuilder: (context, index) => _buildTile(theme, visible[index], searching),
                  ),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildToolbar(ThemeData theme, AppSettings settings, SettingsProvider settingsProv, List<RepoEntry> visible) {
    if (_selecting) {
      return Container(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Seçimi kapat',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_selected.clear),
            ),
            Expanded(
              child: Text('${_selected.length} seçili', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Tümünü seç',
              icon: const Icon(Icons.select_all),
              onPressed: () => setState(() {
                _selected
                  ..clear()
                  ..addAll(visible.map((e) => e.path));
              }),
            ),
            IconButton(
              tooltip: 'Seçilenleri sil',
              icon: const Icon(Icons.delete_outline, color: AppTheme.statusDelete),
              onPressed: () => _deleteSelected(visible),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() {
                  _query = v;
                  _searching = v.trim().isNotEmpty;
                }),
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: 'Depoda dosya ara...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searching
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _query = '';
                            _searching = false;
                          }),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  isDense: true,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Sırala ve göster',
            icon: const Icon(Icons.sort),
            onSelected: (v) {
              if (v == 'hidden') {
                settingsProv.update((c) => c.copyWith(showHiddenFiles: !c.showHiddenFiles));
              } else {
                final mode = RepoSortMode.values.firstWhere((m) => m.name == v, orElse: () => RepoSortMode.nameAsc);
                settingsProv.update((c) => c.copyWith(repoSort: mode));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                enabled: false,
                height: 32,
                child: Text('Klasörler her zaman üstte', style: TextStyle(fontSize: 12)),
              ),
              for (final m in RepoSortMode.values)
                CheckedPopupMenuItem<String>(
                  value: m.name,
                  checked: settings.repoSort == m,
                  child: Text(m.label),
                ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<String>(
                value: 'hidden',
                checked: settings.showHiddenFiles,
                child: const Text('Gizli (.) dosyaları göster'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Commit geçmişi',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommitsScreen())),
          ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    final crumbs = breadcrumbsFor(_currentDir);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (_currentDir.isNotEmpty)
            IconButton(
              tooltip: 'Üst klasör',
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: _goUp,
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: ListView.separated(
              controller: _crumbScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              itemCount: crumbs.length,
              separatorBuilder: (_, __) => Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
              itemBuilder: (context, i) {
                final c = crumbs[i];
                final isLast = i == crumbs.length - 1;
                return Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: isLast ? null : () => _enterDir(c.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          if (i == 0) ...[
                            Icon(Icons.home_outlined, size: 16, color: isLast ? theme.colorScheme.primary : null),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            c.label,
                            style: AppTheme.monoBold.copyWith(
                              fontSize: 13,
                              color: isLast ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsLine(ThemeData theme, bool loading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Depo: $_statFiles dosya · $_statFolders klasör · ${formatBytes(_statBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Widget _buildTile(ThemeData theme, RepoEntry e, bool searching) {
    final selected = _selected.contains(e.path);
    final visual = e.isDir
        ? FileVisual(Icons.folder_rounded, theme.colorScheme.primary)
        : e.isSubmodule
            ? const FileVisual(Icons.account_tree_outlined, Color(0xFF8B93A7))
            : fileVisualFor(e.extension);

    String subtitle;
    if (e.isDir) {
      final parts = <String>[
        '${e.fileCount} dosya',
        if (e.folderCount > 0) '${e.folderCount} klasör',
        formatBytes(e.size),
      ];
      subtitle = parts.join(' · ');
    } else if (e.isSubmodule) {
      subtitle = 'Alt modül';
    } else {
      subtitle = formatBytes(e.size);
    }
    if (searching) {
      final slash = e.path.lastIndexOf('/');
      final parent = slash == -1 ? 'Kök' : e.path.substring(0, slash);
      subtitle = '$parent · $subtitle';
    }

    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: visual.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: selected
            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
            : Icon(visual.icon, color: visual.color, size: 24),
      ),
      title: Text(
        e.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.monoStyle.copyWith(
          fontSize: 13.5,
          fontWeight: e.isDir ? FontWeight.w700 : FontWeight.w500,
          color: e.isHidden ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: _selecting
          ? null
          : IconButton(
              tooltip: 'İşlemler',
              icon: const Icon(Icons.more_vert, size: 20),
              onPressed: () => _showEntryActions(e),
            ),
      onTap: () => _open(e),
      onLongPress: () => _selecting ? _showEntryActions(e) : _toggleSelect(e),
    );
  }
}
