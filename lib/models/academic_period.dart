class AcademicPeriod {
  final int termId;
  final int weekNumber;

  const AcademicPeriod({required this.termId, required this.weekNumber});

  factory AcademicPeriod.validated({
    required int termId,
    required int weekNumber,
  }) {
    if (termId < 1 || termId > 2) {
      throw RangeError.range(termId, 1, 2, 'termId');
    }
    if (weekNumber < 1 || weekNumber > 52) {
      throw RangeError.range(weekNumber, 1, 52, 'weekNumber');
    }
    return AcademicPeriod(termId: termId, weekNumber: weekNumber);
  }

  String get storageKey => 'term_${termId}_week_$weekNumber';
}
