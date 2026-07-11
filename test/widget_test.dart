import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/student_model.dart';
import 'package:study_grades_voice/services/nlp_parser.dart';
import 'package:study_grades_voice/widgets/grade_field_card.dart';

void main() {
  group('NLPParser - Egyptian Dialect Numbers', () {
    test('parses Latin digits', () {
      final r = NLPParser.parse('15 20 8.5');
      expect(r.numbers, [15, 20, 8.5]);
    });

    test('parses Arabic single-digit words', () {
      final r = NLPParser.parse('خمسة سبعة تسعة');
      expect(r.numbers, [5, 7, 9]);
    });

    test('parses compound numbers like "خمسة وعشرين"', () {
      final r = NLPParser.parse('خمسة وعشرين');
      expect(r.numbers, [25]);
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

  group('GradeFieldCard', () {
    testWidgets('accepts Arabic digits and decimal comma', (tester) async {
      double? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GradeFieldCard(
                field: GradeField(name: 'oral', label: 'Oral', max: 20),
                value: null,
                onChanged: (v) => value = v,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '\u0661\u0662,\u0665');

      expect(value, 12.5);
    });

    testWidgets('normalizes text when value exceeds max', (tester) async {
      double? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GradeFieldCard(
                field: GradeField(name: 'oral', label: 'Oral', max: 15),
                value: null,
                onChanged: (v) => value = v,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '99');
      final field = tester.widget<TextField>(find.byType(TextField));

      expect(value, 15);
      expect(field.controller?.text, '15');
    });

    testWidgets('clears focused text when parent value becomes null', (
      tester,
    ) async {
      Widget build(double? value) {
        return MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GradeFieldCard(
                field: GradeField(name: 'oral', label: 'Oral', max: 15),
                value: value,
                onChanged: (_) {},
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build(15));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pumpWidget(build(null));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '');
    });
  });
}
