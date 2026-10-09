import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/path_commit_info.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/upload_provider.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/url_utils.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gitpush_logo.dart';
import '../widgets/pin_dialogs.dart';
import 'setup_screen.dart';

const String kAppVersion = '1.2.1+4';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  final GitHubService _github = GitHubService();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _commitCtrl = TextEditingController();
  final TextEditingController _shortcutCtrl = TextEditingController();
  List<String> _shortcuts = [];
  RateLimitInfo? _rate;
  String? _rateError;
  bool _rateLoading = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false).settings;
    _nameCtrl.text = auth.authorName ?? '';
    _emailCtrl.text = auth.authorEmail ?? '';
    _commitCtrl.text = settings.defaultCommitMessage;
    _loadShortcuts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _commitCtrl.dispose();
    _shortcutCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShortcuts() async {
    final list = await _storage.getShortcuts();
    if (mounted) setState(() => _shortcuts = list);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadRate() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    setState(() {
      _rateLoading = true;
      _rateError = null;
    });
    try {
      final r = await _github.getRateLimit(token);
      if (mounted) setState(() => _rate = r);
    } on GitHubApiException catch (e) {
      if (mounted) setState(() => _rateError = e.message);
    } finally {
      if (mounted) setState(() => _rateLoading = false);
    }
  }

  /// Token'ın türünü yalnızca ön ekinden çıkarır; token asla gösterilmez.
  String _tokenKind(String? token) {
    if (token == null) return 'Yok';
    if (token.startsWith('github_pat_')) return 'Fine-grained PAT';
    if (token.startsWith('ghp_')) return 'Klasik PAT';
    if (token.startsWith('gho_')) return 'OAuth (GitHub ile giriş)';
    if (token.startsWith('ghu_') || token.startsWith('ghs_')) return 'GitHub App';
    return 'Bilinmeyen tür';
  }

  Future<T?> _pick<T>(String title, Map<T, String> options, T current) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.value),
                trailing: e.key == current ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ok = await ConfirmDialog.show(
      context,
      title: 'Çıkış Yapılsın mı?',
      content: 'Kayıtlı token, yazar bilgileri ve geçmiş bu cihazdan silinecek.',
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final uploadProv = Provider.of<UploadProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    await auth.logout();
    repoProv.reset();
    uploadProv.resetAll();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SetupScreen()),
      (route) => false,
    );
  }

  Future<void> _toggleLock(bool on) async {
    final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    if (on) {
      final created = await createNewPin(context);
      if (!created || !mounted) return;
      await settingsProv.update((c) => c.copyWith(appLockEnabled: true));
      await lock.syncSettings(settingsProv.settings);
      _snack('Uygulama kilidi açıldı.');
    } else {
      final ok = await verifyCurrentPin(context, title: 'Kilidi kapat');
      if (!ok || !mounted) return;
      await lock.service.clear();
      await settingsProv.update((c) => c.copyWith(appLockEnabled: false));
      await lock.syncSettings(settingsProv.settings);
      _snack('Uygulama kilidi kapatıldı.');
    }
  }

  Future<void> _changePin() async {
    final ok = await verifyCurrentPin(context);
    if (!ok || !mounted) return;
    final created = await createNewPin(context);
    if (created && mounted) _snack('PIN değiştirildi.');
  }

  Future<void> _resetAll() async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Ayarlar sıfırlansın mı?',
      content: 'Görünüm, repo tarayıcı ve önizleme tercihleri varsayılana döner. Hesap ve PIN etkilenmez.',
      confirmLabel: 'Sıfırla',
    );
    if (!ok || !mounted) return;
    final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
    await settingsProv.resetToDefaults();
    if (!mounted) return;
    _commitCtrl.text = settingsProv.settings.defaultCommitMessage;
    _snack('Ayarlar sıfırlandı.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final themeProv = Provider.of<ThemeProvider>(context);
    final settingsProv = Provider.of<SettingsProvider>(context);
    final lock = Provider.of<AppLockProvider>(context);
    final s = settingsProv.settings;

    void set(AppSettings Function(AppSettings) f) => settingsProv.update(f);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ---------------- Hesap ----------------
        _Section(
          title: 'Hesap',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: auth.avatarUrl != null ? NetworkImage(auth.avatarUrl!) : null,
                    child: auth.avatarUrl == null ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.username ?? 'Kullanıcı', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(_tokenKind(auth.token),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(foregroundColor: theme.colorScheme.error, minimumSize: const Size(64, 40)),
                    onPressed: _logout,
                    child: const Text('Çıkış'),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Token\'ları GitHub\'da yönet'),
              subtitle: const Text('Süre, yetki ve iptal ayarları'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openExternalUrl(context, 'https://github.com/settings/tokens'),
            ),
            ListTile(
              leading: const Icon(Icons.speed_outlined),
              title: const Text('GitHub API kotası'),
              subtitle: Text(_rateLoading
                  ? 'Sorgulanıyor...'
                  : _rateError ??
                      (_rate == null
                          ? 'Kalan istek hakkını görmek için dokunun'
                          : '${_rate!.remaining} / ${_rate!.limit} kalan'
                              '${_rate!.resetAt != null ? ' · sıfırlanma ${_hhmm(_rate!.resetAt!)}' : ''}')),
              trailing: const Icon(Icons.refresh, size: 18),
              onTap: _loadRate,
            ),
          ],
        ),

        // ---------------- Görünüm ----------------
        _Section(
          title: 'Görünüm',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {themeProv.themeMode},
                onSelectionChanged: (set) => themeProv.setThemeMode(set.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vurgu rengi', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < AppSettings.accentPalette.length; i++)
                        Semantics(
                          label: AppSettings.accentNames[i],
                          selected: s.accentIndex == i,
                          button: true,
                          child: GestureDetector(
                            onTap: () {
                              settingsProv.tap();
                              set((c) => c.copyWith(accentIndex: i));
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Color(AppSettings.accentPalette[i]),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: s.accentIndex == i ? theme.colorScheme.onSurface : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: s.accentIndex == i ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.contrast),
              title: const Text('AMOLED siyah'),
              subtitle: const Text('Koyu temada saf siyah zemin'),
              value: s.amoledDark,
              onChanged: (v) => set((c) => c.copyWith(amoledDark: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('Dokunsal geri bildirim'),
              subtitle: const Text('Seçim ve başarılı işlemlerde hafif titreşim'),
              value: s.haptics,
              onChanged: (v) => set((c) => c.copyWith(haptics: v)),
            ),
          ],
        ),

        // ---------------- Commit ----------------
        _Section(
          title: 'Commit',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Yazar adı'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Yazar e-postası'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _commitCtrl,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Varsayılan commit mesajı',
                      helperText: 'Boş bırakılırsa her ekran kendi metnini kullanır',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 42)),
                      onPressed: () {
                        auth.updateAuthorInfo(_nameCtrl.text, _emailCtrl.text);
                        set((c) => c.copyWith(defaultCommitMessage: _commitCtrl.text.trim()));
                        _snack('Commit ayarları kaydedildi.');
                      },
                      child: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ---------------- Repo ve dosyalar ----------------
        _Section(
          title: 'Repo ve dosyalar',
          children: [
            ListTile(
              leading: const Icon(Icons.sort),
              title: const Text('Dosya sıralaması'),
              subtitle: Text('${s.repoSort.label} · klasörler her zaman üstte'),
              onTap: () async {
                final v = await _pick<RepoSortMode>(
                    'Dosya sıralaması', {for (final m in RepoSortMode.values) m: m.label}, s.repoSort);
                if (v != null) set((c) => c.copyWith(repoSort: v));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('Gizli (.) dosyaları göster'),
              value: s.showHiddenFiles,
              onChanged: (v) => set((c) => c.copyWith(showHiddenFiles: v)),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Depo listesi sıralaması'),
              subtitle: Text(s.repoListSort.label),
              onTap: () async {
                final v = await _pick<RepoListSort>(
                    'Depo listesi sıralaması', {for (final m in RepoListSort.values) m: m.label}, s.repoListSort);
                if (v != null) set((c) => c.copyWith(repoListSort: v));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.history_toggle_off),
              title: const Text('Son depoyu hatırla'),
              subtitle: const Text('Açılışta son seçilen depo ve dal'),
              value: s.rememberLastRepo,
              onChanged: (v) async {
                set((c) => c.copyWith(rememberLastRepo: v));
                if (!v) await _storage.clearLastRepoAndBranch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Önizleme boyut sınırı'),
              subtitle: Text('${s.previewMaxKb} KB üstü dosyalar indirilmez'),
              onTap: () async {
                final v = await _pick<int>(
                  'Önizleme boyut sınırı',
                  {for (final k in AppSettings.previewMaxKbOptions) k: k >= 1024 ? '${k ~/ 1024} MB' : '$k KB'},
                  s.previewMaxKb,
                );
                if (v != null) set((c) => c.copyWith(previewMaxKb: v));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wrap_text),
              title: const Text('Önizlemede satır kaydır'),
              value: s.previewWrapLines,
              onChanged: (v) => set((c) => c.copyWith(previewWrapLines: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.format_size),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      min: 10,
                      max: 18,
                      divisions: 8,
                      value: s.previewFontSize,
                      label: '${s.previewFontSize.round()} pt',
                      onChanged: (v) => set((c) => c.copyWith(previewFontSize: v)),
                    ),
                  ),
                  Text('${s.previewFontSize.round()} pt', style: AppTheme.monoStyle),
                ],
              ),
            ),
          ],
        ),

        // ---------------- Güvenlik ----------------
        _Section(
          title: 'Güvenlik',
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('Uygulama kilidi (PIN)'),
              subtitle: const Text('Açılışta ve arka plandan dönünce 6 haneli PIN ister'),
              value: lock.enabled,
              onChanged: _toggleLock,
            ),
            if (lock.enabled) ...[
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('PIN\'i değiştir'),
                onTap: _changePin,
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Otomatik kilitlenme'),
                subtitle: Text(_timeoutLabel(s.lockTimeoutSeconds)),
                onTap: () async {
                  final v = await _pick<int>(
                    'Arka plandan dönünce kilitle',
                    {for (final t in AppSettings.lockTimeoutOptions) t: _timeoutLabel(t)},
                    s.lockTimeoutSeconds,
                  );
                  if (v == null) return;
                  await settingsProv.update((c) => c.copyWith(lockTimeoutSeconds: v));
                  await lock.syncSettings(settingsProv.settings);
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_clock),
                title: const Text('Şimdi kilitle'),
                onTap: lock.lockNow,
              ),
            ],
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Kullanılmazsa oturumu kapat'),
              subtitle: Text(s.autoLogoutDays == 0 ? 'Kapalı' : '${s.autoLogoutDays} gün açılmazsa token silinir'),
              onTap: () async {
                final v = await _pick<int>(
                  'Otomatik oturum kapatma',
                  {for (final d in AppSettings.autoLogoutOptions) d: d == 0 ? 'Kapalı' : '$d gün'},
                  s.autoLogoutDays,
                );
                if (v != null) set((c) => c.copyWith(autoLogoutDays: v));
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Güvenlik özeti'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Nasıl korunuyorsunuz?'),
                  content: const SingleChildScrollView(
                    child: Text(
                      '• Token Android Keystore ile şifreli saklanır; ekranda gösterilmez.\n'
                      '• Token yalnızca https://api.github.com adresine gönderilir.\n'
                      '• Gönderimden önce .env, anahtar ve token içeren dosyalar taranır; bulunursa push durur.\n'
                      '• Silme ve taşıma işlemleri tek commit\'tir; dal arada değişirse hiçbir şey ezilmez.\n'
                      '• PIN düz metin tutulmaz (tuzlu, 20.000 turlu SHA-256); 5 hatadan sonra bekleme süresi artar.\n'
                      '• Uygulama yedeklemesi ve düz HTTP kapalıdır.\n\n'
                      'Mümkünse süresi kısa, yalnızca gerekli depolara yetkili fine-grained token kullanın.',
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
                ),
              ),
            ),
          ],
        ),

        // ---------------- Veri ----------------
        _Section(
          title: 'Veri ve kısayollar',
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Geçmiş kayıt sınırı'),
              subtitle: Text('Son ${s.historyLimit} gönderim saklanır'),
              onTap: () async {
                final v = await _pick<int>(
                  'Geçmiş kayıt sınırı',
                  {for (final n in AppSettings.historyLimitOptions) n: '$n kayıt'},
                  s.historyLimit,
                );
                if (v != null) set((c) => c.copyWith(historyLimit: v));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Geçmişi temizle'),
              onTap: () async {
                final upload = Provider.of<UploadProvider>(context, listen: false);
                final ok = await ConfirmDialog.show(
                  context,
                  title: 'Geçmiş temizlensin mi?',
                  content: 'Tüm yerel gönderim kayıtları silinecek.',
                  isDestructive: true,
                );
                if (ok) {
                  await upload.clearHistory();
                  _snack('Geçmiş temizlendi.');
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Hazır klasör kısayolları', style: theme.textTheme.bodyMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _shortcuts.length; i++)
                    Chip(
                      label: Text(_shortcuts[i]),
                      onDeleted: () async {
                        final updated = List<String>.from(_shortcuts)..removeAt(i);
                        await _storage.saveShortcuts(updated);
                        setState(() => _shortcuts = updated);
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _shortcutCtrl,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'Yeni kısayol (ör. docs/)', isDense: true),
                      onSubmitted: (_) => _addShortcut(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _addShortcut, icon: const Icon(Icons.add)),
                  IconButton(
                    tooltip: 'Varsayılana dön',
                    onPressed: () async {
                      await _storage.resetShortcuts();
                      await _loadShortcuts();
                    },
                    icon: const Icon(Icons.restore),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Ayarları sıfırla'),
              onTap: _resetAll,
            ),
          ],
        ),

        // ---------------- Hakkında ----------------
        _Section(
          title: 'Hakkında',
          children: [
            const ListTile(
              leading: GitpushLogo(size: 40),
              title: Text('Gitpush'),
              subtitle: Text('Sürüm $kAppVersion · Android odaklı mobil Git istemcisi'),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Açık kaynak lisansları'),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Gitpush',
                applicationVersion: kAppVersion,
                applicationIcon: const Padding(padding: EdgeInsets.all(12), child: GitpushLogo(size: 56)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addShortcut() async {
    final added = await _storage.addShortcut(_shortcutCtrl.text);
    if (!mounted) return;
    if (added) {
      _shortcutCtrl.clear();
      await _loadShortcuts();
    } else {
      _snack('Geçersiz veya zaten var.');
    }
  }

  static String _hhmm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _timeoutLabel(int sec) {
    if (sec == 0) return 'Her seferinde (dosya seçici sonrası da)';
    if (sec < 60) return '$sec saniye sonra';
    return '${sec ~/ 60} dakika sonra';
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Text(
              title.toUpperCase(),
              style: AppTheme.monoBold.copyWith(fontSize: 11.5, letterSpacing: 1.0, color: theme.colorScheme.primary),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}
