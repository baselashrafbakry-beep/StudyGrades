import 'package:flutter_test/flutter_test.dart';
import 'package:voice_grader/services/nlp_parser.dart';

void main() {
  group('NLPParser - Numbers (Latin & Arabic digits)', () {
    test('parses Latin digits including decimals', () {
      final r = NLPParser.parse('10 12.5 18');
      expect(r.numbers, containsAll([10, 12.5, 18]));
    });

    test('parses decimal comma as one decimal grade', () {
      final r = NLPParser.parse('12,5');
      expect(r.numbers, [12.5]);
    });

    test('parses Arabic-Indic digits (٠-٩)', () {
      final r = NLPParser.parse('١٥ ٢٠ ٨');
      expect(r.numbers, containsAll([15, 20, 8]));
    });

    test('returns empty list when no numbers present', () {
      final r = NLPParser.parse('مرحبا كيف حالك');
      expect(r.numbers, isEmpty);
    });
  });

  group('NLPParser - Egyptian Dialect Words', () {
    test('parses single-digit Arabic words', () {
      final r = NLPParser.parse('خمسة');
      expect(r.numbers, contains(5));
    });

    test('parses tens (عشرة, عشرين, ثلاثين)', () {
      final r1 = NLPParser.parse('عشرة');
      final r2 = NLPParser.parse('عشرين');
      final r3 = NLPParser.parse('ثلاثين');
      expect(r1.numbers, contains(10));
      expect(r2.numbers, contains(20));
      expect(r3.numbers, contains(30));
    });

    test('parses compound numbers (e.g., خمسة وعشرين = 25)', () {
      final r = NLPParser.parse('خمسة وعشرين');
      expect(r.numbers, contains(25));
    });

    test('parses compound 35 (خمسة وثلاثين)', () {
      final r = NLPParser.parse('خمسة وثلاثين');
      expect(r.numbers, contains(35));
    });

    test('parses multi-word teens once', () {
      final r = NLPParser.parse('خمسة عشر');
      expect(r.numbers, [15]);
    });

    test('preserves repeated equal grades', () {
      final r = NLPParser.parse('خمسة خمسة');
      expect(r.numbers, [5, 5]);
    });

    test('keeps leading waw when it is part of one', () {
      expect(NLPParser.parse('\u0648\u0627\u062D\u062F').numbers, [1]);
      expect(NLPParser.parse('\u0648\u0627\u062D\u062F\u0629').numbers, [1]);
      expect(
        NLPParser.parse('\u0648\u0627\u062D\u062F \u0648\u0646\u0635').numbers,
        [1.5],
      );
      expect(
        NLPParser.parse(
          '\u0648\u0627\u062D\u062F \u0648\u0639\u0634\u0631\u064A\u0646',
        ).numbers,
        [21],
      );
    });
  });

  group('NLPParser - Voice Commands', () {
    test('detects next command in different forms', () {
      expect(NLPParser.parse('التالي').hasNext, true);
      expect(NLPParser.parse('خلاص التالي').hasNext, true);
    });

    test('detects clear/erase command', () {
      expect(NLPParser.parse('امسح').hasClear, true);
    });

    test('detects save command', () {
      expect(NLPParser.parse('احفظ').hasSave, true);
    });

    test('detects absent command', () {
      expect(NLPParser.parse('غائب').hasAbsent, true);
    });

    test('detects previous student command', () {
      expect(NLPParser.parse('السابق').hasPrevious, true);
    });
  });

  group('NLPParser - Robustness', () {
    test('handles empty string safely', () {
      final r = NLPParser.parse('');
      expect(r.numbers, isEmpty);
      expect(r.hasNext, false);
    });

    test('handles extra whitespace gracefully', () {
      final r = NLPParser.parse('   15    20   ');
      expect(r.numbers, containsAll([15, 20]));
    });

    test('mixes numbers and commands', () {
      final r = NLPParser.parse('15 20 التالي');
      expect(r.numbers, containsAll([15, 20]));
      expect(r.hasNext, true);
    });
  });
}
