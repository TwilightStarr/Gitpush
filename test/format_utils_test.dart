import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/utils/format_utils.dart';

// Saf fonksiyonlar oldukları için (dart:io / platform kanalı yok) bu
// testler bir Flutter/Dart SDK'sı ile ilk `flutter test` çalıştırmasında
// başka hiçbir kurulum gerektirmeden geçmelidir — bkz. README > YGL.
void main() {
  group('formatBytes', () {
    test('1 KB altı değerler bayt biriminde kalır', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('KB birimine geçer', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
    });

    test('MB birimine geçer', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('GB birimine geçer', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes(2.5 * 1024 * 1024 * 1024), '2.50 GB');
    });
  });

  group('formatDuration', () {
    test('1 dakikadan kısa süreler için "< 1 dk" döner', () {
      expect(formatDuration(const Duration(seconds: 30)), '< 1 dk');
      expect(formatDuration(Duration.zero), '< 1 dk');
    });

    test('yalnızca dakika içeren süreler', () {
      expect(formatDuration(const Duration(minutes: 42)), '42 dk');
    });

    test('tam saat içeren süreler', () {
      expect(formatDuration(const Duration(hours: 2)), '2 sa');
    });

    test('saat + dakika içeren süreler', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 24)), '1 sa 24 dk');
    });
  });
}
