import 'dart:typed_data';
import '../utils/path_validation.dart';

enum GitFileStatus {
  isNew,       // Repoda yok (Yeni)
  update,      // Repoda var, içerik farklı (Güncelleme)
  delete,      // Silinecek (yalnızca açıkça onaylanırsa)
  newFolder,   // Yeni klasör oluşturulacak
  unchanged,   // Değişmedi (yerel sha == uzak sha)
  conflict,    // Çakışma / geçersiz yol: push engellenir
}

class GitFileItem {
  static int _nextId = 1;

  /// Kart/anahtar kimliği; kopyalarda aynı kalır.
  final int id;
  final String localPath;

  /// Seçilen dosyanın özgün adı (hedef yol değişse de sabit).
  final String sourceName;

  /// Kullanıcının yazdığı / atanan hedef yol (ham; normalleştirme ayrıdır).
  String repoPath;
  final int size;
  final Uint8List? bytes;
  bool isSelected;
  GitFileStatus status;

  /// Durum, repo ağacıyla karşılaştırılarak hesaplandı mı?
  bool statusKnown;
  String? computedSha;
  String? remoteSha;
  String? remoteMode;
  String? conflictMessage;

  /// Repoda birden fazla eşleşme var; kullanıcı seçim yapmalı.
  bool needsChoice;

  /// Yol kullanıcı tarafından elle belirlendi (yazma, klasör seçici, kısayol,
  /// komut). true ise otomatik eşleştirme yolu değiştirmez.
  bool pathManual;
  List<String> suggestions;

  GitFileItem({
    int? id,
    required this.localPath,
    required this.repoPath,
    required this.size,
    this.bytes,
    String? sourceName,
    this.isSelected = true,
    this.status = GitFileStatus.isNew,
    this.statusKnown = false,
    this.computedSha,
    this.remoteSha,
    this.remoteMode,
    this.conflictMessage,
    this.needsChoice = false,
    this.pathManual = false,
    List<String>? suggestions,
  })  : id = id ?? _nextId++,
        sourceName = sourceName ?? _lastSegment(localPath),
        suggestions = suggestions ?? [];

  /// Silinecek bir repo dosyası (yalnızca açık onayla push edilir).
  factory GitFileItem.deletion(String path) {
    return GitFileItem(
      localPath: path,
      repoPath: path,
      size: 0,
      status: GitFileStatus.delete,
      statusKnown: true,
    );
  }

  static String _lastSegment(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }

  GitFileItem copyWith({
    String? repoPath,
    bool? isSelected,
    GitFileStatus? status,
  }) {
    return GitFileItem(
      id: id,
      localPath: localPath,
      repoPath: repoPath ?? this.repoPath,
      size: size,
      bytes: bytes,
      sourceName: sourceName,
      isSelected: isSelected ?? this.isSelected,
      status: status ?? this.status,
      statusKnown: statusKnown,
      computedSha: computedSha,
      remoteSha: remoteSha,
      remoteMode: remoteMode,
      conflictMessage: conflictMessage,
      needsChoice: needsChoice,
      pathManual: pathManual,
      suggestions: List<String>.from(suggestions),
    );
  }

  /// Dosyanın özgün adı.
  String get fileName => sourceName;

  /// Push'ta kullanılacak hedef yol (ham). Yol `/` ile bitiyorsa dosya adı
  /// otomatik eklenir.
  String get targetPath => appendFileNameIfFolder(repoPath, sourceName);

  String get directoryPath {
    final idx = repoPath.lastIndexOf('/');
    if (idx == -1) return '';
    return repoPath.substring(0, idx + 1);
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
