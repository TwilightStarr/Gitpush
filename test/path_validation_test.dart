import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/utils/path_validation.dart';

void main() {
  group('normalizeAndValidateGitPath', () {
    test('ters eğik çizgi, baştaki/sondaki/tekrarlı eğik çizgiler temizlenir', () {
      final r = normalizeAndValidateGitPath('\\lib//screens\\a.dart/');
      expect(r.isValid, isTrue);
      expect(r.normalizedPath, 'lib/screens/a.dart');
    });

    test('boş yol, yalnızca eğik çizgi, . ve .. reddedilir', () {
      expect(normalizeAndValidateGitPath('   ').isValid, isFalse);
      expect(normalizeAndValidateGitPath('///').isValid, isFalse);
      expect(normalizeAndValidateGitPath('a/../b').isValid, isFalse);
      expect(normalizeAndValidateGitPath('a/./b').isValid, isFalse);
    });

    test('geçersiz karakter, .git segmenti ve 400+ karakter reddedilir', () {
      expect(normalizeAndValidateGitPath('a/b?.dart').isValid, isFalse);
      expect(normalizeAndValidateGitPath('a/.GIT/config').isValid, isFalse);
      expect(normalizeAndValidateGitPath('a' * 401).isValid, isFalse);
      expect(normalizeAndValidateGitPath('a' * 400).isValid, isTrue);
    });
  });

  test('findDuplicatePaths büyük/küçük harf duyarsız', () {
    final dups = findDuplicatePaths(['lib/A.dart', 'lib/a.dart', 'lib/b.dart']);
    expect(dups, ['lib/a.dart']);
  });

  test('appendFileNameIfFolder yalnızca eğik çizgiyle biten yollara ekler', () {
    expect(appendFileNameIfFolder('lib/screens/', 'a.dart'), 'lib/screens/a.dart');
    expect(appendFileNameIfFolder('/', 'a.dart'), '/a.dart');
    expect(appendFileNameIfFolder('lib/screens', 'a.dart'), 'lib/screens');
    expect(appendFileNameIfFolder('', 'a.dart'), '');
  });

  test('normalizeFolderPrefix', () {
    expect(normalizeFolderPrefix(''), '');
    expect(normalizeFolderPrefix('/src'), 'src/');
    expect(normalizeFolderPrefix('a\\b//'), 'a/b/');
  });
}
