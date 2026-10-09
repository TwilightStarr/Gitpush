import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/models/git_file.dart';
import 'package:gitpush/models/repo_tree.dart';
import 'package:gitpush/providers/upload_provider.dart';
import 'test_helpers.dart';

Uint8List makeZip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final data = bytesOf(content);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

RepoTreeIndex idx(List<Map<String, dynamic>> e) => RepoTreeIndex.fromEntries(e);

void main() {
  test('ZIP: iç içe fazla klasör otomatik kaldırılır -> Yeni yerine Güncelleme', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([
      treeEntry('lib'),
      blobEntry('lib/a.dart', 'eski'),
      blobEntry('lib/b.dart', 'b'),
      blobEntry('pubspec.yaml', 'p'),
    ]));
    // Tek kök yok (iki farklı üst klasör), bu yüzden klasik "kök soyma" yetmez.
    p.setZipArchive(
      fileName: 'x.zip',
      bytes: makeZip({
        'proje/kaynak/lib/a.dart': 'yeni',
        'proje/kaynak/lib/b.dart': 'b',
        'proje/kaynak/pubspec.yaml': 'p',
        'proje/notlar.txt': 'n',
      }),
    );
    final plan = p.planFor(PreviewSource.zip);
    expect(plan.updates.map((f) => f.repoPath), ['lib/a.dart']);
    expect(plan.unchanged.length, 2);
    expect(p.zipAlignNotice, isNotNull);
  });

  test('ZIP: repoda ek üst klasör varsa (app/) önek otomatik eklenir', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([
      treeEntry('app'),
      treeEntry('app/lib'),
      blobEntry('app/lib/a.dart', 'eski'),
      blobEntry('app/lib/b.dart', 'eski'),
    ]));
    p.setZipArchive(
      fileName: 'x.zip',
      bytes: makeZip({'lib/a.dart': 'yeni', 'lib/b.dart': 'yeni'}),
    );
    expect(p.zipFiles.map((f) => f.repoPath), ['app/lib/a.dart', 'app/lib/b.dart']);
    expect(p.planFor(PreviewSource.zip).updates.length, 2);
  });

  test('ZIP: otomatik eşleştirme kapatılabilir; hedef klasör doluysa uygulanmaz', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([
      treeEntry('app'),
      blobEntry('app/a.dart', 'eski'),
      blobEntry('app/b.dart', 'eski'),
    ]));
    p.setZipArchive(fileName: 'x.zip', bytes: makeZip({'a.dart': 'y', 'b.dart': 'y'}));
    expect(p.zipFiles.first.repoPath, 'app/a.dart');

    p.setZipAutoAlign(false);
    expect(p.zipFiles.first.repoPath, 'a.dart');
    expect(p.zipAlignNotice, isNull);

    p.setZipAutoAlign(true);
    p.setZipPrefix('baska/');
    expect(p.zipFiles.first.repoPath, 'baska/a.dart');
  });

  test('ZIP: gerçekten yeni projede (eşleşme yok) yollar değişmez', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([blobEntry('README.md', 'r'), blobEntry('docs/README.md', 'r')]));
    p.setZipArchive(
      fileName: 'x.zip',
      bytes: makeZip({'src/a.dart': '1', 'src/b.dart': '2', 'docs/c.dart': '3'}),
    );
    expect(p.zipFiles.first.repoPath, 'src/a.dart');
    expect(p.zipAlignment, isNull);
    expect(p.planFor(PreviewSource.zip).adds.length, 3);
  });

  test('ZIP: yalnızca harf büyüklüğü farkı repodaki yola uydurulur', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([blobEntry('README.md', 'eski')]));
    p.setZipArchive(fileName: 'x.zip', bytes: makeZip({'readme.md': 'yeni'}));
    expect(p.zipFiles.first.repoPath, 'README.md');
    expect(p.planFor(PreviewSource.zip).updates.length, 1);
  });

  test('Mod B: ağaç dosyalardan SONRA yüklenirse eşleşme yeniden yapılır', () {
    final p = UploadProvider();
    p.reclassifyAll(null); // ağaç henüz yok
    final f = fileItem('main.dart', 'y');
    p.addMultiFiles([f]);
    expect(f.repoPath, 'main.dart');

    p.reclassifyAll(idx([treeEntry('lib'), blobEntry('lib/main.dart', 'x')]));
    expect(f.repoPath, 'lib/main.dart');
    expect(f.status, GitFileStatus.update);
  });

  test('Mod B: elle belirlenen yol ağaç yenilenince bozulmaz', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([treeEntry('lib'), blobEntry('lib/main.dart', 'x')]));
    final f = fileItem('main.dart', 'y');
    p.addMultiFiles([f]);
    p.updateMultiFilePathById(f.id, 'baska/main.dart');
    p.reclassifyAll(idx([treeEntry('lib'), blobEntry('lib/main.dart', 'x')]));
    expect(f.repoPath, 'baska/main.dart');
  });

  test('Mod B: "main (1).dart" ve harf farkı repodaki dosyayla eşleşir', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([
      treeEntry('lib'),
      blobEntry('lib/main.dart', 'x'),
      blobEntry('lib/Utils.dart', 'x'),
    ]));
    final a = fileItem('main (1).dart', 'y', name: 'main (1).dart');
    final b = fileItem('utils.dart', 'y');
    p.addMultiFiles([a, b]);
    expect(a.repoPath, 'lib/main.dart');
    expect(b.repoPath, 'lib/Utils.dart');
    expect(a.status, GitFileStatus.update);
  });
}
