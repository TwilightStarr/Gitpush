import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/models/app_settings.dart';
import 'package:gitpush/models/repo_listing.dart';

Map<String, dynamic> blob(String p, int size) => {'path': p, 'type': 'blob', 'size': size, 'sha': 'a' * 40, 'mode': '100644'};
Map<String, dynamic> tree(String p) => {'path': p, 'type': 'tree', 'sha': 'b' * 40, 'mode': '040000'};

void main() {
  final t = [
    blob('zeta.txt', 5),
    blob('README.md', 10),
    tree('lib'),
    blob('lib/main.dart', 100),
    tree('lib/src'),
    blob('lib/src/a.dart', 50),
    tree('assets'),
    blob('assets/logo.png', 2000),
    blob('.gitignore', 3),
    blob('file10.txt', 1),
    blob('file2.txt', 1),
  ];

  test('klasörler dosyalardan önce gelir', () {
    final list = buildDirectoryListing(t, '');
    final firstFileIdx = list.indexWhere((e) => !e.isDir);
    expect(list.take(firstFileIdx).every((e) => e.isDir), isTrue);
    expect(list.skip(firstFileIdx).every((e) => !e.isDir), isTrue);
    expect(list.first.name, 'assets');
  });

  test('klasör özeti iç içe dosyaları sayar', () {
    final lib = buildDirectoryListing(t, '').firstWhere((e) => e.name == 'lib');
    expect(lib.fileCount, 2);
    expect(lib.folderCount, 1);
    expect(lib.size, 150);
  });

  test('doğal sıralama: file2 < file10', () {
    final names = buildDirectoryListing(t, '').where((e) => e.name.startsWith('file')).map((e) => e.name).toList();
    expect(names, ['file2.txt', 'file10.txt']);
  });

  test('gizli dosyalar kapatılabilir', () {
    final list = buildDirectoryListing(t, '', showHidden: false);
    expect(list.any((e) => e.name == '.gitignore'), isFalse);
  });

  test('alt klasör listesi yalnızca doğrudan çocukları verir', () {
    final list = buildDirectoryListing(t, 'lib');
    expect(list.map((e) => e.name), ['src', 'main.dart']);
  });

  test('boyuta göre sıralama', () {
    final files = buildDirectoryListing(t, '', sort: RepoSortMode.sizeDesc).where((e) => !e.isDir).toList();
    expect(files.first.name, 'README.md');
  });

  test('arama klasörleri önce, ad eşleşmesini önde getirir', () {
    final r = searchRepoTree(t, 'a');
    expect(r.first.isDir, isTrue);
    expect(searchRepoTree(t, 'zzz'), isEmpty);
  });

  test('breadcrumbs', () {
    final c = breadcrumbsFor('lib/src');
    expect(c.map((e) => e.path), ['', 'lib', 'lib/src']);
  });

  test('blobsUnder yalnızca blob döndürür', () {
    expect(blobsUnder(t, 'lib').map((e) => e['path']), ['lib/main.dart', 'lib/src/a.dart']);
  });

  test('önizleme türü', () {
    expect(previewKindFor('a.PNG'), PreviewKind.image);
    expect(previewKindFor('a.apk'), PreviewKind.binary);
    expect(previewKindFor('Makefile'), PreviewKind.text);
  });
}
