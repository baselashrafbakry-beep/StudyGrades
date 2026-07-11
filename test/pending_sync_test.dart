import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/pending_sync.dart';

void main() {
  PendingSync syncFor(String owner) {
    return PendingSync(
      termId: 1,
      weekNumber: 2,
      studentId: 3,
      studentName: 'Student',
      grades: const {'oral': 10},
      timestamp: '2026-06-26T00:00:00.000Z',
      classId: 4,
      subject: 'Arabic',
      ownerKey: owner,
    );
  }

  test('same grade target is scoped by owner key', () {
    expect(syncFor('user:a').hasSameTarget(syncFor('user:a')), true);
    expect(syncFor('user:a').hasSameTarget(syncFor('user:b')), false);
  });

  test('owner key survives json round trip', () {
    final sync = syncFor('user:teacher');
    final decoded = PendingSync.fromJson(sync.toJson());
    expect(decoded.ownerKey, 'user:teacher');
    expect(decoded.hasSameTarget(sync), true);
  });
}
