import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/academic_period.dart';

void main() {
  group('AcademicPeriod', () {
    test('accepts supported terms and weeks', () {
      expect(const AcademicPeriod(termId: 1, weekNumber: 1).termId, 1);
      expect(const AcademicPeriod(termId: 2, weekNumber: 18).weekNumber, 18);
    });

    test('rejects out-of-range terms and weeks', () {
      expect(
        () => AcademicPeriod.validated(termId: 0, weekNumber: 1),
        throwsRangeError,
      );
      expect(
        () => AcademicPeriod.validated(termId: 3, weekNumber: 1),
        throwsRangeError,
      );
      expect(
        () => AcademicPeriod.validated(termId: 1, weekNumber: 0),
        throwsRangeError,
      );
      expect(
        () => AcademicPeriod.validated(termId: 1, weekNumber: 53),
        throwsRangeError,
      );
    });

    test('has a stable storage key', () {
      expect(
        const AcademicPeriod(termId: 2, weekNumber: 7).storageKey,
        'term_2_week_7',
      );
    });
  });
}
