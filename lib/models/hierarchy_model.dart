class ClassroomItem {
  final int id;
  final String name;
  final String? subject;

  ClassroomItem({required this.id, required this.name, this.subject});

  factory ClassroomItem.fromJson(Map<String, dynamic> json) {
    return ClassroomItem(
      id: _toInt(json['id']),
      name: json['name']?.toString() ?? 'فصل بدون اسم',
      subject: json['subject']?.toString(),
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

class HierarchyItem {
  final int id;
  final String name;
  final List<ClassroomItem> classes;

  HierarchyItem({
    required this.id,
    required this.name,
    this.classes = const [],
  });

  factory HierarchyItem.fromJson(Map<String, dynamic> json) {
    final rawClasses = json['classes'] ?? json['classrooms'];
    final list = rawClasses is List ? rawClasses : const [];
    return HierarchyItem(
      id: ClassroomItem._toInt(json['id']),
      name: json['name']?.toString() ?? '',
      classes: list
          .whereType<Map>()
          .map((e) => ClassroomItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
