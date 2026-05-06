import 'package:flutter_test/flutter_test.dart';
import 'package:voice_grader/models/student_model.dart';

void main() {
  group('GradeField', () {
    test('creates with required fields', () {
      final field = GradeField(name: 'q1', label: 'سؤال 1', max: 10);
      expect(field.name, 'q1');
      expect(field.label, 'سؤال 1');
      expect(field.max, 10);
    });

    test('fromJson parses correctly with all fields', () {
      final field = GradeField.fromJson({
        'name': 'midterm',
        'label': 'منتصف الفصل',
        'max': 20,
      });
      expect(field.name, 'midterm');
      expect(field.label, 'منتصف الفصل');
      expect(field.max, 20.0);
    });

    test('fromJson handles missing label by using name', () {
      final field = GradeField.fromJson({'name': 'final', 'max': 30});
      expect(field.label, 'final');
    });

    test('fromJson handles string max value', () {
      final field = GradeField.fromJson({
        'name': 'q',
        'label': 'L',
        'max': '15.5',
      });
      expect(field.max, 15.5);
    });

    test('fromJson handles invalid max gracefully', () {
      final field = GradeField.fromJson({
        'name': 'q',
        'label': 'L',
        'max': 'invalid',
      });
      expect(field.max, 0);
    });

    test('toJson produces correct map', () {
      final field = GradeField(name: 'q1', label: 'L1', max: 10);
      final json = field.toJson();
      expect(json['name'], 'q1');
      expect(json['label'], 'L1');
      expect(json['max'], 10);
    });
  });

  group('Student', () {
    test('creates with required fields and defaults', () {
      final s = Student(id: 1, studentNumber: '001', name: 'أحمد');
      expect(s.id, 1);
      expect(s.studentNumber, '001');
      expect(s.name, 'أحمد');
      expect(s.grades, isEmpty);
      expect(s.existingGrades, isEmpty);
      expect(s.isLocked, false);
    });

    test('total calculates sum of grades correctly', () {
      final s = Student(
        id: 1,
        studentNumber: '001',
        name: 'محمد',
        grades: {'q1': 10, 'q2': 15, 'q3': 8},
      );
      expect(s.total, 33);
    });

    test('total handles empty grades safely', () {
      final s = Student(id: 1, studentNumber: '001', name: 'علي');
      expect(s.total, 0);
    });

    test('total ignores non-finite values (NaN, Infinity)', () {
      final s = Student(
        id: 1,
        studentNumber: '001',
        name: 'سارة',
        grades: {'q1': 10, 'q2': double.nan, 'q3': double.infinity, 'q4': 5},
      );
      expect(s.total, 15);
    });

    test('fromJson parses Student correctly', () {
      final s = Student.fromJson({
        'id': 5,
        'student_number': '005',
        'name': 'فاطمة',
        'existing_grades': {'q1': 10, 'q2': 8.5},
      });
      expect(s.id, 5);
      expect(s.name, 'فاطمة');
      expect(s.existingGrades['q1'], 10.0);
      expect(s.existingGrades['q2'], 8.5);
      expect(s.grades['q1'], 10.0);
    });

    test('fromJson handles string id', () {
      final s = Student.fromJson({
        'id': '42',
        'student_number': '042',
        'name': 'خالد',
      });
      expect(s.id, 42);
    });

    test('fromJson uses fallback name field full_name', () {
      final s = Student.fromJson({
        'id': 1,
        'student_number': '001',
        'full_name': 'سعيد',
      });
      expect(s.name, 'سعيد');
    });

    test('toJson produces complete map', () {
      final s = Student(
        id: 1,
        studentNumber: '001',
        name: 'حسن',
        grades: {'q1': 10},
        isLocked: true,
      );
      final json = s.toJson();
      expect(json['id'], 1);
      expect(json['student_number'], '001');
      expect(json['name'], 'حسن');
      expect(json['grades']['q1'], 10);
      expect(json['is_locked'], true);
    });
  });

  group('ClassroomData', () {
    test('creates with all required fields', () {
      final data = ClassroomData(
        classId: 1,
        className: '5/أ',
        subject: 'الرياضيات',
        fields: [GradeField(name: 'q1', label: 'L1', max: 10)],
        students: [Student(id: 1, studentNumber: '001', name: 'أحمد')],
      );
      expect(data.classId, 1);
      expect(data.className, '5/أ');
      expect(data.subject, 'الرياضيات');
      expect(data.fields.length, 1);
      expect(data.students.length, 1);
    });
  });
}
