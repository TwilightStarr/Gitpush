/// `executeAtomicPush` sonucu. Sayaçlar dosya durumundan değil, gerçekten
/// push edilenlerden hesaplanır.
class PushResult {
  final String? commitSha;
  final int added;
  final int updated;
  final int deleted;
  final int skipped;
  final bool noChanges;
  final List<String> warnings;

  const PushResult({
    this.commitSha,
    this.added = 0,
    this.updated = 0,
    this.deleted = 0,
    this.skipped = 0,
    this.noChanges = false,
    this.warnings = const <String>[],
  });

  int get changedCount => added + updated + deleted;
}
