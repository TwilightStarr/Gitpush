import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/models/git_file.dart';
import 'package:gitpush/models/repo_tree.dart';
import 'package:gitpush/providers/upload_provider.dart';
import 'package:gitpush/services/zip_service.dart';
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
  test('ZIP: önizlemeye gir-çık-gir -> önek bir kez uygulanır (çift önek yok)', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([]));
    p.setZipArchive(fileName: 'a.zip', bytes: makeZip({'proje/a.dart': 'a', 'proje/b/c.dart': 'c'}));
    p.setZipPrefix('src/');

    expect(p.zipFiles.map((f) => f.repoPath), ['src/a.dart', 'src/b/c.dart']);

    // "önizleme" iki kez okunur, sonra önek yeniden girilir
    p.planFor(PreviewSource.zip);
    p.planFor(PreviewSource.zip);
    p.setZipPrefix('src/');
    expect(p.zipFiles.map((f) => f.repoPath), ['src/a.dart', 'src/b/c.dart']);

    // strip anahtarı değişince ZIP yeniden ayıklanır (bellekte tutulur)
    p.setZipStripRootDir(false);
    expect(p.zipFiles.first.repoPath, 'src/proje/a.dart');
    p.setZipStripRootDir(true);
    expect(p.zipFiles.first.repoPath, 'src/a.dart');
  });

  test('ZIP: repoyla karşılaştırma ve seçim (+1 ~1 =1)', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([blobEntry('a.txt', 'aynı'), blobEntry('b.txt', 'eski')]));
    p.setZipArchive(
      fileName: 'a.zip',
      bytes: makeZip({'a.txt': 'aynı', 'b.txt': 'yeni içerik', 'c.txt': 'c'}),
    );
    final plan = p.planFor(PreviewSource.zip);
    expect(plan.adds.length, 1);
    expect(plan.updates.length, 1);
    expect(plan.unchanged.length, 1);

    // Ağaç sonradan değişince yeniden sınıflandırılır
    p.reclassifyAll(idx([]));
    expect(p.planFor(PreviewSource.zip).adds.length, 3);
  });

  test('ZIP: overwrite kapalıyken var olan yollar atlanır; silme varsayılan kapalı', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([blobEntry('src/b.txt', 'eski'), blobEntry('src/x.txt', 'x')]));
    p.setZipArchive(fileName: 'a.zip', bytes: makeZip({'b.txt': 'yeni', 'c.txt': 'c'}));
    p.setZipPrefix('src/');
    p.setZipOverwriteExisting(false);

    var plan = p.planFor(PreviewSource.zip);
    expect(plan.skipped.length, 1);
    expect(plan.updates, isEmpty);
    expect(plan.deletes, isEmpty); // silme kapalı

    p.setZipDeleteUnlisted(true);
    plan = p.planFor(PreviewSource.zip);
    expect(plan.deletes.map((f) => f.repoPath), ['src/x.txt']);
    expect(plan.approvedDeletePaths, {'src/x.txt'});
  });

  test('ZIP: bozuk dosya anlamlı hata verir; .. içeren girdi atlanır', () {
    final p = UploadProvider();
    expect(
      () => p.setZipArchive(fileName: 'x.zip', bytes: bytesOf('bu bir zip değil')),
      throwsA(isA<ZipServiceException>()),
    );

    final zip = makeZip({'ok.txt': 'ok', '../evil.txt': 'x'});
    p.setZipArchive(fileName: 'y.zip', bytes: zip);
    expect(p.zipFiles.length, 1);
    expect(p.zipInvalidEntries.length, 1);
  });

  test('Mod B: eşleştirme tam ada göre; tek eşleşme otomatik, çoklu eşleşmede seçim istenir', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([
      treeEntry('lib'),
      treeEntry('test'),
      blobEntry('lib/main.dart', 'x'),
      blobEntry('lib/xmain.dart', 'x'),
      blobEntry('lib/a.dart', 'x'),
      blobEntry('test/a.dart', 'x'),
    ]));

    final main = fileItem('main.dart', 'y');
    final a = fileItem('a.dart', 'y');
    p.addMultiFiles([main, a]);

    expect(main.repoPath, 'lib/main.dart'); // xmain.dart ile karışmaz
    expect(main.status, GitFileStatus.update);
    expect(a.needsChoice, isTrue);
    expect(a.repoPath, 'a.dart');
    expect(a.status, GitFileStatus.conflict); // kullanıcı seçene kadar engelli

    p.updateMultiFilePathById(a.id, 'test/a.dart');
    expect(a.needsChoice, isFalse);
    expect(a.status, GitFileStatus.update);
  });

  test('Mod B: yol değişimi, kısayol, metin komutu; klasör hedefine dosya adı eklenir', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([treeEntry('lib'), treeEntry('lib/screens'), blobEntry('lib/screens/x.dart', 'x')]));
    final f = fileItem('a.dart', 'y');
    p.addMultiFiles([f]);

    p.updateMultiFilePathById(f.id, 'lib/screens'); // klasörle birebir aynı
    expect(f.status, GitFileStatus.conflict);
    expect(p.planFor(PreviewSource.multi).hasBlockers, isTrue);

    p.updateMultiFilePathById(f.id, 'lib/screens/'); // eğik çizgi -> dosya adı eklenir
    expect(f.targetPath, 'lib/screens/a.dart');
    expect(f.status, GitFileStatus.isNew);

    p.applyShortcutToMultiFiles('lib/', {});
    expect(f.repoPath, 'lib/a.dart');

    p.parseAndApplyTextCommands('a.dart=lib/screens\n# yorum');
    expect(f.status, GitFileStatus.conflict); // klasör hedefi yakalanır
    p.parseAndApplyTextCommands('a.dart=lib/screens/');
    expect(f.repoPath, 'lib/screens/a.dart');
    p.parseAndApplyTextCommands('lib/: a.dart');
    expect(f.repoPath, 'lib/a.dart');
  });

  test('Mod B: kısayol yalnızca seçili kimliklere uygulanır', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([]));
    final a = fileItem('a.dart', '1');
    final b = fileItem('b.dart', '2');
    p.addMultiFiles([a, b]);
    p.applyShortcutToMultiFiles('lib/', {b.id});
    expect(a.repoPath, 'a.dart');
    expect(b.repoPath, 'lib/b.dart');
  });

  test('Mod B: Tümünü Kaldır ve Geri Al yolları korur', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([]));
    final a = fileItem('a.dart', '1');
    final b = fileItem('b.dart', '2');
    p.addMultiFiles([a, b]);
    p.updateMultiFilePathById(b.id, 'lib/özel/b.dart');

    final removed = p.clearMultiFiles();
    expect(p.multiFiles, isEmpty);
    expect(removed.length, 2);

    p.restoreMultiFiles(removed);
    expect(p.multiFiles.length, 2);
    expect(p.multiFiles[1].repoPath, 'lib/özel/b.dart');
  });

  test('Mod B: mükerrer hedef yol çakışma sayılır', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([]));
    final a = fileItem('a.dart', '1');
    final b = fileItem('b.dart', '2');
    p.addMultiFiles([a, b]);
    p.updateMultiFilePathById(b.id, 'A.dart');
    expect(a.status, GitFileStatus.conflict);
    expect(b.status, GitFileStatus.conflict);
  });

  test('push sonrası sıfırlama tüm yükleme durumunu temizler', () {
    final p = UploadProvider();
    p.reclassifyAll(idx([]));
    p.setZipArchive(fileName: 'a.zip', bytes: makeZip({'a.txt': 'a'}));
    p.addMultiFiles([fileItem('b.txt', 'b')]);
    p.resetAfterPush();
    expect(p.zipFiles, isEmpty);
    expect(p.zipFileName, isNull);
    expect(p.multiFiles, isEmpty);
  });
}
