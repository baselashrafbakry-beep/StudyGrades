class PendingSync {
  final int studentId;
  final String studentName;
  final Map<String, double> grades;
  final String timestamp;
  final int classId;
  final String subject;

  PendingSync({
    required this.studentId,
    required this.studentName,
    required this.grades,
    required this.timestamp,
    required this.classId,
    required this.subject,
  });

  Map<String, dynamic> toJson() => {
    'student_id': studentId,
    'student_name': studentName,
    'grades': grades,
    'timestamp': timestamp,
    'class_id': classId,
    'subject': subject,
  };

  factory PendingSync.fromJson(Map<String, dynamic> json) {
    final raw = json['grades'] as Map? ?? {};
    final grades = <String, double>{};
    raw.forEach((k, v) {
      if (v is num) grades[k.toString()] = v.toDouble();
      if (v is String) grades[k.toString()] = double.tryParse(v) ?? 0;
    });
    return PendingSync(
      studentId: json['student_id'] is int
          ? json['student_id']
          : int.tryParse('${json['student_id']}') ?? 0,
      studentName: json['student_name']?.toString() ?? '',
      grades: grades,
      timestamp: json['timestamp']?.toString() ?? '',
      classId: json['class_id'] is int
          ? json['class_id']
          : int.tryParse('${json['class_id']}') ?? 0,
      subject: json['subject']?.toString() ?? 'General',
    );
  }
}
