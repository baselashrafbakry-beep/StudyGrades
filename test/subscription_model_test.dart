import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/subscription_model.dart';

void main() {
  group('Subscription model', () {
    test('normalizes aliases and applies professional limits', () {
      final subscription = Subscription.fromJson({
        'plan': 'pro',
        'status': 'paid',
      });

      expect(subscription.plan, SubscriptionPlan.professional);
      expect(subscription.status, SubscriptionStatus.active);
      expect(subscription.canUseServerTranscription, isTrue);
      expect(subscription.canExportReports, isTrue);
      expect(subscription.canUseStudentCount(121), isFalse);
    });

    test('expired date blocks paid features', () {
      final subscription = Subscription.fromJson({
        'plan': 'school',
        'status': 'active',
        'expires_at': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });

      expect(subscription.isUsable, isFalse);
      expect(subscription.canExportReports, isFalse);
      expect(subscription.statusLabel, 'منتهي');
    });

    test('custom limits override plan defaults', () {
      final subscription = Subscription.fromJson({
        'plan': 'starter',
        'status': 'active',
        'limits': {
          'max_students_per_class': 12,
          'max_pending_sync': 5,
          'server_transcription': true,
        },
      });

      expect(subscription.canUseStudentCount(12), isTrue);
      expect(subscription.canUseStudentCount(13), isFalse);
      expect(subscription.canQueueMorePending(4), isTrue);
      expect(subscription.canQueueMorePending(5), isFalse);
      expect(subscription.canUseServerTranscription, isTrue);
    });
  });
}
