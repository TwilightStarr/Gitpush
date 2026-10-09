import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/utils/secret_guard.dart';
import 'package:gitpush/utils/url_utils.dart';

SecretCandidate _c(String path, String text) =>
    SecretCandidate(path, Uint8List.fromList(utf8.encode(text)));

void main() {
  group('SecretGuard', () {
    test('hassas dosya adlarını yakalar, şablonlara izin verir', () {
      expect(SecretGuard.isSensitiveFileName('.env'), isTrue);
      expect(SecretGuard.isSensitiveFileName('config/.env.production'), isTrue);
      expect(SecretGuard.isSensitiveFileName('.env.example'), isFalse);
      expect(SecretGuard.isSensitiveFileName('android/key.properties'), isTrue);
      expect(SecretGuard.isSensitiveFileName('upload.jks'), isTrue);
      expect(SecretGuard.isSensitiveFileName('lib/main.dart'), isFalse);
    });

    test('içerikte GitHub token yakalar', () {
      final token = 'ghp_${'a' * 36}';
      final f = SecretGuard.scan([_c('lib/a.dart', 'const t = "$token";')]);
      expect(f, hasLength(1));
      expect(f.first.reason, 'GitHub token');
    });

    test('temiz dosyada bulgu yok', () {
      expect(SecretGuard.scan([_c('lib/a.dart', 'void main() {}')]), isEmpty);
    });

    test('ikili dosya taranmaz', () {
      final bytes = Uint8List.fromList([0, 1, 2, 3, 0]);
      expect(SecretGuard.scan([SecretCandidate('a.bin', bytes)]), isEmpty);
    });
  });

  group('isSafeExternalUri', () {
    test('yalnızca https + github', () {
      expect(isSafeExternalUri(Uri.parse('https://github.com/a/b')), isTrue);
      expect(isSafeExternalUri(Uri.parse('https://api.github.com/x')), isTrue);
      expect(isSafeExternalUri(Uri.parse('http://github.com/a')), isFalse);
      expect(isSafeExternalUri(Uri.parse('https://evil.com/github.com')), isFalse);
      expect(isSafeExternalUri(Uri.parse('https://github.com.evil.com/')), isFalse);
      expect(isSafeExternalUri(Uri.parse('intent://x#Intent;end')), isFalse);
      expect(isSafeExternalUri(Uri.parse('file:///etc/passwd')), isFalse);
    });
  });
}
