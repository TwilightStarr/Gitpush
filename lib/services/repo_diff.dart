import '../models/git_file.dart';
import '../models/repo_tree.dart';
import '../utils/path_validation.dart';
import 'github_service.dart';

/// Gönderilecek dosyaların gruplanmış planı (önizleme + push girdisi).
class PushPlan {
  final List<GitFileItem> adds;
  final List<GitFileItem> updates;
  final List<GitFileItem> deletes;
  final List<GitFileItem> unchanged;
  final List<GitFileItem> conflicts;

  /// "Mevcut dosyaların üzerine yazma" kapalıyken atlanan güncellemeler.
  final List<GitFileItem> skipped;

  /// Repo ağacı bilinmiyorsa (alınamadıysa) push engellenir.
  final bool treeUnknown;

  const PushPlan({
    this.adds = const <GitFileItem>[],
    this.updates = const <GitFileItem>[],
    this.deletes = const <GitFileItem>[],
    this.unchanged = const <GitFileItem>[],
    this.conflicts = const <GitFileItem>[],
    this.skipped = const <GitFileItem>[],
    this.treeUnknown = false,
  });

  bool get hasBlockers => conflicts.isNotEmpty || treeUnknown;
  bool get hasChanges =>
      adds.isNotEmpty || updates.isNotEmpty || deletes.isNotEmpty;

  /// Gerçekten push edilecek öğeler (değişmeyenler ve atlananlar hariç).
  List<GitFileItem> get pushItems => [...adds, ...updates, ...deletes];

  /// Açıkça onaylanmış silme yolları (normalleştirilmiş).
  Set<String> get approvedDeletePaths => deletes
      .map((f) => normalizeAndValidateGitPath(f.repoPath).normalizedPath)
      .toSet();

  static PushPlan build(
    List<GitFileItem> selected, {
    List<GitFileItem> deletes = const <GitFileItem>[],
    bool skipExisting = false,
  }) {
    final adds = <GitFileItem>[];
    final updates = <GitFileItem>[];
    final unchanged = <GitFileItem>[];
    final conflicts = <GitFileItem>[];
    final skipped = <GitFileItem>[];
    var unknown = false;

    for (final f in selected) {
      if (!f.statusKnown) unknown = true;
      switch (f.status) {
        case GitFileStatus.isNew:
        case GitFileStatus.newFolder:
          adds.add(f);
          break;
        case GitFileStatus.update:
          if (skipExisting) {
            skipped.add(f);
          } else {
            updates.add(f);
          }
          break;
        case GitFileStatus.unchanged:
          unchanged.add(f);
          break;
        case GitFileStatus.conflict:
          conflicts.add(f);
          break;
        case GitFileStatus.delete:
          // Seçili listede silme yok; yalnızca `deletes` parametresi kullanılır.
          break;
      }
    }

    return PushPlan(
      adds: adds,
      updates: updates,
      deletes: deletes,
      unchanged: unchanged,
      conflicts: conflicts,
      skipped: skipped,
      treeUnknown: unknown,
    );
  }
}

/// ZIP yollarının repo yapısına otomatik hizalanma sonucu.
///
/// ZIP yolu, baştan [stripSegments] klasör kaldırılıp başına [addPrefix]
/// eklenerek repo yoluna çevrilir.
class ZipAlignment {
  final int stripSegments;

  /// Boş ya da `a/b/` biçiminde.
  final String addPrefix;

  /// Bu hizalamayla repoda bulunan dosya sayısı.
  final int matches;

  /// Hizalama uygulanmadan repoda bulunan dosya sayısı.
  final int baselineMatches;
  final int total;

  const ZipAlignment({
    required this.stripSegments,
    required this.addPrefix,
    required this.matches,
    required this.baselineMatches,
    required this.total,
  });

  /// Özgün (ZIP içindeki, normalleştirilmiş) yolu repo yoluna çevirir.
  String apply(String originalPath) {
    final segs = originalPath.split('/');
    final k = stripSegments < segs.length ? stripSegments : segs.length - 1;
    return '$addPrefix${segs.sublist(k).join('/')}';
  }

  String describe() {
    final parts = <String>[];
    if (stripSegments > 0) {
      parts.add('ZIP yollarından $stripSegments üst klasör kaldırıldı');
    }
    if (addPrefix.isNotEmpty) {
      parts.add('"$addPrefix" öneki eklendi');
    }
    return 'Otomatik eşleştirme: ${parts.join(', ')} '
        '($matches/$total dosya repoda bulundu).';
  }
}

class _AlignCandidate {
  final int k;
  final String prefix;
  final int votes;
  const _AlignCandidate(this.k, this.prefix, this.votes);
}

/// ZIP (Mod A) ve çoklu dosya (Mod B) için TEK sınıflandırma noktası.
class RepoDiff {
  static const int maxBlobBytes = 50 * 1024 * 1024;

  /// Her dosyanın durumunu repo ağacına göre yeniden hesaplar.
  /// [index] null ise durum bilinmiyor demektir (`statusKnown = false`).
  static void classify(List<GitFileItem> files, RepoTreeIndex? index) {
    for (final f in files) {
      if (f.status == GitFileStatus.delete) continue;
      _classifyOne(f, index);
    }
    _markBatchConflicts(files);
  }

  static void _setConflict(GitFileItem f, String message) {
    f.status = GitFileStatus.conflict;
    f.conflictMessage = message;
    f.statusKnown = true;
    f.remoteSha = null;
    f.remoteMode = null;
  }

  static void _classifyOne(GitFileItem f, RepoTreeIndex? index) {
    f.conflictMessage = null;

    if (f.needsChoice) {
      _setConflict(f, 'Birden fazla eşleşme var, seçin.');
      return;
    }

    final validation = normalizeAndValidateGitPath(f.targetPath);
    if (!validation.isValid) {
      _setConflict(f, validation.error ?? 'Geçersiz dosya yolu.');
      return;
    }

    final bytes = f.bytes;
    if (bytes == null) {
      _setConflict(f, 'Dosya içeriği okunamadı.');
      return;
    }
    if (f.size > maxBlobBytes || bytes.length > maxBlobBytes) {
      _setConflict(f, 'Dosya 50 MB sınırını aşıyor; gönderilemez.');
      return;
    }

    if (index == null) {
      f.statusKnown = false;
      f.remoteSha = null;
      f.remoteMode = null;
      return;
    }

    final path = validation.normalizedPath;
    final node = index.nodes[path];

    if (node != null) {
      if (node.isTree) {
        _setConflict(
          f,
          'Bu yol bir klasör; dosya adı ekleyin (örn. $path/${f.sourceName}).',
        );
        return;
      }
      if (!node.isBlob) {
        _setConflict(f, 'Bu yol bir alt modül (submodule); üzerine yazılamaz.');
        return;
      }

      f.computedSha ??= GitHubService.calculateGitBlobSha(bytes);
      f.remoteSha = node.sha;
      f.remoteMode = node.mode;
      f.statusKnown = true;
      f.status = f.computedSha == node.sha
          ? GitFileStatus.unchanged
          : GitFileStatus.update;
      return;
    }

    final fileAncestor = index.findFileAncestor(path);
    if (fileAncestor != null) {
      _setConflict(
        f,
        'Üst yol "$fileAncestor" repoda bir dosya; klasör olarak kullanılamaz.',
      );
      return;
    }

    f.remoteSha = null;
    f.remoteMode = null;
    f.statusKnown = true;
    f.status =
        index.hasParentFolder(path) ? GitFileStatus.isNew : GitFileStatus.newFolder;
  }

  /// Aynı yola giden dosyalar (büyük/küçük harf duyarsız) ve dosya/klasör
  /// çakışmaları (aynı pakette `a` dosyası ile `a/b` dosyası).
  static void _markBatchConflicts(List<GitFileItem> files) {
    final groups = <String, List<GitFileItem>>{};
    for (final f in files) {
      if (!f.isSelected || f.status == GitFileStatus.delete) continue;
      final v = normalizeAndValidateGitPath(f.targetPath);
      if (!v.isValid) continue;
      groups.putIfAbsent(v.normalizedPath.toLowerCase(), () => <GitFileItem>[]).add(f);
    }

    for (final group in groups.values) {
      if (group.length > 1) {
        for (final f in group) {
          _setConflict(f, 'Aynı yola giden birden fazla dosya var.');
        }
      }
    }

    for (final entry in groups.entries) {
      var idx = entry.key.lastIndexOf('/');
      while (idx > 0) {
        final parent = entry.key.substring(0, idx);
        final parentGroup = groups[parent];
        if (parentGroup != null) {
          for (final f in entry.value) {
            _setConflict(f, 'Bu yolun üst yolu ("$parent") aynı gönderimde dosya olarak var.');
          }
          for (final f in parentGroup) {
            _setConflict(f, 'Bu yol, aynı gönderimde klasör olarak da kullanılıyor.');
          }
        }
        idx = parent.lastIndexOf('/');
      }
    }
  }

  /// ZIP yollarını repodaki gerçek konuma hizalamayı dener.
  ///
  /// [originalPaths]: ZIP içindeki (normalleştirilmiş) tam yollar.
  /// [currentPaths]: şu anki ayarlarla (tek kök klasör kaldırma vb.) oluşan
  /// yollar. Yalnızca hizalama, mevcut ayara göre repoda BULUNAN dosya sayısını
  /// anlamlı biçimde artırıyorsa sonuç döner; belirsizse null (dokunulmaz).
  static ZipAlignment? detectAlignment({
    required List<String> originalPaths,
    required List<String> currentPaths,
    required RepoTreeIndex index,
    int maxStrip = 6,
  }) {
    final total = originalPaths.length;
    if (total == 0 || index.nodes.isEmpty) return null;

    // Repodaki her blob için tüm yol sonekleri -> o sonekten önceki önek
    final lowerBlobs = <String>{};
    final suffixPrefixes = <String, Set<String>>{};
    var budget = 300000;
    for (final node in index.nodes.values) {
      if (!node.isBlob) continue;
      final path = node.path;
      lowerBlobs.add(path.toLowerCase());
      var start = 0;
      while (true) {
        final suffix = path.substring(start).toLowerCase();
        suffixPrefixes
            .putIfAbsent(suffix, () => <String>{})
            .add(path.substring(0, start));
        budget--;
        final next = path.indexOf('/', start);
        if (next == -1) break;
        start = next + 1;
      }
      if (budget <= 0) break;
    }

    var baseline = 0;
    for (final p in currentPaths) {
      if (lowerBlobs.contains(p.toLowerCase())) baseline++;
    }
    if (baseline >= total) return null;

    // (kaldırılan segment sayısı, eklenecek önek) -> eşleşen dosya sayısı
    final votes = <String, int>{};
    for (final orig in originalPaths) {
      final segs = orig.split('/');
      final maxK = segs.length - 1 < maxStrip ? segs.length - 1 : maxStrip;
      for (var k = 0; k <= maxK; k++) {
        final stripped = segs.sublist(k).join('/').toLowerCase();
        final prefixes = suffixPrefixes[stripped];
        if (prefixes == null || prefixes.length > 20) continue;
        for (final pre in prefixes) {
          final key = '$k|$pre';
          votes[key] = (votes[key] ?? 0) + 1;
        }
      }
    }
    if (votes.isEmpty) return null;

    final candidates = <_AlignCandidate>[];
    votes.forEach((key, v) {
      final sep = key.indexOf('|');
      candidates.add(_AlignCandidate(
        int.parse(key.substring(0, sep)),
        key.substring(sep + 1),
        v,
      ));
    });
    candidates.sort((a, b) {
      if (a.votes != b.votes) return b.votes.compareTo(a.votes);
      if (a.k != b.k) return a.k.compareTo(b.k);
      return a.prefix.length.compareTo(b.prefix.length);
    });

    final top = candidates.first;
    if (candidates.length > 1) {
      final second = candidates[1];
      // Aynı kaldırma sayısında farklı öneklerle eşit oy: belirsiz.
      if (second.votes == top.votes && second.k == top.k) return null;
    }

    final minVotes = total == 1 ? 1 : 2;
    if (top.votes < minVotes) return null;
    if (top.votes * 100 < total * 40) return null; // en az %40 eşleşme
    if (top.votes <= baseline) return null;

    return ZipAlignment(
      stripSegments: top.k,
      addPrefix: top.prefix,
      matches: top.votes,
      baselineMatches: baseline,
      total: total,
    );
  }

  /// ZIP için "Repoda olup ZIP'te olmayanları sil" adaylarını hesaplar.
  ///
  /// Kapsam (en güvenli seçenek): hedef klasör öneki varsa yalnızca o önekin
  /// altı; yoksa yalnızca ZIP'in dokunduğu üst düzey klasörlerin altı. Kökteki
  /// gevşek dosyalar ASLA silinmez.
  static List<GitFileItem> computeUnlistedDeletes({
    required RepoTreeIndex index,
    required Iterable<String> zipEffectivePaths,
    required String normalizedPrefix,
  }) {
    final zipPaths = <String>{};
    for (final raw in zipEffectivePaths) {
      final v = normalizeAndValidateGitPath(raw);
      if (v.isValid) zipPaths.add(v.normalizedPath);
    }

    final scopes = <String>{};
    if (normalizedPrefix.isNotEmpty) {
      scopes.add(normalizedPrefix); // "a/b/" biçiminde
    } else {
      for (final p in zipPaths) {
        final slash = p.indexOf('/');
        if (slash > 0) scopes.add('${p.substring(0, slash)}/');
      }
    }
    if (scopes.isEmpty) return <GitFileItem>[];

    final result = <GitFileItem>[];
    final candidates = index.nodes.values.where((n) => n.isBlob).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final node in candidates) {
      if (zipPaths.contains(node.path)) continue;
      final inScope = scopes.any((s) => node.path.startsWith(s));
      if (inScope) result.add(GitFileItem.deletion(node.path));
    }
    return result;
  }
}
