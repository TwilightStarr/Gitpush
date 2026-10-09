import '../models/action_run.dart';

class RunEvaluation {
  /// Push'un ürettiği commit'e (head_sha) ait çalışmalar.
  final List<ActionRun> matching;

  /// Eşleşen çalışma var ve hepsi tamamlandı.
  final bool allCompleted;

  const RunEvaluation({required this.matching, required this.allCompleted});

  bool get found => matching.isNotEmpty;
}

/// Eski (başka commit'e ait) çalışmaları yok sayar; yalnızca [commitSha] ile
/// eşleşenleri döndürür. Eşleşme yoksa polling devam etmelidir.
RunEvaluation evaluateRuns(List<ActionRun> runs, String commitSha) {
  final matching = runs.where((r) => r.headSha == commitSha).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final done = matching.isNotEmpty && matching.every((r) => r.isCompleted);
  return RunEvaluation(matching: matching, allCompleted: done);
}
