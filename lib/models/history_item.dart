import 'dart:convert';

class HistoryItem {
  final String id;
  final String repoFullName;
  final String branch;
  final String commitMessage;
  final String commitSha;
  final int filesCount;
  final DateTime timestamp;
  final String commitUrl;

  HistoryItem({
    required this.id,
    required this.repoFullName,
    required this.branch,
    required this.commitMessage,
    required this.commitSha,
    required this.filesCount,
    required this.timestamp,
    required this.commitUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repoFullName': repoFullName,
      'branch': branch,
      'commitMessage': commitMessage,
      'commitSha': commitSha,
      'filesCount': filesCount,
      'timestamp': timestamp.toIso8601String(),
      'commitUrl': commitUrl,
    };
  }

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'] as String,
      repoFullName: map['repoFullName'] as String,
      branch: map['branch'] as String,
      commitMessage: map['commitMessage'] as String,
      commitSha: map['commitSha'] as String,
      filesCount: map['filesCount'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
      commitUrl: map['commitUrl'] as String,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory HistoryItem.fromJson(String source) => HistoryItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
