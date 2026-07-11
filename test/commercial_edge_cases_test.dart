import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/pending_sync.dart';
import 'package:study_grades_voice/models/student_model.dart';
import 'package:study_grades_voice/models/subscription_model.dart';
import 'package:study_grades_voice/models/user_model.dart';
import 'package:study_grades_voice/services/analytics_service.dart';
import 'package:study_grades_voice/services/auth_session_epoch.dart';
import 'package:study_grades_voice/services/nlp_parser.dart';
import 'package:study_grades_voice/services/sync_request_identity.dart';

PendingSync _pending({required String timestamp, double grade = 8}) {
  return PendingSync(
    termId: 1,
    weekNumber: 2,
    studentId: 3,
    studentName: 'Student',
    grades: {'oral': grade},
    timestamp: timestamp,
    classId: 4,
    subject: 'Math',
    ownerKey: 'teacher:1',
  );
}

void main() {
  group('Crash-safe pending synchronization', () {
    test('replacing the same target is allowed when the queue is full', () {
      final old = _pending(timestamp: '2026-07-03T10:00:00Z');
      final newer = _pending(timestamp: '2026-07-03T10:00:01Z', grade: 9);

      final updated = PendingSyncQueue.upsert(
        current: [old],
        incoming: newer,
        maxItemsForOwner: 1,
      );

      expect(updated, [same(newer)]);
    });

    test('a distinct target cannot exceed the owner queue limit', () {
      final existing = _pending(timestamp: '2026-07-03T10:00:00Z');
      final distinct = PendingSync(
        termId: existing.termId,
        weekNumber: existing.weekNumber,
        studentId: 99,
        studentName: 'Another student',
        grades: existing.grades,
        timestamp: existing.timestamp,
        classId: existing.classId,
        subject: existing.subject,
        ownerKey: existing.ownerKey,
      );

      expect(
        () => PendingSyncQueue.upsert(
          current: [existing],
          incoming: distinct,
          maxItemsForOwner: 1,
        ),
        throwsStateError,
      );
    });

    test('removing a delivered revision preserves a newer queued revision', () {
      final delivered = _pending(timestamp: '2026-07-03T10:00:00Z');
      final newer = _pending(timestamp: '2026-07-03T10:00:01Z', grade: 9);

      final remaining = PendingSyncQueue.removeDelivered(
        current: [newer],
        delivered: [delivered],
      );

      expect(remaining, [same(newer)]);
    });

    test('removing delivered revisions does not affect another owner', () {
      final delivered = _pending(timestamp: '2026-07-03T10:00:00Z');
      final otherOwner = PendingSync(
        termId: delivered.termId,
        weekNumber: delivered.weekNumber,
        studentId: delivered.studentId,
        studentName: delivered.studentName,
        grades: delivered.grades,
        timestamp: delivered.timestamp,
        classId: delivered.classId,
        subject: delivered.subject,
        ownerKey: 'teacher:2',
      );

      final remaining = PendingSyncQueue.removeDelivered(
        current: [delivered, otherOwner],
        delivered: [delivered],
      );

      expect(remaining, [same(otherOwner)]);
    });
  });

  group('Voice number edge cases', () {
    test('preserves spoken order when Arabic words and digits are mixed', () {
      expect(NLPParser.parse('خمسة 10').numbers, [5, 10]);
    });

    test('parses a standalone half grade', () {
      expect(NLPParser.parse('نص').numbers, [0.5]);
    });

    test('adds a spoken fraction to the preceding digit', () {
      expect(NLPParser.parse('8 ونص').numbers, [8.5]);
    });
  });

  group('Grade integrity', () {
    test('locked state is restored from the backend payload', () {
      final student = Student.fromJson({
        'id': 1,
        'student_number': '1',
        'name': 'Student',
        'is_locked': true,
      });

      expect(student.isLocked, isTrue);
    });

    test(
      'analytics ignore grades for fields outside the current structure',
      () {
        final fields = [GradeField(name: 'oral', label: 'Oral', max: 10)];
        final student = Student(
          id: 1,
          studentNumber: '1',
          name: 'Student',
          grades: {'oral': 5, 'removed_field': 99},
        );

        final stats = AnalyticsService.calculate([student], fields);

        expect(stats.averageScore, 5);
        expect(stats.highestScore, 5);
        expect(stats.successRate, 100);
      },
    );
  });

  group('Commercial entitlement fail-closed behavior', () {
    test('missing subscription data never grants paid access', () {
      expect(Subscription.fromJson(null).isUsable, isFalse);
    });

    test('device limit rejection blocks an otherwise active subscription', () {
      final subscription = Subscription.fromJson({
        'plan': 'professional',
        'status': 'active',
        'device_limit_reached': true,
      });

      expect(subscription.isUsable, isFalse);
    });

    test('a user without subscription fields has no paid entitlement', () {
      final user = User.fromJson({
        'id': 1,
        'username': 'teacher',
        'email': 'teacher@example.com',
        'role': 'teacher',
      });

      expect(user.subscription.isUsable, isFalse);
    });

    test('plan limits expose device, seat, and trial-day constraints', () {
      final limits = PlanLimits.forPlan(SubscriptionPlan.school).toJson();

      expect(limits['max_devices'], isA<int>());
      expect(limits['max_seats'], isA<int>());
      expect(limits['trial_days'], isA<int>());
    });
  });

  group('Authenticated request isolation', () {
    test('requests captured before an account switch become stale', () {
      final epoch = AuthSessionEpoch();
      final requestEpoch = epoch.capture();

      expect(epoch.isCurrent(requestEpoch), isTrue);
      epoch.advance();
      expect(epoch.isCurrent(requestEpoch), isFalse);
    });

    test('sync identity is stable for an equivalent payload', () {
      final first = SyncRequestIdentity.forGrades(
        termId: 1,
        weekNumber: 2,
        classId: 3,
        subject: 'Math',
        grades: [
          {
            'student_id': 4,
            'timestamp': '2026-07-03T10:00:00Z',
            'grades': {'written': 9.0, 'oral': 8.0},
          },
        ],
      );
      final second = SyncRequestIdentity.forGrades(
        termId: 1,
        weekNumber: 2,
        classId: 3,
        subject: 'Math',
        grades: [
          {
            'student_id': 4,
            'timestamp': '2026-07-03T10:00:00Z',
            'grades': {'oral': 8.0, 'written': 9.0},
          },
        ],
      );

      expect(first, second);
      expect(first, hasLength(64));
    });
  });
}
