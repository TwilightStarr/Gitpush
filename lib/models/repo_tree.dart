/// Repo ağacındaki tek bir düğüm (dosya veya klasör).
class RepoNode {
  final String path;
  final String type; // blob | tree | commit
  final String? sha;
  final String? mode;

  const RepoNode({
    required this.path,
    required this.type,
    this.sha,
    this.mode,
  });

  bool get isTree => type == 'tree';
  bool get isBlob => type == 'blob';
}

/// `getRecursiveTree` sonucu: düğümler + ağacın GitHub tarafından kesilip
/// kesilmediği.
class RepoTreeResult {
  final List<Map<String, dynamic>> entries;
  final bool truncated;

  const RepoTreeResult({required this.entries, this.truncated = false});

  const RepoTreeResult.empty()
      : entries = const <Map<String, dynamic>>[],
        truncated = false;
}

/// `path -> düğüm` haritası. Sınıflandırma ve çakışma denetimleri bunu kullanır.
class RepoTreeIndex {
  final Map<String, RepoNode> nodes;

  const RepoTreeIndex(this.nodes);

  factory RepoTreeIndex.fromEntries(List<Map<String, dynamic>> entries) {
    final map = <String, RepoNode>{};
    for (final e in entries) {
      final path = e['path'];
      if (path is! String) continue;
      map[path] = RepoNode(
        path: path,
        type: (e['type'] as String?) ?? 'blob',
        sha: e['sha'] as String?,
        mode: e['mode'] as String?,
      );
    }
    return RepoTreeIndex(map);
  }

  /// Klasör olmayan (blob / alt modül) tüm yollar.
  Iterable<String> get nonTreePaths =>
      nodes.values.where((n) => !n.isTree).map((n) => n.path);

  /// Verilen dosya adıyla eşleşen blob yolları.
  ///
  /// Önce TAM ad eşleşmesi aranır. Bulunamazsa büyük/küçük harf farkı ve
  /// tarayıcı/telefonun eklediği kopya son eki (`main (1).dart`) yok sayılarak
  /// aranır.
  List<String> findBlobsByName(String name) {
    final exact = nodes.values
        .where((n) => n.isBlob && (n.path == name || n.path.endsWith('/$name')))
        .map((n) => n.path)
        .toList();
    if (exact.isNotEmpty) {
      exact.sort();
      return exact;
    }

    final key = _nameKey(name);
    final loose = nodes.values
        .where((n) => n.isBlob && _nameKey(_lastSegment(n.path)) == key)
        .map((n) => n.path)
        .toList();
    loose.sort();
    return loose;
  }

  static final RegExp _dupSuffix = RegExp(r'\s*\(\d+\)(?=(\.[^./]+)?$)');

  static String _lastSegment(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? path : path.substring(i + 1);
  }

  static String _nameKey(String name) =>
      name.toLowerCase().replaceAll(_dupSuffix, '');

  static final Expando<Map<String, List<String>>> _lowerCache =
      Expando<Map<String, List<String>>>();

  /// küçük harfli yol -> gerçek blob yolları (büyük/küçük harf duyarsız arama).
  Map<String, List<String>> get _lowerBlobs {
    final cached = _lowerCache[this];
    if (cached != null) return cached;
    final map = <String, List<String>>{};
    for (final n in nodes.values) {
      if (n.isBlob) {
        map.putIfAbsent(n.path.toLowerCase(), () => <String>[]).add(n.path);
      }
    }
    _lowerCache[this] = map;
    return map;
  }

  /// Yol repoda blob olarak varsa (birebir ya da yalnızca harf büyüklüğü
  /// farkıyla TEK eşleşme) gerçek repo yolunu döndürür; yoksa null.
  String? uniqueBlobIgnoreCase(String path) {
    final exact = nodes[path];
    if (exact != null && exact.isBlob) return path;
    final list = _lowerBlobs[path.toLowerCase()];
    if (list != null && list.length == 1) return list.first;
    return null;
  }

  /// Yolun herhangi bir üst segmenti repoda klasör DEĞİLSE (dosya/alt modül)
  /// o üst yolu döndürür; yoksa null.
  String? findFileAncestor(String path) {
    var idx = path.lastIndexOf('/');
    while (idx > 0) {
      final parent = path.substring(0, idx);
      final node = nodes[parent];
      if (node != null && !node.isTree) return parent;
      idx = parent.lastIndexOf('/');
    }
    return null;
  }

  /// Dosyanın hemen üst klasörü repoda var mı? (Kök her zaman vardır.)
  bool hasParentFolder(String path) {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return true;
    final node = nodes[path.substring(0, idx)];
    return node != null && node.isTree;
  }
}
