class GitHubRepo {
  final int id;
  final String name;
  final String fullName;
  final String owner;
  final bool isPrivate;
  final String defaultBranch;
  final String? description;
  final DateTime? updatedAt;
  final bool isEmpty;

  GitHubRepo({
    required this.id,
    required this.name,
    required this.fullName,
    required this.owner,
    required this.isPrivate,
    required this.defaultBranch,
    this.description,
    this.updatedAt,
    this.isEmpty = false,
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      id: json['id'] as int,
      name: json['name'] as String,
      fullName: json['full_name'] as String,
      owner: (json['owner'] as Map<String, dynamic>)['login'] as String,
      isPrivate: json['private'] as bool? ?? false,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      description: json['description'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      isEmpty: json['size'] == 0,
    );
  }
}

class GitHubBranch {
  final String name;
  final String commitSha;

  GitHubBranch({
    required this.name,
    required this.commitSha,
  });

  factory GitHubBranch.fromJson(Map<String, dynamic> json) {
    final commit = json['commit'] as Map<String, dynamic>;
    return GitHubBranch(
      name: json['name'] as String,
      commitSha: commit['sha'] as String,
    );
  }
}
