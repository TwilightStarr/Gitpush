import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/models/app_settings.dart';
import 'package:gitpush/services/app_lock_service.dart';

void main() {
  test('ayarlar JSON gidiş-dönüş', () {
    const s = AppSettings(accentIndex: 3, amoledDark: true, repoSort: RepoSortMode.sizeDesc, historyLimit: 100);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.accentIndex, 3);
    expect(back.amoledDark, isTrue);
    expect(back.repoSort, RepoSortMode.sizeDesc);
    expect(back.historyLimit, 100);
  });

  test('bozuk / geçersiz değerler varsayılana döner', () {
    expect(AppSettings.fromJson('{bozuk').historyLimit, 50);
    final s = AppSettings.fromMap({'accentIndex': 99, 'historyLimit': 7, 'repoSort': 'yok', 'previewFontSize': 500});
    expect(s.accentIndex, 0);
    expect(s.historyLimit, 50);
    expect(s.repoSort, RepoSortMode.nameAsc);
    expect(s.previewFontSize, 18);
  });

  test('önizleme sınırı: özel değer korunur, aralık dışı varsayılana döner', () {
    expect(AppSettings.fromMap({'previewMaxKb': 7000}).previewMaxKb, 7000);
    expect(AppSettings.fromMap({'previewMaxKb': 102400}).previewMaxKb, 102400);
    expect(AppSettings.fromMap({'previewMaxKb': 102401}).previewMaxKb, 512);
    expect(AppSettings.fromMap({'previewMaxKb': 0}).previewMaxKb, 512);
    expect(AppSettings.fromMap({'previewMaxKb': 'x'}).previewMaxKb, 512);
    const s = AppSettings(previewMaxKb: 30000);
    expect(AppSettings.fromJson(s.toJson()).previewMaxKb, 30000);
    expect(AppSettings.formatKb(512), '512 KB');
    expect(AppSettings.formatKb(5120), '5 MB');
    expect(AppSettings.formatKb(1536), '1.5 MB');
  });

  test('PIN karması tuza bağlıdır ve doğrulanır', () {
    final a = AppLockService.hashPin('492817', [1, 2, 3], rounds: 10);
    final b = AppLockService.hashPin('492817', [1, 2, 4], rounds: 10);
    expect(a, isNot(b));
    expect(AppLockService.constantTimeEquals(a, AppLockService.hashPin('492817', [1, 2, 3], rounds: 10)), isTrue);
    expect(AppLockService.constantTimeEquals(a, b), isFalse);
  });

  test('PIN kuralları ve bekleme süresi', () {
    expect(AppLockService.isValidPin('123456'), isTrue);
    expect(AppLockService.isValidPin('12345'), isFalse);
    expect(AppLockService.isWeakPin('111111'), isTrue);
    expect(AppLockService.isWeakPin('123456'), isTrue);
    expect(AppLockService.isWeakPin('492817'), isFalse);
    expect(AppLockService.lockoutFor(4), Duration.zero);
    expect(AppLockService.lockoutFor(5), const Duration(seconds: 30));
    expect(AppLockService.lockoutFor(6), const Duration(seconds: 60));
    expect(AppLockService.lockoutFor(99), const Duration(seconds: 30 * 64));
  });
}
