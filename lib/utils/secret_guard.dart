import 'dart:convert';
import 'dart:typed_data';

/// Gizli bilgilerin (token, .env, özel anahtar vb.) yanlışlıkla repoya
/// gönderilmesini engelleyen son savunma hattı. `src/utils/secretGuard.ts`
/// mantığının Dart karşılığıdır. Yalnızca yüksek güvenilirlikli eşleşmeleri
/// yakalar (yanlış alarm düşük tutulur).
class SecretCandidate {
  final String path;
  final Uint8List bytes;
  const SecretCandidate(this.path, this.bytes);
}

class SecretFinding {
  final String path;
  final String reason;
  const SecretFinding(this.path, this.reason);
}

class SecretGuard {
  static const int _maxScanBytes = 2 * 1024 * 1024;

  static final RegExp _envFile = RegExp(r'^\.env(\..+)?$');
  static final RegExp _safeEnvSuffix =
      RegExp(r'\.(example|sample|template|dist|defaults?)$', caseSensitive: false);
  static final RegExp _keyFileExt = RegExp(r'\.(pem|p12|pfx|jks|keystore|ppk)$');
  static final RegExp _sshKey = RegExp(r'^id_(rsa|dsa|ecdsa|ed25519)$');
  static final RegExp _credJson =
      RegExp(r'^(service-?account|credentials?)[\w.-]*\.json$');

  static final List<MapEntry<String, RegExp>> _patterns = [
    MapEntry('GitHub token', RegExp(r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b')),
    MapEntry('GitHub fine-grained token', RegExp(r'\bgithub_pat_[A-Za-z0-9_]{50,}\b')),
    MapEntry('AWS access key', RegExp(r'\bAKIA[0-9A-Z]{16}\b')),
    MapEntry('Google API key', RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b')),
    MapEntry('Anthropic API key', RegExp(r'\bsk-ant-[A-Za-z0-9_-]{20,}\b')),
    MapEntry('Slack token', RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b')),
    MapEntry('Özel anahtar (private key)', RegExp(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----')),
  ];

  static bool isSensitiveFileName(String path) {
    final base = path.split('/').last.toLowerCase();
    if (_envFile.hasMatch(base)) return !_safeEnvSuffix.hasMatch(base);
    if (_keyFileExt.hasMatch(base)) return true;
    if (_sshKey.hasMatch(base)) return true;
    if (base == 'key.properties' || base == '.netrc' || base == '.pgpass') return true;
    if (_credJson.hasMatch(base)) return true;
    return false;
  }

  static bool _looksBinary(Uint8List bytes) {
    final n = bytes.length < 8000 ? bytes.length : 8000;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  static List<SecretFinding> scan(List<SecretCandidate> files) {
    final findings = <SecretFinding>[];
    for (final f in files) {
      if (isSensitiveFileName(f.path)) {
        findings.add(SecretFinding(f.path, 'Hassas dosya adı'));
        continue;
      }
      if (f.bytes.length > _maxScanBytes || _looksBinary(f.bytes)) continue;
      final text = utf8.decode(f.bytes, allowMalformed: true);
      for (final p in _patterns) {
        if (p.value.hasMatch(text)) {
          findings.add(SecretFinding(f.path, p.key));
          break;
        }
      }
    }
    return findings;
  }

  static String formatError(List<SecretFinding> findings) {
    final shown = findings.take(5).map((f) => '${f.path} (${f.reason})').join(', ');
    final more = findings.length > 5 ? ' ve ${findings.length - 5} dosya daha' : '';
    return 'Gizli bilgi içerebilecek dosya(lar) tespit edildi, push engellendi: '
        '$shown$more. Bu dosyaları listeden çıkarın veya içindeki anahtarları '
        'kaldırıp tekrar deneyin.';
  }
}
