/// Git yolu doğrulama ve normalleştirme yardımcıları.
///
/// `src/utils/pathValidation.ts` mantığının Dart karşılığıdır.
class PathValidationResult {
  final bool isValid;
  final String? error;
  final String normalizedPath;

  const PathValidationResult({
    required this.isValid,
    this.error,
    required this.normalizedPath,
  });
}

final RegExp _invalidSegmentChars = RegExp(r'[<>:"|?*\x00-\x1F]');
final RegExp _multiSlash = RegExp(r'/+');

/// Yol `/` veya `\` ile bitiyorsa (yani kullanıcı bir klasör yazdıysa) true.
bool endsWithPathSeparator(String raw) {
  final t = raw.trim();
  return t.endsWith('/') || t.endsWith('\\');
}

/// Hedef yol bir klasör gibi bitiyorsa (`lib/`, `/`) dosya adını sonuna ekler.
/// Boş yol olduğu gibi döner (doğrulamada hata olarak yakalanır).
String appendFileNameIfFolder(String raw, String fileName) {
  if (fileName.isEmpty) return raw;
  final t = raw.trim();
  if (t.isEmpty) return raw;
  if (t.endsWith('/') || t.endsWith('\\')) return '$t$fileName';
  return raw;
}

PathValidationResult _invalid(String error, String normalized) {
  return PathValidationResult(
    isValid: false,
    error: error,
    normalizedPath: normalized,
  );
}

/// Yolu normalleştirir (`\` -> `/`, baştaki/sondaki/tekrarlı `/` temizlenir)
/// ve Git için güvenli olup olmadığını denetler.
PathValidationResult normalizeAndValidateGitPath(String rawPath) {
  if (rawPath.trim().isEmpty) {
    return _invalid('Dosya yolu boş olamaz.', '');
  }

  var p = rawPath.trim().replaceAll('\\', '/');
  p = p.replaceAll(_multiSlash, '/');
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }

  if (p.isEmpty) {
    return _invalid('Dosya yolu yalnızca eğik çizgilerden oluşamaz.', '');
  }

  for (final seg in p.split('/')) {
    if (seg == '..') {
      return _invalid('Dosya yolunda ".." (üst dizin yönlendirmesi) kullanılamaz.', p);
    }
    if (seg == '.') {
      return _invalid('Dosya yolunda geçersiz "." segmenti var.', p);
    }
    if (seg.toLowerCase() == '.git') {
      return _invalid('Dosya yolunda ".git" klasörü kullanılamaz.', p);
    }
    if (_invalidSegmentChars.hasMatch(seg)) {
      return _invalid('Dosya adı geçersiz karakterler içeriyor ($seg).', p);
    }
  }

  if (p.length > 400) {
    return _invalid('Dosya yolu 400 karakter sınırını aşıyor.', p);
  }

  return PathValidationResult(isValid: true, normalizedPath: p);
}

/// Büyük/küçük harf duyarsız şekilde mükerrer olan (normalleştirilmiş, küçük
/// harfli) yolları döndürür.
List<String> findDuplicatePaths(List<String> paths) {
  final seen = <String>{};
  final duplicates = <String>{};

  for (final raw in paths) {
    final norm = normalizeAndValidateGitPath(raw).normalizedPath.toLowerCase();
    if (!seen.add(norm)) {
      duplicates.add(norm);
    }
  }
  return duplicates.toList();
}

/// Hedef klasör önekini normalleştirir: boşsa '', değilse `a/b/` biçimi.
/// (Geçerlilik denetimi, öneklenmiş tam yol üzerinde yapılır.)
String normalizeFolderPrefix(String raw) {
  var p = raw.trim().replaceAll('\\', '/');
  p = p.replaceAll(_multiSlash, '/');
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p.isEmpty ? '' : '$p/';
}
