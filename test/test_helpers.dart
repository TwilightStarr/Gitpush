import 'dart:convert';
import 'dart:typed_data';
import 'package:gitpush/models/git_file.dart';
import 'package:gitpush/services/github_service.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

/// Repo ağacı düğümü (GitHub `git/trees` biçimi).
Map<String, dynamic> blobEntry(String path, String content, {String mode = '100644'}) {
  return {
    'path': path,
    'mode': mode,
    'type': 'blob',
    'sha': GitHubService.calculateGitBlobSha(bytesOf(content)),
  };
}

Map<String, dynamic> treeEntry(String path) {
  return {'path': path, 'mode': '040000', 'type': 'tree', 'sha': 'tree-$path'};
}

GitFileItem fileItem(String repoPath, String content, {String? name}) {
  final data = bytesOf(content);
  return GitFileItem(
    localPath: name ?? repoPath.split('/').last,
    repoPath: repoPath,
    sourceName: name ?? repoPath.split('/').last,
    size: data.length,
    bytes: data,
  );
}
