class PendingSync {
  final int termId;
  final int weekNumber;
  final int studentId;
  final String studentName;
  final Map<String, double> grades;
  final String timestamp;
  final int classId;
  final String subject;
  final String ownerKey;

  PendingSync({
    required this.termId,
    required this.weekNumber,
    required this.studentId,
    required this.studentName,
    required this.grades,
    required this.timestamp,
    required this.classId,
    required this.subject,
    this.ownerKey = '',
  });

  Map<String, dynamic> toJson() => {
    'term_id': termId,
    'week_number': weekNumber,
    'student_id': studentId,
    'student_name': studentName,
    'grades': grades,
    'timestamp': timestamp,
    'class_id': classId,
    'subject': subject,
    'owner_key': ownerKey,
  };

  bool hasSameTarget(PendingSync other) {
    return termId == other.termId &&
        weekNumber == other.weekNumber &&
        classId == other.classId &&
        subject == other.subject &&
        studentId == other.studentId &&
        ownerKey == other.ownerKey;
  }

  bool hasSameRevision(PendingSync other) {
    return hasSameTarget(other) && timestamp == other.timestamp;
  }

  PendingSync withOwner(String owner) {
    return PendingSync(
      termId: termId,
      weekNumber: weekNumber,
      studentId: studentId,
      studentName: studentName,
      grades: grades,
      timestamp: timestamp,
      classId: classId,
      subject: subject,
      ownerKey: owner,
    );
  }

  factory PendingSync.fromJson(Map<String, dynamic> json) {
    final raw = json['grades'] as Map? ?? {};
    final grades = <String, double>{};
    raw.forEach((k, v) {
      if (v is num) grades[k.toString()] = v.toDouble();
      if (v is String) grades[k.toString()] = double.tryParse(v) ?? 0;
    });
    return PendingSync(
      termId: _toInt(json['term_id'], fallback: 1),
      weekNumber: _toInt(json['week_number'], fallback: 1),
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
      ownerKey: json['owner_key']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}

class PendingSyncQueue {
  const PendingSyncQueue._();

  static List<PendingSync> upsert({
    required List<PendingSync> current,
    required PendingSync incoming,
    required int maxItemsForOwner,
  }) {
    final updated = current
        .where((entry) => !entry.hasSameTarget(incoming))
        .toList(growable: true)
      ..add(incoming);
    final ownerCount = updated
        .where((entry) => entry.ownerKey == incoming.ownerKey)
        .length;
    if (maxItemsForOwner <= 0 || ownerCount > maxItemsForOwner) {
      throw StateError(
        'Pending sync queue limit reached. Sync queued grades before saving more offline grades.',
      );
    }
    return updated;
  }

  static List<PendingSync> removeDelivered({
    required List<PendingSync> current,
    required Iterable<PendingSync> delivered,
  }) {
    final deliveredRevisions = delivered.toList(growable: false);
    return current
        .where(
          (entry) => !deliveredRevisions.any(entry.hasSameRevision),
        )
        .toList(growable: false);
  }
}
