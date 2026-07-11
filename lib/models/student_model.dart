class GradeField {
  final String name;
  final String label;
  final double max;

  GradeField({required this.name, required this.label, required this.max});

  factory GradeField.fromJson(Map<String, dynamic> json) {
    final parsedMax = _toDouble(json['max']);
    return GradeField(
      name: json['name']?.toString() ?? '',
      label: json['label']?.toString() ?? json['name']?.toString() ?? '',
      max: parsedMax != null && parsedMax.isFinite && parsedMax > 0
          ? parsedMax
          : 100,
    );
  }

  static GradeField? tryFromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final parsedMax = _toDouble(json['max']);
    if (name.isEmpty ||
        parsedMax == null ||
        !parsedMax.isFinite ||
        parsedMax <= 0) {
      return null;
    }
    return GradeField(
      name: name,
      label: json['label']?.toString() ?? name,
      max: parsedMax,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static double clampGrade(double value, GradeField field) {
    if (!value.isFinite) return 0;
    final max = field.max.isFinite && field.max > 0 ? field.max : 100;
    return value.clamp(0, max).toDouble();
  }

  Map<String, dynamic> toJson() => {'name': name, 'label': label, 'max': max};
}

class Student {
  final int id;
  final String studentNumber;
  final String name;
  Map<String, double> existingGrades;
  Map<String, double> grades;
  bool isLocked;

  Student({
    required this.id,
    required this.studentNumber,
    required this.name,
    Map<String, double>? existingGrades,
    Map<String, double>? grades,
    this.isLocked = false,
  }) : existingGrades = existingGrades ?? {},
       grades = grades ?? {};

  factory Student.fromJson(Map<String, dynamic> json) {
    final existing = <String, double>{};
    final raw = json['existing_grades'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final parsed = GradeField._toDouble(v);
        if (parsed != null && parsed.isFinite) {
          existing[k.toString()] = parsed;
        }
      });
    }
    return Student(
      id: _toInt(json['id']),
      studentNumber:
          json['student_number']?.toString() ??
          json['number']?.toString() ??
          '',
      name: json['name']?.toString() ?? json['full_name']?.toString() ?? '',
      existingGrades: existing,
      grades: Map<String, double>.from(existing),
      isLocked: _toBool(json['is_locked'] ?? json['locked']),
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  double get total =>
      grades.values.fold<double>(0, (sum, v) => sum + (v.isFinite ? v : 0));

  double totalFor(List<GradeField> fields) {
    return fields.fold<double>(0, (sum, field) {
      final value = grades[field.name];
      if (value == null || !value.isFinite) return sum;
      return sum + GradeField.clampGrade(value, field);
    });
  }

  int completedFieldCount(List<GradeField> fields) {
    return fields.where((field) {
      final value = grades[field.name];
      return value != null && value.isFinite;
    }).length;
  }

  bool isCompleteFor(List<GradeField> fields) {
    return fields.isNotEmpty && completedFieldCount(fields) == fields.length;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'student_number': studentNumber,
    'name': name,
    'grades': grades,
    'existing_grades': existingGrades,
    'is_locked': isLocked,
  };
}

class ClassroomData {
  final int classId;
  final String className;
  final String subject;
  final List<GradeField> fields;
  final List<Student> students;

  ClassroomData({
    required this.classId,
    required this.className,
    required this.subject,
    required this.fields,
    required this.students,
  });

  factory ClassroomData.fromJson(
    Map<String, dynamic> json, {
    String? className,
    String? subject,
  }) {
    // grade_structure may be:
    //  - a List<Map> directly (production API)  e.g. [{"name":"reading","label":"...","max":15}, ...]
    //  - a Map containing a 'fields' List         e.g. {"fields":[...]}
    //  - missing entirely
    final structureRaw = json['grade_structure'];
    List fieldsList;
    if (structureRaw is List) {
      fieldsList = structureRaw;
    } else if (structureRaw is Map) {
      final inner = structureRaw['fields'];
      fieldsList = inner is List ? inner : const [];
    } else {
      fieldsList = const [];
    }

    // Some old endpoints return "fields" at the top-level instead of grade_structure
    if (fieldsList.isEmpty && json['fields'] is List) {
      fieldsList = json['fields'] as List;
    }

    final studentsList = json['students'] as List? ?? const [];
    return ClassroomData(
      classId: Student._toInt(json['class_id'] ?? json['id']),
      className: className ?? json['class_name']?.toString() ?? 'فصل',
      subject: subject ?? json['subject']?.toString() ?? 'عام',
      fields: fieldsList
          .whereType<Map>()
          .map((e) => GradeField.tryFromJson(Map<String, dynamic>.from(e)))
          .whereType<GradeField>()
          .toList(),
      students: studentsList
          .whereType<Map>()
          .map((e) => Student.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
