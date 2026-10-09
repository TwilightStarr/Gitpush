import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../services/github_service.dart';
import '../theme/app_theme.dart';

class RepoPickerScreen extends StatefulWidget {
  const RepoPickerScreen({super.key});

  @override
  State<RepoPickerScreen> createState() => _RepoPickerScreenState();
}

class _RepoPickerScreenState extends State<RepoPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showNewRepoDialog() {
    final nameCtrl = TextEditingController();
    bool isPrivate = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Yeni Depo Oluştur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Depo Adı'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Özel (Private) Depo'),
                value: isPrivate,
                onChanged: (val) => setModalState(() => isPrivate = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  final auth = Provider.of<AuthProvider>(context, listen: false);
                  final repoProv = Provider.of<RepoProvider>(context, listen: false);
                  Navigator.pop(ctx);
                  final created = await repoProv.createNewRepo(auth.token!, name, isPrivate);
                  if (created != null && mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewBranchDialog() {
    final branchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Dal (Branch) Oluştur'),
        content: TextField(
          controller: branchCtrl,
          decoration: const InputDecoration(labelText: 'Dal Adı (Örn: feature-1)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final b = branchCtrl.text.trim();
              if (b.isNotEmpty) {
                final auth = Provider.of<AuthProvider>(context, listen: false);
                final repoProv = Provider.of<RepoProvider>(context, listen: false);
                Navigator.pop(ctx);
                final success = await repoProv.createNewBranch(auth.token!, b);
                if (success && mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteBranch(String name) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dal silinsin mi?'),
        content: Text('"$name" dalı GitHub\'dan silinecek. Birleştirilmemiş commit\'ler kaybolabilir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || auth.token == null) return;
    try {
      await repoProv.deleteBranch(auth.token!, name);
      messenger.showSnackBar(SnackBar(content: Text('"$name" silindi.')));
    } on GitHubApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final repoProvider = Provider.of<RepoProvider>(context);

    final sortMode = Provider.of<SettingsProvider>(context).settings.repoListSort;
    final filteredRepos = repoProvider.repositories.where((r) {
      return r.fullName.toLowerCase().contains(_filter.toLowerCase());
    }).toList();
    switch (sortMode) {
      case RepoListSort.recent:
        filteredRepos.sort((a, b) => (b.updatedAt ?? DateTime(1970)).compareTo(a.updatedAt ?? DateTime(1970)));
        break;
      case RepoListSort.name:
        filteredRepos.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
        break;
      case RepoListSort.privateFirst:
        filteredRepos.sort((a, b) {
          if (a.isPrivate != b.isPrivate) return a.isPrivate ? -1 : 1;
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        });
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Repo & Dal Seçimi'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewRepoDialog,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Repo'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              // Arama Çubuğu
              Padding(
                padding: const EdgeInsets.all(16),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Depolarda ara...',
                  leading: const Icon(Icons.search),
                  onChanged: (val) => setState(() => _filter = val),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: filteredRepos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final repo = filteredRepos[index];
                    final isSelected = repo.fullName == repoProvider.selectedRepo?.fullName;

                    return ExpansionTile(
                      key: ValueKey(repo.id),
                      initiallyExpanded: isSelected,
                      leading: Icon(
                        repo.isPrivate ? Icons.lock_outline : Icons.public,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        repo.fullName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        '${repo.description != null && repo.description!.isNotEmpty ? '${repo.description}\n' : ''}Varsayılan: ${repo.defaultBranch}',
                        style: AppTheme.monoStyle.copyWith(fontSize: 11),
                      ),
                      onExpansionChanged: (expanded) {
                        if (expanded) {
                          repoProvider.selectRepository(auth.token!, repo);
                        }
                      },
                      children: [
                        // Dallar listesi
                        Container(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'DALLAR (silmek için uzun bas)',
                                    style: AppTheme.monoBold.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _showNewBranchDialog,
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text('Yeni Dal', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                              ...repoProvider.branches.map((b) {
                                final isCurrentBranch = b.name == repoProvider.selectedBranch;
                                return ListTile(
                                  dense: true,
                                  title: Text(b.name, style: AppTheme.monoStyle),
                                  trailing: isCurrentBranch
                                      ? Icon(Icons.check, color: theme.colorScheme.primary, size: 18)
                                      : null,
                                  onTap: () {
                                    repoProvider.selectBranch(auth.token!, b.name);
                                    Navigator.pop(context);
                                  },
                                  onLongPress: b.name == repo.defaultBranch ? null : () => _confirmDeleteBranch(b.name),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
