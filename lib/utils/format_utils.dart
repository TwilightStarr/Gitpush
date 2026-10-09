/// Godot'taki `_format_bytes()` fonksiyonunun Flutter karsiligi.
/// Bayt degerini okunabilir B / KB / MB / GB birimine cevirir.
String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Bir süreyi "1 sa 24 dk" / "42 dk" / "< 1 dk" biçimine çevirir.
/// Pil kalan-süre tahmini için kullanılır (bkz. `BatteryService`).
String formatDuration(Duration d) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes < 1) return '< 1 dk';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours <= 0) return '$minutes dk';
  if (minutes == 0) return '$hours sa';
  return '$hours sa $minutes dk';
}

/// Commit SHA'sını her ekranda aynı uzunlukta (7 karakter) gösterir.
String shortSha(String sha, {int length = 7}) {
  return sha.length <= length ? sha : sha.substring(0, length);
}
