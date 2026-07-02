import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/services/nlp_parser.dart';

void main() {
  group('NLPParser - Egyptian Dialect Numbers', () {
    test('parses Latin digits', () {
      final r = NLPParser.parse('15 20 8.5');
      expect(r.numbers, [15, 20, 8.5]);
    });

    test('parses Arabic single-digit words', () {
      final r = NLPParser.parse('خمسة سبعة عشرة');
      expect(r.numbers.contains(5), true);
      expect(r.numbers.contains(7), true);
      expect(r.numbers.contains(10), true);
    });

    test('parses compound numbers like "خمسة وعشرين"', () {
      final r = NLPParser.parse('خمسة وعشرين');
      expect(r.numbers, contains(25));
    });

    test('detects next command', () {
      final r = NLPParser.parse('خلاص التالي');
      expect(r.hasNext, true);
    });

    test('detects clear command', () {
      final r = NLPParser.parse('امسح');
      expect(r.hasClear, true);
    });
  });
}
