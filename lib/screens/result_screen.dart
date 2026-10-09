import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/action_run.dart';
import '../models/push_result.dart';
import '../providers/auth_provider.dart';
import '../services/github_service.dart';
import '../services/run_tracker.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../utils/url_utils.dart';
import 'main_shell.dart';

class ResultScreen extends StatefulWidget {
  final PushResult result;
  final String commitUrl;
  final String owner;
  final String repo;
  final String branch;
  final bool isPrivate;

  const ResultScreen({
    super.key,
    required this.result,
    required this.commitUrl,
    required this.owner,
    required this.repo,
    required this.branch,
    this.isPrivate = false,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static const int _pollIntervalSeconds = 10;
  static const int _pollLimitSeconds = 300;

  final GitHubService _gitHubService = GitHubService();
  Timer? _pollTimer;
  List<ActionRun> _runs = [];
  bool _isPolling = true;
  bool _notFound = false;
  String? _pollError;
  int _pollSeconds = 0;
  bool _requestInFlight = false;

  String get _sha => widget.result.commitSha ?? '';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _isPolling = false;
  }

  void _startPolling() {
    _pollActions();
    _pollTimer = Timer.periodic(const Duration(seconds: _pollIntervalSeconds), (timer) {
      _pollSeconds += _pollIntervalSeconds;
      if (_pollSeconds >= _pollLimitSeconds) {
        // Süre doldu: eşleşen çalışma hiç görünmediyse bunu bildir.
        if (mounted) {
          setState(() {
            _stopPolling();
            if (_runs.isEmpty && _pollError == null) _notFound = true;
          });
        } else {
          timer.cancel();
        }
        return;
      }
      _pollActions();
    });
  }

  Future<void> _pollActions() async {
    if (_requestInFlight) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null || _sha.isEmpty) {
      setState(_stopPolling);
      return;
    }

    _requestInFlight = true;
    try {
      final runs = await _gitHubService.getActionRuns(token, widget.owner, widget.repo);
      if (!mounted) return;

      final evaluation = evaluateRuns(runs, _sha);
      setState(() {
        _pollError = null;
        _runs = evaluation.matching;
        if (evaluation.allCompleted) _stopPolling();
      });
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      // Yetki/erişim hatası tekrarlarla düzelmez; polling durur.
      setState(() {
        _pollError = e.message;
        _stopPolling();
      });
    } finally {
      _requestInFlight = false;
    }
  }

  String get _actionsUrl => 'https://github.com/${widget.owner}/${widget.repo}/actions';
  String get _releasesUrl => 'https://github.com/${widget.owner}/${widget.repo}/releases';

  Color _runColor(ActionRun run, ThemeData theme) {
    if (run.isSuccess) return AppTheme.statusNew;
    if (run.isFailed || run.isTimedOut || run.isStartupFailure) return theme.colorScheme.error;
    if (run.isCancelled) return theme.colorScheme.onSurfaceVariant;
    return theme.colorScheme.primary;
  }

  IconData _runIcon(ActionRun run) {
    if (run.isSuccess) return Icons.check_circle;
    if (run.isFailed || run.isTimedOut || run.isStartupFailure) return Icons.cancel;
    if (run.isCancelled) return Icons.block;
    return Icons.hourglass_empty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final anySuccess = _runs.any((r) => r.isSuccess);
    final allDone = _runs.isNotEmpty && _runs.every((r) => r.isCompleted);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gönderim Tamamlandı'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Başarı İkonu
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.statusNew.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 64, color: AppTheme.statusNew),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Başarıyla Gönderildi!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Sayaçlar (gerçek push sonucundan)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('+${result.added} eklendi', style: const TextStyle(color: AppTheme.statusNew, fontWeight: FontWeight.bold)),
                  Text('~${result.updated} güncellendi', style: const TextStyle(color: AppTheme.statusUpdate, fontWeight: FontWeight.bold)),
                  Text('-${result.deleted} silindi', style: const TextStyle(color: AppTheme.statusDelete, fontWeight: FontWeight.bold)),
                  Text('=${result.skipped} atlandı', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              ),
              for (final w in result.warnings) ...[
                const SizedBox(height: 8),
                Text(w, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 16),

              // Commit SHA & Kopyala
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      shortSha(_sha),
                      style: AppTheme.monoBold.copyWith(fontSize: 14),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'SHA Kopyala',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _sha));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Commit SHA kopyalandı!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Canlı Build Durumu Kartı
              Card(
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Canlı Build Durumu',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_isPolling)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_pollError != null)
                        Text(
                          'Durum alınamadı: $_pollError',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                        )
                      else if (_runs.isNotEmpty)
                        ...[
                          for (final run in _runs.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(_runIcon(run), size: 18, color: _runColor(run, theme)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(run.name, style: const TextStyle(fontSize: 12)),
                                ),
                                Text(
                                  run.statusLabel,
                                  style: AppTheme.monoStyle.copyWith(fontSize: 12, color: _runColor(run, theme)),
                                ),
                              ],
                            ),
                          ),
                        ]
                      else if (_notFound)
                        const Text(
                          'Workflow tetiklenmedi/bulunamadı. Bu commit için bir GitHub Actions çalışması görünmedi.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      else
                        const Text(
                          'Bu commit için GitHub Actions çalışması bekleniyor...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Eylem Butonları
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainShell()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home),
                label: const Text('Ana Ekrana Dön'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => openExternalUrl(context, widget.commitUrl),
                icon: const Icon(Icons.open_in_browser),
                label: const Text("GitHub'da Aç"),
              ),
              if (widget.isPrivate)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Özel depo: tarayıcıda GitHub\'a giriş yapmadıysanız bağlantı 404 gösterebilir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  final url = _runs.isNotEmpty && _runs.first.htmlUrl.isNotEmpty
                      ? _runs.first.htmlUrl
                      : _actionsUrl;
                  openExternalUrl(context, url);
                },
                icon: const Icon(Icons.bolt),
                label: const Text("Actions'ta Aç"),
              ),
              if (allDone && anySuccess) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => openExternalUrl(context, _releasesUrl),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text("Releases'ı Aç"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
