import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/git_file.dart';
import '../utils/path_validation.dart';

class ZipServiceException implements Exception {
  final String message;
  ZipServiceException(this.message);

  @override
  String toString() => message;
}

class ZipExtractResult {
  final List<GitFileItem> items;

  /// Güvensiz/geçersiz yol içerdiği için atlanan girdiler (örn. `../x`).
  final List<String> invalidEntries;

  const ZipExtractResult({required this.items, required this.invalidEntries});
}

class ZipService {
  // Hariç tutulacak dosya ve klasör kalıpları
  static final List<Pattern> _ignoredPatterns = [
    RegExp(r'(^|/)(__MACOSX)($|/)'),
    RegExp(r'(^|/)(\.DS_Store)$'),
    RegExp(r'(^|/)(Thumbs\.db)$'),
    RegExp(r'(^|/)(\.git)($|/)'),
  ];

  static bool shouldIgnore(String path) {
    for (final pattern in _ignoredPatterns) {
      if (pattern.allMatches(path).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  // ZIP dosyasını bellek içinde aç ve GitFileItem listesine dönüştür
  static ZipExtractResult extractZipBytes({
    required Uint8List zipBytes,
    bool stripSingleRootDir = true,
  }) {
    try {
      return _extract(zipBytes, stripSingleRootDir);
    } on ZipServiceException {
      rethrow;
    } catch (_) {
      throw ZipServiceException(
        'ZIP dosyası okunamadı. Dosya bozuk veya şifreli olabilir.',
      );
    }
  }

  static ZipExtractResult _extract(Uint8List zipBytes, bool stripSingleRootDir) {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // (normalleştirilmiş ad, dosya) çiftleri
    final names = <String>[];
    final files = <ArchiveFile>[];
    final invalid = <String>[];

    for (final file in archive) {
      if (!file.isFile) continue;

      final name = file.name.replaceAll('\\', '/');
      if (shouldIgnore(name)) continue;

      // Zip Slip benzeri girdiler: mutlak yol, `..` veya geçersiz karakter
      final validation = normalizeAndValidateGitPath(name);
      if (!validation.isValid || name.startsWith('/')) {
        invalid.add(file.name);
        continue;
      }

      names.add(validation.normalizedPath);
      files.add(file);
    }

    if (files.isEmpty) {
      return ZipExtractResult(items: const <GitFileItem>[], invalidEntries: invalid);
    }

    // Tek bir üst klasör olup olmadığını kontrol et (örn: "flutter_app-master/...")
    String? commonRoot;
    if (stripSingleRootDir) {
      final firstSlash = names.first.indexOf('/');
      if (firstSlash != -1) {
        final possibleRoot = names.first.substring(0, firstSlash + 1);
        final allHaveRoot = names.every((n) => n.startsWith(possibleRoot));
        if (allHaveRoot) {
          commonRoot = possibleRoot;
        }
      }
    }

    final items = <GitFileItem>[];
    for (var i = 0; i < files.length; i++) {
      var cleanPath = names[i];
      if (commonRoot != null && cleanPath.startsWith(commonRoot)) {
        cleanPath = cleanPath.substring(commonRoot.length);
      }

      final content = files[i].content as List<int>;
      final bytes = Uint8List.fromList(content);

      items.add(GitFileItem(
        localPath: files[i].name,
        repoPath: cleanPath,
        size: bytes.length,
        bytes: bytes,
        isSelected: true,
        status: GitFileStatus.isNew,
      ));
    }

    return ZipExtractResult(items: items, invalidEntries: invalid);
  }
}
