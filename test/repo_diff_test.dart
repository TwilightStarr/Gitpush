import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/models/git_file.dart';
import 'package:gitpush/models/repo_tree.dart';
import 'package:gitpush/services/repo_diff.dart';
import 'test_helpers.dart';

RepoTreeIndex indexOf(List<Map<String, dynamic>> entries) => RepoTreeIndex.fromEntries(entries);

void main() {
  test('sınıflandırma: 10 dosyalı repo, 4 aynı / 3 farklı / 3 yeni -> +3 ~3 =4', () {
    final repoEntries = <Map<String, dynamic>>[
      for (var i = 0; i < 10; i++) blobEntry('f$i.txt', 'icerik $i'),
    ];
    final files = <GitFileItem>[
      for (var i = 0; i < 4; i++) fileItem('f$i.txt', 'icerik $i'), // aynı
      for (var i = 4; i < 7; i++) fileItem('f$i.txt', 'FARKLI $i'), // farklı
      for (var i = 0; i < 3; i++) fileItem('yeni$i.txt', 'yeni $i'), // yeni
    ];

    RepoDiff.classify(files, indexOf(repoEntries));
    final plan = PushPlan.build(files);

    expect(plan.adds.length, 3);
    expect(plan.updates.length, 3);
    expect(plan.unchanged.length, 4);
    expect(plan.hasBlockers, isFalse);
    expect(plan.updates.every((f) => f.remoteSha != null), isTrue);
  });

  test('ağaç bilinmiyorsa (null) durum bilinmez ve plan engellenir', () {
    final files = [fileItem('a.txt', 'x')];
    RepoDiff.classify(files, null);
    expect(files.first.statusKnown, isFalse);
    expect(PushPlan.build(files).treeUnknown, isTrue);
    expect(PushPlan.build(files).hasBlockers, isTrue);
  });

  test('klasör hedefi: lib/screens/ dosya adı eklenir; lib/screens birebir klasörse çakışma', () {
    final idx = indexOf([treeEntry('lib'), treeEntry('lib/screens'), blobEntry('lib/screens/x.dart', 'x')]);

    final withSlash = fileItem('lib/screens/', 'a', name: 'a.dart');
    final bare = fileItem('lib/screens', 'a', name: 'a.dart');
    RepoDiff.classify([withSlash, bare], idx);

    expect(withSlash.targetPath, 'lib/screens/a.dart');
    expect(withSlash.status, GitFileStatus.isNew);
    expect(bare.status, GitFileStatus.conflict);
    expect(bare.conflictMessage, contains('klasör'));
  });

  test('üst segment dosyaysa çakışma', () {
    final idx = indexOf([blobEntry('lib/a.dart', 'x')]);
    final f = fileItem('lib/a.dart/x.dart', 'y');
    RepoDiff.classify([f], idx);
    expect(f.status, GitFileStatus.conflict);
  });

  test('aynı yola giden dosyalar (büyük/küçük harf duyarsız) çakışır', () {
    final a = fileItem('lib/A.dart', '1');
    final b = fileItem('lib/a.dart', '2');
    RepoDiff.classify([a, b], indexOf([]));
    expect(a.status, GitFileStatus.conflict);
    expect(b.status, GitFileStatus.conflict);
  });

  test('yeni klasör / kök dosyası ayrımı', () {
    final idx = indexOf([treeEntry('lib'), blobEntry('lib/a.dart', 'x')]);
    final inExisting = fileItem('lib/b.dart', '1');
    final inNew = fileItem('yeni/b.dart', '1');
    final root = fileItem('kok.txt', '1');
    RepoDiff.classify([inExisting, inNew, root], idx);
    expect(inExisting.status, GitFileStatus.isNew);
    expect(inNew.status, GitFileStatus.newFolder);
    expect(root.status, GitFileStatus.isNew);
  });

  test('değişmeyen dosyalar: hepsi aynıysa plan değişiklik içermez', () {
    final idx = indexOf([blobEntry('a.txt', 'x'), blobEntry('b.txt', 'y')]);
    final files = [fileItem('a.txt', 'x'), fileItem('b.txt', 'y')];
    RepoDiff.classify(files, idx);
    final plan = PushPlan.build(files);
    expect(plan.hasChanges, isFalse);
    expect(plan.unchanged.length, 2);
    expect(plan.pushItems, isEmpty);
  });

  test('ZIP silme adayları: yalnızca önek kapsamı, kökteki gevşek dosyalar silinmez', () {
    final idx = indexOf([
      treeEntry('src'),
      blobEntry('src/a.dart', 'a'),
      blobEntry('src/eski.dart', 'e'),
      blobEntry('README.md', 'r'),
      blobEntry('baska/b.dart', 'b'),
    ]);

    final withPrefix = RepoDiff.computeUnlistedDeletes(
      index: idx,
      zipEffectivePaths: ['src/a.dart'],
      normalizedPrefix: 'src/',
    );
    expect(withPrefix.map((f) => f.repoPath), ['src/eski.dart']);

    final noPrefix = RepoDiff.computeUnlistedDeletes(
      index: idx,
      zipEffectivePaths: ['src/a.dart', 'yeni.txt'],
      normalizedPrefix: '',
    );
    expect(noPrefix.map((f) => f.repoPath), ['src/eski.dart']);
  });

  test('50 MB üstü dosya çakışma olarak işaretlenir', () {
    final f = GitFileItem(
      localPath: 'big.bin',
      repoPath: 'big.bin',
      size: 51 * 1024 * 1024,
      bytes: bytesOf('x'),
    );
    RepoDiff.classify([f], indexOf([]));
    expect(f.status, GitFileStatus.conflict);
  });
}
