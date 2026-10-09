import 'app_settings.dart';

/// Repo tarayıcıdaki tek satır: dosya, klasör veya alt modül.
class RepoEntry {
  final String name;
  final String path;
  final bool isDir;
  final bool isSubmodule;

  /// Dosyada kendi boyutu, klasörde altındaki tüm dosyaların toplamı (bayt).
  final int size;

  /// Yalnızca klasörler için: altındaki (iç içe dahil) dosya / klasör sayısı.
  final int fileCount;
  final int folderCount;

  final String? sha;
  final String? mode;

  const RepoEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.isSubmodule = false,
    this.size = 0,
    this.fileCount = 0,
    this.folderCount = 0,
    this.sha,
    this.mode,
  });

  bool get isHidden => name.startsWith('.');

  /// Küçük harfli uzantı (nokta yok). Uzantısız ve `.gitignore` gibi
  /// nokta-ile-başlayan adlar için boş döner.
  String get extension {
    if (isDir) return '';
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }
}

/// Yol çubuğundaki (breadcrumb) bir basamak.
class RepoCrumb {
  final String label;
  final String path;

  const RepoCrumb(this.label, this.path);
}

/// `lib/screens` -> [Kök, lib, lib/screens].
List<RepoCrumb> breadcrumbsFor(String dir, {String rootLabel = 'Kök'}) {
  final crumbs = <RepoCrumb>[RepoCrumb(rootLabel, '')];
  if (dir.isEmpty) return crumbs;
  var acc = '';
  for (final seg in dir.split('/')) {
    if (seg.isEmpty) continue;
    acc = acc.isEmpty ? seg : '$acc/$seg';
    crumbs.add(RepoCrumb(seg, acc));
  }
  return crumbs;
}

/// "file10" > "file2" doğru sıralansın diye sayı kısımlarını sayısal
/// karşılaştıran, harf büyüklüğünü yok sayan doğal sıralama.
int compareNatural(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    final dx = cx >= 48 && cx <= 57;
    final dy = cy >= 48 && cy <= 57;
    if (dx && dy) {
      var ei = i;
      while (ei < x.length && x.codeUnitAt(ei) >= 48 && x.codeUnitAt(ei) <= 57) {
        ei++;
      }
      var ej = j;
      while (ej < y.length && y.codeUnitAt(ej) >= 48 && y.codeUnitAt(ej) <= 57) {
        ej++;
      }
      final nx = x.substring(i, ei).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final ny = y.substring(j, ej).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (nx.length != ny.length) return nx.length.compareTo(ny.length);
      final c = nx.compareTo(ny);
      if (c != 0) return c;
      i = ei;
      j = ej;
    } else {
      if (cx != cy) return cx.compareTo(cy);
      i++;
      j++;
    }
  }
  return (x.length - i).compareTo(y.length - j);
}

class _FolderAgg {
  String? sha;
  int files = 0;
  int folders = 0;
  int size = 0;
}

int _sizeOf(Map<String, dynamic> e) {
  final s = e['size'];
  return s is num ? s.toInt() : 0;
}

String? _typeOf(Map<String, dynamic> e) => e['type'] is String ? e['type'] as String : null;

/// [dir] klasörünün DOĞRUDAN çocuklarını döndürür. Klasörler her zaman
/// dosyalardan önce gelir; her grubun içi [sort] ölçütüne göre sıralanır.
List<RepoEntry> buildDirectoryListing(
  List<Map<String, dynamic>> tree,
  String dir, {
  RepoSortMode sort = RepoSortMode.nameAsc,
  bool showHidden = true,
}) {
  final prefix = dir.isEmpty ? '' : '$dir/';
  final folders = <String, _FolderAgg>{};
  final files = <RepoEntry>[];

  for (final e in tree) {
    final path = e['path'];
    if (path is! String) continue;
    if (prefix.isNotEmpty && !path.startsWith(prefix)) continue;
    final rel = path.substring(prefix.length);
    if (rel.isEmpty) continue;
    final type = _typeOf(e);
    final slash = rel.indexOf('/');

    if (slash == -1) {
      // Doğrudan çocuk
      if (type == 'tree') {
        folders.putIfAbsent(rel, _FolderAgg.new).sha = e['sha'] as String?;
      } else {
        files.add(RepoEntry(
          name: rel,
          path: path,
          isDir: false,
          isSubmodule: type == 'commit',
          size: _sizeOf(e),
          sha: e['sha'] as String?,
          mode: e['mode'] as String?,
        ));
      }
    } else {
      // Alt klasörün torunu: üst klasörün toplamlarına ekle
      final top = rel.substring(0, slash);
      final agg = folders.putIfAbsent(top, _FolderAgg.new);
      if (type == 'tree') {
        agg.folders++;
      } else {
        agg.files++;
        agg.size += _sizeOf(e);
      }
    }
  }

  final dirs = folders.entries
      .map((f) => RepoEntry(
            name: f.key,
            path: prefix + f.key,
            isDir: true,
            size: f.value.size,
            fileCount: f.value.files,
            folderCount: f.value.folders,
            sha: f.value.sha,
          ))
      .toList();

  bool keep(RepoEntry e) => showHidden || !e.isHidden;
  final visibleDirs = dirs.where(keep).toList();
  final visibleFiles = files.where(keep).toList();

  int byName(RepoEntry a, RepoEntry b) => compareNatural(a.name, b.name);

  switch (sort) {
    case RepoSortMode.nameAsc:
      visibleDirs.sort(byName);
      visibleFiles.sort(byName);
      break;
    case RepoSortMode.nameDesc:
      visibleDirs.sort((a, b) => byName(b, a));
      visibleFiles.sort((a, b) => byName(b, a));
      break;
    case RepoSortMode.sizeDesc:
      int bySize(RepoEntry a, RepoEntry b) {
        final c = b.size.compareTo(a.size);
        return c != 0 ? c : byName(a, b);
      }
      visibleDirs.sort(bySize);
      visibleFiles.sort(bySize);
      break;
    case RepoSortMode.extension:
      visibleDirs.sort(byName);
      visibleFiles.sort((a, b) {
        final c = a.extension.compareTo(b.extension);
        return c != 0 ? c : byName(a, b);
      });
      break;
  }

  return <RepoEntry>[...visibleDirs, ...visibleFiles];
}

/// Tüm ağaçta yol araması (büyük/küçük harf duyarsız). Klasörler önce, sonra
/// ada göre başlayan eşleşmeler, sonra yola göre.
List<RepoEntry> searchRepoTree(
  List<Map<String, dynamic>> tree,
  String query, {
  bool showHidden = true,
  int limit = 300,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const <RepoEntry>[];

  final out = <RepoEntry>[];
  for (final e in tree) {
    final path = e['path'];
    if (path is! String) continue;
    if (!path.toLowerCase().contains(q)) continue;
    if (!showHidden && path.split('/').any((s) => s.startsWith('.'))) continue;
    final type = _typeOf(e);
    final name = path.substring(path.lastIndexOf('/') + 1);
    out.add(RepoEntry(
      name: name,
      path: path,
      isDir: type == 'tree',
      isSubmodule: type == 'commit',
      size: _sizeOf(e),
      sha: e['sha'] as String?,
      mode: e['mode'] as String?,
    ));
  }

  int rank(RepoEntry e) {
    final n = e.name.toLowerCase();
    if (n == q) return 0;
    if (n.startsWith(q)) return 1;
    if (n.contains(q)) return 2;
    return 3;
  }

  out.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return compareNatural(a.path, b.path);
  });
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// [dir] altındaki (iç içe) TÜM blob girdileri; klasör silme / taşıma için.
List<Map<String, dynamic>> blobsUnder(List<Map<String, dynamic>> tree, String dir) {
  final prefix = '$dir/';
  return tree
      .where((e) => e['path'] is String && (e['path'] as String).startsWith(prefix) && _typeOf(e) == 'blob')
      .toList();
}

/// Dosya adından önizleme türü.
enum PreviewKind { text, image, binary }

const Set<String> _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const Set<String> _binaryExts = {
  'zip', 'gz', 'tgz', 'rar', '7z', 'jar', 'aar', 'apk', 'aab', 'so', 'dll', 'exe', 'bin', 'class', 'dex',
  'pdf', 'mp3', 'mp4', 'mov', 'avi', 'mkv', 'wav', 'ogg', 'ttf', 'otf', 'woff', 'woff2', 'ico', 'keystore', 'jks',
  'psd', 'sketch', 'db', 'sqlite', 'o', 'a',
};

PreviewKind previewKindFor(String fileName) {
  final i = fileName.lastIndexOf('.');
  final ext = i <= 0 ? '' : fileName.substring(i + 1).toLowerCase();
  if (_imageExts.contains(ext)) return PreviewKind.image;
  if (_binaryExts.contains(ext)) return PreviewKind.binary;
  return PreviewKind.text;
}
