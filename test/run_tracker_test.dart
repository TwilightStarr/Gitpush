import 'package:flutter_test/flutter_test.dart';
import 'package:gitpush/models/action_run.dart';
import 'package:gitpush/services/run_tracker.dart';

ActionRun run(int id, String sha, String status, {String? conclusion}) {
  return ActionRun(
    id: id,
    name: 'Build',
    headBranch: 'main',
    headSha: sha,
    status: status,
    conclusion: conclusion,
    event: 'push',
    htmlUrl: 'https://github.com/o/r/actions/runs/$id',
    createdAt: DateTime(2026, 1, 1, 0, 0, id),
    commitMessage: 'm',
  );
}

void main() {
  test('eski completed run yeni push için yok sayılır; polling devam eder', () {
    final old = run(1, 'oldsha', 'completed', conclusion: 'success');
    final eval = evaluateRuns([old], 'newsha');
    expect(eval.found, isFalse);
    expect(eval.allCompleted, isFalse);
  });

  test('doğru head_sha eşleşince sonuç gösterilir; tamamlanınca durur', () {
    final old = run(1, 'oldsha', 'completed', conclusion: 'success');
    final running = run(2, 'newsha', 'in_progress');
    expect(evaluateRuns([running, old], 'newsha').allCompleted, isFalse);

    final done = run(2, 'newsha', 'completed', conclusion: 'failure');
    final eval = evaluateRuns([done, old], 'newsha');
    expect(eval.found, isTrue);
    expect(eval.allCompleted, isTrue);
    expect(eval.matching.first.isFailed, isTrue);
  });

  test('queued/waiting/pending sürüyor sayılır; cancelled/timed_out ayrı', () {
    expect(run(1, 's', 'queued').isRunning, isTrue);
    expect(run(1, 's', 'waiting').isRunning, isTrue);
    expect(run(1, 's', 'pending').isRunning, isTrue);
    expect(run(1, 's', 'completed', conclusion: 'cancelled').isCancelled, isTrue);
    expect(run(1, 's', 'completed', conclusion: 'timed_out').isTimedOut, isTrue);
    expect(run(1, 's', 'completed', conclusion: 'cancelled').isFailed, isFalse);
  });
}
