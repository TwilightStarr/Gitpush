import 'package:flutter/material.dart';

/// Bir dosya uzantısı için simge + vurgu rengi.
class FileVisual {
  final IconData icon;
  final Color color;

  const FileVisual(this.icon, this.color);
}

const FileVisual _defaultFile = FileVisual(Icons.insert_drive_file_outlined, Color(0xFF8B93A7));

const Map<String, FileVisual> _byExt = {
  'dart': FileVisual(Icons.flutter_dash, Color(0xFF29B6F6)),
  'kt': FileVisual(Icons.code, Color(0xFFB455F0)),
  'java': FileVisual(Icons.code, Color(0xFFE8A200)),
  'swift': FileVisual(Icons.code, Color(0xFFFF7043)),
  'js': FileVisual(Icons.javascript, Color(0xFFE8C200)),
  'jsx': FileVisual(Icons.javascript, Color(0xFF29B6F6)),
  'ts': FileVisual(Icons.javascript, Color(0xFF3B82F6)),
  'tsx': FileVisual(Icons.javascript, Color(0xFF3B82F6)),
  'py': FileVisual(Icons.code, Color(0xFF3B82F6)),
  'rb': FileVisual(Icons.code, Color(0xFFE5484D)),
  'go': FileVisual(Icons.code, Color(0xFF00B8A9)),
  'rs': FileVisual(Icons.code, Color(0xFFFF7043)),
  'c': FileVisual(Icons.code, Color(0xFF8B93A7)),
  'cpp': FileVisual(Icons.code, Color(0xFF3B82F6)),
  'h': FileVisual(Icons.code, Color(0xFF8B93A7)),
  'json': FileVisual(Icons.data_object, Color(0xFFE8A200)),
  'yaml': FileVisual(Icons.data_object, Color(0xFFE5484D)),
  'yml': FileVisual(Icons.data_object, Color(0xFFE5484D)),
  'toml': FileVisual(Icons.data_object, Color(0xFF8B93A7)),
  'xml': FileVisual(Icons.data_object, Color(0xFFFF7043)),
  'md': FileVisual(Icons.description_outlined, Color(0xFF5B6CFF)),
  'txt': FileVisual(Icons.description_outlined, Color(0xFF8B93A7)),
  'html': FileVisual(Icons.html, Color(0xFFFF7043)),
  'css': FileVisual(Icons.css, Color(0xFF3B82F6)),
  'sh': FileVisual(Icons.terminal, Color(0xFF2EA043)),
  'bat': FileVisual(Icons.terminal, Color(0xFF2EA043)),
  'gradle': FileVisual(Icons.build_outlined, Color(0xFF00B8A9)),
  'kts': FileVisual(Icons.build_outlined, Color(0xFF00B8A9)),
  'png': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'jpg': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'jpeg': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'gif': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'webp': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'svg': FileVisual(Icons.image_outlined, Color(0xFFFF7043)),
  'zip': FileVisual(Icons.inventory_2_outlined, Color(0xFFE8A200)),
  'apk': FileVisual(Icons.android, Color(0xFF2EA043)),
  'pdf': FileVisual(Icons.picture_as_pdf_outlined, Color(0xFFE5484D)),
  'pem': FileVisual(Icons.vpn_key_outlined, Color(0xFFE5484D)),
  'jks': FileVisual(Icons.vpn_key_outlined, Color(0xFFE5484D)),
  'lock': FileVisual(Icons.lock_outline, Color(0xFF8B93A7)),
};

FileVisual fileVisualFor(String extension) => _byExt[extension.toLowerCase()] ?? _defaultFile;
