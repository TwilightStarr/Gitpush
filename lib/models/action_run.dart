class ActionRun {
  final int id;
  final String name;
  final String headBranch;
  final String headSha;
  final String status;      // queued, in_progress, waiting, pending, completed
  final String? conclusion; // success, failure, cancelled, timed_out, startup_failure
  final String event;
  final String htmlUrl;
  final DateTime createdAt;
  final String commitMessage;

  ActionRun({
    required this.id,
    required this.name,
    required this.headBranch,
    required this.headSha,
    required this.status,
    this.conclusion,
    required this.event,
    required this.htmlUrl,
    required this.createdAt,
    required this.commitMessage,
  });

  factory ActionRun.fromJson(Map<String, dynamic> json) {
    final commit = json['head_commit'] as Map<String, dynamic>?;
    return ActionRun(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Workflow',
      headBranch: json['head_branch'] as String? ?? 'main',
      headSha: json['head_sha'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      conclusion: json['conclusion'] as String?,
      event: json['event'] as String? ?? 'push',
      htmlUrl: json['html_url'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      commitMessage: commit?['message'] as String? ?? 'No commit message',
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isSuccess => conclusion == 'success';
  bool get isFailed => conclusion == 'failure';
  bool get isCancelled => conclusion == 'cancelled';
  bool get isTimedOut => conclusion == 'timed_out';
  bool get isStartupFailure => conclusion == 'startup_failure';

  /// Tamamlanmamış her durum (in_progress, queued, waiting, pending...) "sürüyor".
  bool get isRunning => !isCompleted;
  bool get isQueued =>
      status == 'queued' || status == 'waiting' || status == 'pending' || status == 'requested';

  /// Türkçe durum etiketi.
  String get statusLabel {
    if (!isCompleted) return isQueued ? 'Sırada' : 'Çalışıyor';
    if (isSuccess) return 'Başarılı';
    if (isFailed) return 'Başarısız';
    if (isCancelled) return 'İptal edildi';
    if (isTimedOut) return 'Zaman aşımı';
    if (isStartupFailure) return 'Başlatılamadı';
    if (conclusion == 'skipped') return 'Atlandı';
    return conclusion ?? 'Tamamlandı';
  }
}
