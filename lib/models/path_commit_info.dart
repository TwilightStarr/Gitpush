/// Bir dosya/klasörü en son değiştiren commit'in özeti.
class PathCommitInfo {
  final String sha;
  final String message;
  final String? authorName;
  final DateTime? date;
  final String? htmlUrl;

  const PathCommitInfo({
    required this.sha,
    required this.message,
    this.authorName,
    this.date,
    this.htmlUrl,
  });

  /// Commit mesajının ilk satırı.
  String get title {
    final i = message.indexOf('\n');
    return (i == -1 ? message : message.substring(0, i)).trim();
  }

  factory PathCommitInfo.fromJson(Map<String, dynamic> json) {
    final commit = json['commit'] is Map ? Map<String, dynamic>.from(json['commit'] as Map) : <String, dynamic>{};
    final author = commit['author'] is Map ? Map<String, dynamic>.from(commit['author'] as Map) : <String, dynamic>{};
    final url = json['html_url'];
    return PathCommitInfo(
      sha: (json['sha'] as String?) ?? '',
      message: (commit['message'] as String?) ?? '',
      authorName: author['name'] as String?,
      date: author['date'] is String ? DateTime.tryParse(author['date'] as String) : null,
      htmlUrl: url is String ? url : null,
    );
  }
}

/// Dosya/klasör taşıma-yeniden adlandırma için tek bir blob eşlemesi.
class RepoMove {
  final String from;
  final String to;
  final String sha;
  final String mode;

  const RepoMove({required this.from, required this.to, required this.sha, this.mode = '100644'});
}

/// GitHub API (core) istek kotası.
class RateLimitInfo {
  final int limit;
  final int remaining;
  final DateTime? resetAt;

  const RateLimitInfo({required this.limit, required this.remaining, this.resetAt});

  int get used => limit - remaining;

  factory RateLimitInfo.fromJson(Map<String, dynamic> json) {
    final resources = json['resources'];
    final core = resources is Map && resources['core'] is Map
        ? Map<String, dynamic>.from(resources['core'] as Map)
        : <String, dynamic>{};
    final reset = core['reset'];
    return RateLimitInfo(
      limit: (core['limit'] as num?)?.toInt() ?? 0,
      remaining: (core['remaining'] as num?)?.toInt() ?? 0,
      resetAt: reset is num ? DateTime.fromMillisecondsSinceEpoch(reset.toInt() * 1000) : null,
    );
  }
}
