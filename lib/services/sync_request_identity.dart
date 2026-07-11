import 'dart:convert';

import 'package:crypto/crypto.dart';

class SyncRequestIdentity {
  const SyncRequestIdentity._();

  static String forGrades({
    required int termId,
    required int weekNumber,
    required int? classId,
    required String subject,
    required List<Map<String, dynamic>> grades,
  }) {
    final canonical = _canonicalize({
      'term_id': termId,
      'week_number': weekNumber,
      'class_id': classId,
      'subject': subject,
      'grades': grades,
    });
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }
}
