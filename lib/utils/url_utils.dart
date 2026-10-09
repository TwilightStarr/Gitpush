import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Yalnızca https ve GitHub alan adlarına izin verir. `intent:`, `file:`,
/// `javascript:`, `content:` gibi şemalar veya başka alan adları reddedilir
/// (geçmiş kaydı / API yanıtı üzerinden kötü niyetli bağlantı açılmasını önler).
bool isSafeExternalUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (uri.userInfo.isNotEmpty) return false;
  final host = uri.host.toLowerCase();
  return host == 'github.com' || host.endsWith('.github.com');
}

/// Bağlantıyı harici uygulamada (tarayıcı) açar.
///
/// Ön kontrol (can-launch) bilinçli olarak YAPILMAZ: Android 11+ paket
/// görünürlüğü yüzünden manifestte `<queries>` tanımlı değilse false dönüp
/// sessizce hiçbir şey yapmıyordu. Doğrudan `launchUrl` çağrılır; başarısız
/// olursa kullanıcıya SnackBar + "Kopyala" eylemi gösterilir.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final trimmed = url.trim();

  var opened = false;
  if (trimmed.isNotEmpty) {
    try {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && isSafeExternalUri(uri)) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      opened = false;
    }
  }

  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(
        content: const Text('Link açılamadı.'),
        action: SnackBarAction(
          label: 'Kopyala',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: trimmed));
          },
        ),
      ),
    );
  }
}
