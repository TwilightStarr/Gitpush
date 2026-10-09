import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/github_device_flow.dart';
import '../theme/app_theme.dart';
import '../utils/url_utils.dart';
import '../widgets/gitpush_logo.dart';
import 'main_shell.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  bool _obscureToken = true;

  /// true: yalnızca herkese açık depolar (`public_repo`), false: tüm depolar (`repo`).
  bool _publicOnly = false;

  @override
  void dispose() {
    _clientIdController.dispose();
    _tokenController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: controller,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'GitHub Token Nasıl Alınır?',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text('1. GitHub hesabınızda sağ üstteki profilinize tıklayın.'),
                  const SizedBox(height: 6),
                  const Text('2. Settings -> Developer settings -> Personal access tokens -> Tokens (classic) yolunu izleyin.'),
                  const SizedBox(height: 6),
                  const Text('3. "Generate new token (classic)" butonuna basın.'),
                  const SizedBox(height: 6),
                  const Text('4. Gerekli İzinler (Scopes):'),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• repo (Zorunlu: depolara erişim, commit ve Actions çalışmalarını okuma/tetikleme)', style: AppTheme.monoBold.copyWith(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('• workflow (.github/workflows/ altındaki dosyaları göndermek/değiştirmek için; yoksa GitHub bu dosyaları reddeder)', style: AppTheme.monoBold.copyWith(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text("5. \"Generate token\" deyip ghp_ ile başlayan tokenı kopyalayın ve Gitpush'a yapıştırın."),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () async {
                      await openExternalUrl(
                        context,
                        'https://github.com/settings/tokens/new?scopes=repo,workflow&description=Gitpush%20App',
                      );
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('GitHub Token Sayfasını Aç'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Client ID girilmesini ister. Kaydedilirse `true` döner.
  Future<bool> _promptClientId() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _clientIdController.text = auth.effectiveClientId;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('GitHub ile giriş kurulumu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Token yapıştırmadan girmek için ücretsiz bir OAuth App gerekir (tek seferlik, 1 dakika):'),
                const SizedBox(height: 8),
                const Text(
                  '1. GitHub → Settings → Developer settings → OAuth Apps → New OAuth App\n'
                  '2. Callback URL olarak https://github.com yazın\n'
                  '3. Oluşturunca "Enable Device Flow" kutusunu işaretleyin\n'
                  "4. Client ID'yi aşağıya yapıştırın (Client secret gerekmez)",
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => openExternalUrl(ctx, 'https://github.com/settings/applications/new'),
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('OAuth App oluştur'),
                ),
                TextField(
                  controller: _clientIdController,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppTheme.monoStyle.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Client ID',
                    hintText: 'Ov23li...',
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await auth.setClientId(_clientIdController.text);
                if (ok) {
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } else {
                  setDialogState(() => errorText = 'Geçersiz Client ID biçimi');
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    return saved ?? false;
  }

  Future<void> _handleDeviceLogin() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // Client ID yoksa (derlemede gömülü değil, kullanıcı da girmemiş) önce iste.
    if (!auth.deviceFlowAvailable) {
      final ok = await _promptClientId();
      if (!ok || !mounted) return;
    }

    final success = await auth.loginWithDeviceFlow(
      authorName: _nameController.text.trim(),
      authorEmail: _emailController.text.trim(),
      scope: _publicOnly ? GitHubDeviceFlow.scopePublic : GitHubDeviceFlow.scopeAll,
      onCode: (info) async {
        // Kod panoya kopyalanır ve GitHub doğrulama sayfası açılır.
        await Clipboard.setData(ClipboardData(text: info.userCode));
        if (mounted) await openExternalUrl(context, info.verificationUri);
      },
    );
    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  Widget _buildDeviceFlowSection(BuildContext context, AuthProvider auth) {
    final theme = Theme.of(context);
    final info = auth.deviceInfo;

    if (info != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              "GitHub'da bu kodu girin",
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            SelectableText(
              info.userCode,
              style: AppTheme.monoBold.copyWith(fontSize: 28, letterSpacing: 3),
            ),
            const SizedBox(height: 6),
            Text(
              'Kod panoya kopyalandı. Onayladığınızda uygulama otomatik giriş yapar.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openExternalUrl(context, info.verificationUri),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text("GitHub'ı Aç"),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: auth.cancelDeviceFlow,
                  child: const Text('İptal'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<bool>(value: false, label: Text('Tüm depolar')),
            ButtonSegment<bool>(value: true, label: Text('Yalnız herkese açık')),
          ],
          selected: {_publicOnly},
          onSelectionChanged: (selection) => setState(() => _publicOnly = selection.first),
        ),
        const SizedBox(height: 6),
        Text(
          _publicOnly
              ? 'Yalnızca herkese açık (public) depolara erişir; özel depolarınıza dokunamaz.'
              : 'Özel ve herkese açık tüm depolarınıza erişir.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: auth.isLoading ? null : _handleDeviceLogin,
          icon: const Icon(Icons.login),
          label: const Text('GitHub ile Giriş Yap'),
        ),
        if (auth.canEditClientId)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: auth.isLoading ? null : _promptClientId,
              child: Text(auth.deviceFlowAvailable ? "Client ID'yi değiştir" : 'Client ID ayarla'),
            ),
          ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen Personal Access Token giriniz.')),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.loginWithToken(
      token: token,
      authorName: _nameController.text.trim(),
      authorEmail: _emailController.text.trim(),
    );

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo ve Başlık
                      const GitpushLogo(size: 84),
                      const SizedBox(height: 16),
                      Text(
                        'Gitpush',
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Telefonda kod yazmadan GitHub reposuna dosya aktarın',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),

                      // 3 Adımlı Gösterge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStepItem(context, '1', 'Giriş Yap'),
                          _buildStepDivider(),
                          _buildStepItem(context, '2', 'Bilgi Gir'),
                          _buildStepDivider(),
                          _buildStepItem(context, '3', 'Doğrula'),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // GitHub ile Giriş (Device Flow) - her zaman görünür; Client ID yoksa ilk dokunuşta istenir
                      ...[
                        _buildDeviceFlowSection(context, auth),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'veya token ile',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Token Alanı
                      TextField(
                        controller: _tokenController,
                        obscureText: _obscureToken,
                        // Token klavye önerilerine / öğrenme sözlüğüne / otomatik
                        // doldurmaya sızmasın
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                        keyboardType: TextInputType.visiblePassword,
                        style: AppTheme.monoStyle.copyWith(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Personal Access Token',
                          hintText: 'ghp_xxxxxxxxxxxx',
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureToken = !_obscureToken),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Yazar Adı (Opsiyonel)
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Commit Yazar Adı (Opsiyonel)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Yazar E-posta (Opsiyonel)
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Commit Yazar E-postası (Opsiyonel)',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Yardım Butonu
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _showHelpSheet,
                          icon: const Icon(Icons.help_outline, size: 16),
                          label: const Text('Token nasıl alınır?'),
                        ),
                      ),

                      // Hata Mesajı
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          auth.errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Giriş Butonu
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: (auth.isLoading || auth.isDeviceFlowActive) ? null : _handleLogin,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Text('Giriş Yap ve Doğrula'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem(BuildContext context, String number, String label) {
    final theme = Theme.of(context);
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          child: Text(number, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
      ],
    );
  }

  Widget _buildStepDivider() {
    return Container(width: 24, height: 1, color: Colors.grey.shade400);
  }
}
