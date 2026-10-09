import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/action_run.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../services/github_service.dart';
import '../utils/url_utils.dart';
import '../widgets/action_run_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';

class ActionsScreen extends StatefulWidget {
  /// Sekme şu an görünür mü? (MainShell IndexedStack tüm sekmeleri baştan kurar.)
  final bool isActive;

  const ActionsScreen({super.key, this.isActive = true});

  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  final GitHubService _gitHubService = GitHubService();
  List<ActionRun> _runs = [];
  bool _isLoading = false;
  String? _error;
  String? _loadedKey;
  bool _fetchScheduled = false;

  @override
  void didUpdateWidget(covariant ActionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sekmeye geçince yenile
    if (widget.isActive && !oldWidget.isActive) {
      _fetchRuns();
    }
  }

  Future<void> _fetchRuns() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repo = Provider.of<RepoProvider>(context, listen: false);
    final selected = repo.selectedRepo;
    final token = auth.token;
    if (token == null || selected == null) return;

    _loadedKey = _keyFor(repo);
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final list = await _gitHubService.getActionRuns(token, selected.owner, selected.name);
      if (!mounted) return;
      setState(() => _runs = list);
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _runs = [];
        _error = 'İş akışları alınamadı: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runs = [];
        _error = 'İş akışları alınamadı: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _keyFor(RepoProvider repo) =>
      '${repo.selectedRepo?.fullName}#${repo.selectedBranch}#${repo.treeRevision}';

  Future<void> _triggerWorkflow() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repo = Provider.of<RepoProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final selected = repo.selectedRepo;
    final token = auth.token;
    if (token == null || selected == null) return;

    try {
      await _gitHubService.triggerWorkflow(
        token,
        selected.owner,
        selected.name,
        'build.yml',
        repo.selectedBranch ?? 'main',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Workflow (build.yml) tetiklendi!')),
      );
      _fetchRuns();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Tetikleme hatası: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<RepoProvider>(context);

    if (repo.selectedRepo == null) {
      return const EmptyState(
        icon: Icons.bolt,
        message: 'GitHub Actions görüntülemek için bir repo seçiniz.',
      );
    }

    // Repo/dal değişti veya push sonrası ağaç yenilendi: görünürse yeniden yükle.
    if (widget.isActive && !_isLoading && !_fetchScheduled && _loadedKey != _keyFor(repo)) {
      _fetchScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchScheduled = false;
        if (mounted) _fetchRuns();
      });
    }

    if (_isLoading && _runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _fetchRuns);
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _triggerWorkflow,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Workflow Başlat'),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRuns,
        // Boş durum da kaydırılabilir olmalı ki çek-yenile çalışsın.
        child: _runs.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.play_circle_outline,
                    message: 'Bu depoda henüz GitHub Actions çalıştırması bulunmuyor.',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                itemCount: _runs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final run = _runs[index];
                  final fallback = repo.selectedRepo == null
                      ? ''
                      : 'https://github.com/${repo.selectedRepo!.owner}/${repo.selectedRepo!.name}/actions';
                  return ActionRunTile(
                    run: run,
                    onTap: () => openExternalUrl(
                      context,
                      run.htmlUrl.isNotEmpty ? run.htmlUrl : fallback,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
