import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gitpush/models/git_file.dart';
import 'package:gitpush/services/github_service.dart';
import 'test_helpers.dart';

http.Response jsonRes(Object body, [int status = 200, Map<String, String>? headers]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json', ...?headers},
  );
}

/// Sahte GitHub: istekleri kaydeder, durum kodlarını test başına ayarlanır.
class FakeGitHub {
  final List<String> log = [];
  int refStatus = 200;
  int commitStatus = 200;
  int treesGetStatus = 200;
  int patchStatus = 200;
  int treesPostStatus = 201;
  String treesPostMessage = 'Validation Failed';
  int blobFailuresBeforeSuccess = 0;

  List<Map<String, dynamic>> baseEntries = [];
  List<Map<String, dynamic>> newEntries = [];
  bool baseTruncated = false;

  int blobCount = 0;
  Map<String, dynamic>? lastTreeBody;
  Map<String, dynamic>? lastCommitBody;

  bool called(String key) => log.contains(key);

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    log.add(key);

    switch (key) {
      case 'GET /repos/o/r/git/ref/heads/main':
        if (refStatus == 200) return jsonRes({'object': {'sha': 'parent1'}});
        return jsonRes({'message': 'Not Found'}, refStatus);
      case 'GET /repos/o/r/git/commits/parent1':
        if (commitStatus == 200) return jsonRes({'tree': {'sha': 'basetree'}});
        return jsonRes({'message': 'Server Error'}, commitStatus);
      case 'GET /repos/o/r/git/trees/basetree':
        if (treesGetStatus != 200) return jsonRes({'message': 'Forbidden'}, treesGetStatus);
        return jsonRes({'tree': baseEntries, 'truncated': baseTruncated});
      case 'GET /repos/o/r/git/trees/newtree':
        return jsonRes({'tree': newEntries, 'truncated': false});
      case 'POST /repos/o/r/git/blobs':
        if (blobFailuresBeforeSuccess > 0) {
          blobFailuresBeforeSuccess--;
          return jsonRes({'message': 'You have exceeded a secondary rate limit'}, 403, {'retry-after': '1'});
        }
        blobCount++;
        return jsonRes({'sha': 'blob$blobCount'}, 201);
      case 'POST /repos/o/r/git/trees':
        lastTreeBody = jsonDecode(req.body) as Map<String, dynamic>;
        if (treesPostStatus == 201) return jsonRes({'sha': 'newtree'}, 201);
        return jsonRes({'message': treesPostMessage}, treesPostStatus);
      case 'POST /repos/o/r/git/commits':
        lastCommitBody = jsonDecode(req.body) as Map<String, dynamic>;
        return jsonRes({'sha': 'newcommit'}, 201);
      case 'PATCH /repos/o/r/git/refs/heads/main':
        if (patchStatus == 200) return jsonRes({'ref': 'refs/heads/main'});
        return jsonRes({'message': 'Update is not a fast forward'}, patchStatus);
      case 'POST /repos/o/r/git/refs':
        return jsonRes({'ref': 'refs/heads/main'}, 201);
    }
    return jsonRes({'message': 'unexpected $key'}, 500);
  }
}

List<Map<String, dynamic>> makeBase() {
  return [
    treeEntry('dir1'),
    treeEntry('dir2'),
    for (var i = 0; i < 25; i++) blobEntry('dir1/f$i.txt', 'a$i'),
    for (var i = 0; i < 25; i++) blobEntry('dir2/f$i.txt', 'b$i'),
  ];
}

GitHubService serviceFor(FakeGitHub fake, {List<Duration>? sleeps}) {
  return GitHubService(
    client: MockClient(fake.handle),
    sleep: (d) async => sleeps?.add(d),
  );
}

Future<dynamic> push(
  GitHubService s,
  List<GitFileItem> files, {
  Set<String> deletes = const <String>{},
  String? name,
  String? email,
}) {
  return s.executeAtomicPush(
    token: 't',
    owner: 'o',
    repo: 'r',
    branch: 'main',
    commitMessage: 'msg',
    filesToPush: files,
    approvedDeletePaths: deletes,
    authorName: name,
    authorEmail: email,
    onProgress: (step, current, total) {},
  );
}

void main() {
  test('ağaç isteği 403 dönerse getRecursiveTree hata fırlatır (boş liste dönmez)', () async {
    final fake = FakeGitHub()
      ..baseEntries = makeBase()
      ..treesGetStatus = 403;
    final s = serviceFor(fake);
    expect(
      () => s.getRecursiveTree('t', 'o', 'r', 'main'),
      throwsA(isA<GitHubApiException>()),
    );
  });

  test('ref 404 -> boş ağaç; ref 403 -> hata', () async {
    final fake = FakeGitHub()..refStatus = 404;
    final empty = await serviceFor(fake).getRecursiveTree('t', 'o', 'r', 'main');
    expect(empty.entries, isEmpty);

    final fake2 = FakeGitHub()..refStatus = 403;
    expect(
      () => serviceFor(fake2).getRecursiveTree('t', 'o', 'r', 'main'),
      throwsA(isA<GitHubApiException>()),
    );
  });

  test('base tree alınamazsa push iptal edilir, ref PATCH atılmaz', () async {
    final fake = FakeGitHub()
      ..baseEntries = makeBase()
      ..commitStatus = 500;
    final s = serviceFor(fake);

    await expectLater(
      push(s, [fileItem('dir1/yeni.txt', 'x')]),
      throwsA(isA<GitHubApiException>()),
    );
    expect(fake.called('PATCH /repos/o/r/git/refs/heads/main'), isFalse);
    expect(fake.called('POST /repos/o/r/git/trees'), isFalse);
    expect(fake.called('POST /repos/o/r/git/commits'), isFalse);
  });

  test('ref sorgusu 403 ise "boş repo" sanılmaz, push iptal', () async {
    final fake = FakeGitHub()..refStatus = 403;
    await expectLater(
      push(serviceFor(fake), [fileItem('a.txt', 'x')]),
      throwsA(isA<GitHubApiException>()),
    );
    expect(fake.called('POST /repos/o/r/git/refs'), isFalse);
    expect(fake.called('POST /repos/o/r/git/blobs'), isFalse);
  });

  test('güvenlik ağı: 2 dosya, 50 dosyalı base -> yeni ağaç 52; push başarılı', () async {
    final base = makeBase();
    final fake = FakeGitHub()
      ..baseEntries = base
      ..newEntries = [
        ...base,
        blobEntry('dir1/yeni.txt', 'x'),
        blobEntry('dir2/yeni.txt', 'y'),
      ];
    final result = await push(
      serviceFor(fake),
      [fileItem('dir1/yeni.txt', 'x'), fileItem('dir2/yeni.txt', 'y')],
      name: 'Ad',
      email: 'a@b.c',
    );

    expect(result.commitSha, 'newcommit');
    expect(result.added, 2);
    expect(result.updated, 0);
    expect(fake.lastTreeBody!['base_tree'], 'basetree');
    expect(fake.lastCommitBody!['parents'], ['parent1']);
    expect(fake.lastCommitBody!['author'], {'name': 'Ad', 'email': 'a@b.c'});
    expect(fake.called('PATCH /repos/o/r/git/refs/heads/main'), isTrue);
  });

  test('güvenlik ağı: beklenmeyen dosya kaybı -> push iptal, ref\'e dokunulmaz', () async {
    final base = makeBase();
    final fake = FakeGitHub()
      ..baseEntries = base
      // yeni ağaçta 3 dosya kaybolmuş (simülasyon)
      ..newEntries = [
        ...base.where((e) => !(e['path'] as String).startsWith('dir2/f1')),
        blobEntry('dir1/yeni.txt', 'x'),
      ];

    await expectLater(
      push(serviceFor(fake), [fileItem('dir1/yeni.txt', 'x')]),
      throwsA(
        isA<GitHubApiException>().having((e) => e.kind, 'kind', GitHubApiException.kindSafetyNet),
      ),
    );
    expect(fake.called('POST /repos/o/r/git/commits'), isFalse);
    expect(fake.called('PATCH /repos/o/r/git/refs/heads/main'), isFalse);
  });

  test('onaylı silme güvenlik ağını geçer; onaysız silme yerel olarak reddedilir', () async {
    final base = makeBase();
    final fake = FakeGitHub()
      ..baseEntries = base
      ..newEntries = base.where((e) => e['path'] != 'dir1/f0.txt').toList();

    final del = GitFileItem.deletion('dir1/f0.txt');
    final result = await push(serviceFor(fake), [del], deletes: {'dir1/f0.txt'});
    expect(result.deleted, 1);
    final entries = fake.lastTreeBody!['tree'] as List;
    expect((entries.first as Map)['sha'], isNull);

    final fake2 = FakeGitHub()..baseEntries = base;
    await expectLater(
      push(serviceFor(fake2), [GitFileItem.deletion('dir1/f0.txt')]),
      throwsA(isA<GitHubApiException>()),
    );
    expect(fake2.log, isEmpty); // ağa hiç çıkılmadı
  });

  test('klasör yolunu dosyayla değiştirme girişimi push içinde engellenir', () async {
    final base = makeBase();
    final fake = FakeGitHub()..baseEntries = base;
    await expectLater(
      push(serviceFor(fake), [fileItem('dir1', 'x', name: 'x.txt')]),
      throwsA(isA<GitHubApiException>()),
    );
    expect(fake.called('POST /repos/o/r/git/trees'), isFalse);
  });

  test('değişmeyen dosyalar: commit atılmaz, noChanges döner', () async {
    final base = makeBase();
    final fake = FakeGitHub()..baseEntries = base;
    final result = await push(serviceFor(fake), [fileItem('dir1/f0.txt', 'a0')]);
    expect(result.noChanges, isTrue);
    expect(result.commitSha, isNull);
    expect(result.skipped, 1);
    expect(fake.called('POST /repos/o/r/git/blobs'), isFalse);
    expect(fake.called('POST /repos/o/r/git/commits'), isFalse);
  });

  test('mevcut çalıştırılabilir dosyanın modu korunur', () async {
    final base = [blobEntry('run.sh', 'old', mode: '100755'), blobEntry('a.txt', 'x')];
    final fake = FakeGitHub()
      ..baseEntries = base
      ..newEntries = base;
    await push(serviceFor(fake), [fileItem('run.sh', 'new'), fileItem('gradlew.bat', 'bat'), fileItem('gradlew', 'g')]);
    final entries = (fake.lastTreeBody!['tree'] as List).cast<Map>();
    final modes = {for (final e in entries) e['path']: e['mode']};
    expect(modes['run.sh'], '100755'); // korunur
    expect(modes['gradlew.bat'], '100644');
    expect(modes['gradlew'], '100755');
  });

  test('ref 404 (dal yok): ilk commit, parents boş, POST refs kullanılır', () async {
    final fake = FakeGitHub()..refStatus = 404;
    final result = await push(serviceFor(fake), [fileItem('a.txt', 'x')]);
    expect(result.commitSha, 'newcommit');
    expect(fake.lastCommitBody!['parents'], isEmpty);
    expect(fake.lastTreeBody!.containsKey('base_tree'), isFalse);
    expect(fake.called('POST /repos/o/r/git/refs'), isTrue);
    expect(fake.called('PATCH /repos/o/r/git/refs/heads/main'), isFalse);
  });

  test('PATCH 422 -> dal değişti mesajı ve POST refs denenmez', () async {
    final base = makeBase();
    final fake = FakeGitHub()
      ..baseEntries = base
      ..newEntries = [...base, blobEntry('dir1/yeni.txt', 'x')]
      ..patchStatus = 422;
    await expectLater(
      push(serviceFor(fake), [fileItem('dir1/yeni.txt', 'x')]),
      throwsA(isA<GitHubApiException>().having((e) => e.kind, 'kind', GitHubApiException.kindBranchMoved)),
    );
    expect(fake.called('POST /repos/o/r/git/refs'), isFalse);
  });

  test('workflow yetkisi yoksa açık Türkçe mesaj verilir', () async {
    final base = makeBase();
    final fake = FakeGitHub()
      ..baseEntries = base
      ..treesPostStatus = 404
      ..treesPostMessage = 'refusing to allow a Personal Access Token to create or update workflow `.github/workflows/build.yml` without `workflow` scope';
    await expectLater(
      push(serviceFor(fake), [fileItem('.github/workflows/build.yml', 'x')]),
      throwsA(isA<GitHubApiException>().having((e) => e.message, 'message', contains('workflow')).having((e) => e.message, 'message', contains('yetkisi yok'))),
    );
  });

  test('ikincil hız sınırı (403 + retry-after): bekleyip yeniden dener', () async {
    final base = makeBase();
    final fake = FakeGitHub()
      ..baseEntries = base
      ..newEntries = [...base, blobEntry('dir1/yeni.txt', 'x')]
      ..blobFailuresBeforeSuccess = 1;
    final sleeps = <Duration>[];
    final result = await push(serviceFor(fake, sleeps: sleeps), [fileItem('dir1/yeni.txt', 'x')]);
    expect(result.commitSha, 'newcommit');
    expect(sleeps, [const Duration(seconds: 1)]);
  });

  test('ağ zaman aşımı Türkçe anlamlı mesaja çevrilir', () async {
    final s = GitHubService(
      client: MockClient((req) async => throw http.ClientException('boom')),
      sleep: (d) async {},
    );
    await expectLater(
      s.verifyUser('t'),
      throwsA(isA<GitHubApiException>().having((e) => e.statusCode, 'statusCode', 0)),
    );
  });

  test('getActionRuns 403 dönerse boş liste değil hata fırlatır', () async {
    final s = GitHubService(
      client: MockClient((req) async => jsonRes({'message': 'Resource not accessible'}, 403)),
      sleep: (d) async {},
    );
    await expectLater(s.getActionRuns('t', 'o', 'r'), throwsA(isA<GitHubApiException>()));
  });

  test('deleteSingleFile yolu URL-encode eder', () async {
    late Uri seen;
    final s = GitHubService(
      client: MockClient((req) async {
        seen = req.url;
        return jsonRes({}, 200);
      }),
      sleep: (d) async {},
    );
    await s.deleteSingleFile('t', 'o', 'r', 'lib/ğ dosya#1.dart', 'main', 'sha', 'msg');
    expect(seen.toString(), contains('/contents/lib/%C4%9F%20dosya%231.dart'));
  });
}
