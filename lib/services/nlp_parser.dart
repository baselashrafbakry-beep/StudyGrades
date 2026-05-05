import '../models/student_model.dart';

/// NLP Parser for Arabic Voice Input - Egyptian Dialect Support
/// Extracts numbers (grades) and commands from transcribed Arabic speech.
class NLPResult {
  final List<double> numbers;
  final Set<String> commands;
  final String originalText;

  NLPResult({
    required this.numbers,
    required this.commands,
    required this.originalText,
  });

  bool get hasNext => commands.contains('next');
  bool get hasPrevious => commands.contains('previous');
  bool get hasSave => commands.contains('save');
  bool get hasClear => commands.contains('clear');
  bool get hasAbsent => commands.contains('absent');
  bool get hasConfirm => commands.contains('confirm');
  bool get hasStop => commands.contains('stop');
  bool get hasRepeat => commands.contains('repeat');
  bool get hasFull => commands.contains('full');
  bool get hasZero => commands.contains('zero');
  bool get isEmpty =>
      numbers.isEmpty && commands.isEmpty && originalText.trim().isEmpty;
}

class NLPParser {
  static const Map<String, List<String>> _commandKeywords = {
    'next': [
      'الطالب التالي',
      'التالي',
      'بعده',
      'بعدها',
      'اللي بعده',
      'اللي بعدها',
      'كمل',
      'كملي',
      'استمر',
      'next',
      'forward',
    ],
    'previous': [
      'الطالب السابق',
      'السابق',
      'قبله',
      'قبلها',
      'اللي قبله',
      'اللي قبلها',
      'ارجع',
      'رجوع',
      'previous',
      'back',
    ],
    'clear': [
      'امسح',
      'مسح',
      'حذف',
      'احذف',
      'تصفير',
      'صفر',
      'خطا',
      'غلط',
      'الغي',
      'الغاء',
      'clear',
      'cancel',
      'reset',
    ],
    'save': [
      'حفظ',
      'احفظ',
      'سجل',
      'save',
    ],
    'absent': [
      'غائب',
      'غايب',
      'غايبة',
      'غائبة',
      'مش موجود',
      'مش موجوده',
      'مش هنا',
      'لم يحضر',
      'absent',
    ],
    'confirm': [
      'تاكيد',
      'موافق',
      'تمام',
      'اوكي',
      'اوك',
      'تم',
      'خلاص',
      'confirm',
      'ok',
      'yes',
    ],
    'stop': [
      'ايقاف',
      'وقف',
      'توقف',
      'انهاء',
      'انه',
      'خلصت',
      'انتهيت',
      'stop',
      'pause',
    ],
    'repeat': [
      'كرر',
      'اعد',
      'مره تانيه',
      'تاني',
      'repeat',
      'again',
    ],
    'full': [
      'كامله',
      'كامل',
      'النهايه',
      'النهايه العظمي',
      'الدرجه كامله',
      'كامل العلامه',
      'علامه كامله',
      'full',
      'max',
    ],
    'zero': [
      'صفر',
      'لا شيء',
      'مفيش',
      'zero',
    ],
  };

  /// Note: keys are stored AFTER normalization (ة→ه, إأآا→ا, ى→ي, no tashkeel)
  static const Map<String, double> _arabicNumbers = {
    // أرقام أساسية
    'صفر': 0, 'زيرو': 0, 'سفر': 0,
    'واحد': 1, 'واحده': 1, 'وحده': 1,
    'اتنين': 2, 'اثنان': 2, 'اثنين': 2, 'تنين': 2,
    'تلاته': 3, 'ثلاثه': 3, 'تلات': 3, 'ثلاث': 3, 'تلاتا': 3,
    'اربعه': 4, 'اربع': 4, 'اربعا': 4,
    'خمسه': 5, 'خمس': 5, 'خمسا': 5,
    'سته': 6, 'ست': 6, 'ستا': 6,
    'سبعه': 7, 'سبع': 7, 'سبعا': 7,
    'تمانيه': 8, 'ثمانيه': 8, 'تمان': 8, 'ثمان': 8, 'تمانيا': 8,
    'تسعه': 9, 'تسع': 9, 'تسعا': 9,
    'عشره': 10, 'عشر': 10, 'عشرا': 10,

    // 11-19
    'حدعشر': 11, 'حداشر': 11, 'احدعشر': 11, 'احد عشر': 11, 'احدي عشر': 11,
    'اتناشر': 12, 'اثناشر': 12, 'اتنين عشر': 12, 'اثني عشر': 12,
    'تلاتاشر': 13, 'ثلاثه عشر': 13, 'تلت عشر': 13,
    'اربعتاشر': 14, 'اربعطاشر': 14, 'اربعه عشر': 14, 'اربع عشر': 14,
    'خمستاشر': 15, 'خمسطاشر': 15, 'خمسه عشر': 15, 'خمس عشر': 15,
    'ستاشر': 16, 'سطاشر': 16, 'سته عشر': 16, 'ست عشر': 16,
    'سبعتاشر': 17, 'سبعطاشر': 17, 'سبعه عشر': 17, 'سبع عشر': 17,
    'تمنتاشر': 18, 'تمانتاشر': 18, 'تمانيه عشر': 18, 'ثمانيه عشر': 18,
    'تسعتاشر': 19, 'تسعطاشر': 19, 'تسعه عشر': 19, 'تسع عشر': 19,

    // عشرات
    'عشرين': 20, 'عشرون': 20,
    'تلاتين': 30, 'ثلاثين': 30, 'ثلاثون': 30,
    'اربعين': 40, 'اربعون': 40,
    'خمسين': 50, 'خمسون': 50,
    'ستين': 60, 'ستون': 60,
    'سبعين': 70, 'سبعون': 70,
    'تمانين': 80, 'ثمانين': 80,
    'تسعين': 90, 'تسعون': 90,
    'ميه': 100, 'مايه': 100, 'مئه': 100, 'مايا': 100,

    // الكسور (مع مفهوم النصف والربع)
    'ونص': 0.5, 'نص': 0.5, 'نصف': 0.5, 'ونصف': 0.5,
    'وربع': 0.25, 'ربع': 0.25,
    'وتلت': 0.33, 'تلت': 0.33,
    'وثلاثه ارباع': 0.75,
  };

  /// خريطة الأرقام العربية الهندية إلى لاتينية
  static const Map<String, String> _arabicDigitsMap = {
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };

  static String _normalize(String text) {
    var t = text.trim().toLowerCase();
    // Convert Arabic-Indic digits to Latin
    _arabicDigitsMap.forEach((ar, la) => t = t.replaceAll(ar, la));
    // Remove tashkeel
    t = t.replaceAll(RegExp(r'[\u064B-\u0652]'), '');
    // Normalize alef forms
    t = t.replaceAll(RegExp(r'[إأآا]'), 'ا');
    t = t.replaceAll('ى', 'ي');
    t = t.replaceAll('ة', 'ه');
    t = t.replaceAll('ؤ', 'و');
    t = t.replaceAll('ئ', 'ي');
    // Remove punctuation (preserve dots in numbers like 8.5)
    t = t.replaceAll(RegExp(r'[,،؛؟!:؟"\(\)\[\]{}\-_/\\]'), ' ');
    // Collapse whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static NLPResult parse(String text) {
    if (text.isEmpty) {
      return NLPResult(
        numbers: const [],
        commands: const {},
        originalText: text,
      );
    }

    final normalized = _normalize(text);
    final numbers = <double>[];
    final commands = <String>{};

    // 1) Extract Latin / Arabic-Indic digits (e.g. "15", "20.5")
    final digitMatches = RegExp(r'\d+(?:\.\d+)?').allMatches(normalized);
    for (final m in digitMatches) {
      final v = double.tryParse(m.group(0)!);
      if (v != null) numbers.add(v);
    }

    // 2) Extract Egyptian dialect words (already normalized via _normalize)
    final words = normalized.split(' ');
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;

      // Try the word as-is, or stripped of leading "و" (and)
      String? matched;
      if (_arabicNumbers.containsKey(w)) {
        matched = w;
      } else if (w.startsWith('و') &&
          _arabicNumbers.containsKey(w.substring(1))) {
        matched = w.substring(1);
      }

      if (matched != null) {
        final n = _arabicNumbers[matched]!;
        // Fractions append to last number
        if ((n == 0.5 || n == 0.25 || n == 0.33 || n == 0.75) &&
            numbers.isNotEmpty) {
          numbers[numbers.length - 1] = numbers.last + n;
          continue;
        }
        if (n < 10 && i + 1 < words.length) {
          // Try compound: e.g. "خمسة وعشرين" -> 25
          var nextW = words[i + 1];
          if (nextW.startsWith('و')) nextW = nextW.substring(1);
          if (_arabicNumbers.containsKey(nextW) &&
              _arabicNumbers[nextW]! >= 20 &&
              _arabicNumbers[nextW]! % 10 == 0) {
            numbers.add(n + _arabicNumbers[nextW]!);
            i++; // skip next
            continue;
          }
          numbers.add(n);
        } else {
          numbers.add(n);
        }
      }
    }

    // 3) Extract commands. Use word-boundary-ish matches to avoid false hits
    _commandKeywords.forEach((cmd, keys) {
      for (final k in keys) {
        final nk = _normalize(k);
        if (nk.isEmpty) continue;
        // Phrases (with spaces) -> contains; single words -> word-boundary
        if (nk.contains(' ')) {
          if (normalized.contains(nk)) {
            commands.add(cmd);
            break;
          }
        } else {
          // Match as a whole word: surrounded by start/end or whitespace
          final pattern = RegExp(
            '(^|\\s)${RegExp.escape(nk)}(\\s|\$)',
          );
          if (pattern.hasMatch(normalized)) {
            commands.add(cmd);
            break;
          }
        }
      }
    });

    // Special heuristic: if user said "صفر" alone with no other numbers,
    // treat it as a number 0 (not just the "zero" command).
    if (commands.contains('zero') && numbers.isEmpty) {
      numbers.add(0);
    }

    return NLPResult(
      numbers: numbers,
      commands: commands,
      originalText: text,
    );
  }

  /// Distribute parsed numbers across grade fields, respecting max limits
  /// Strategy: fill empty/zero fields first; if all filled, overwrite from the start.
  static Map<String, double> distributeGrades(
    List<double> numbers,
    List<GradeField> fields,
    Map<String, double> currentGrades,
  ) {
    final updated = Map<String, double>.from(currentGrades);
    if (numbers.isEmpty || fields.isEmpty) return updated;

    var idx = 0;

    // Pass 1: fill empty fields (not yet present)
    for (final f in fields) {
      if (idx >= numbers.length) break;
      if (!updated.containsKey(f.name)) {
        final v = numbers[idx].clamp(0, f.max).toDouble();
        updated[f.name] = v;
        idx++;
      }
    }

    // Pass 2: overwrite from beginning if numbers remain
    if (idx < numbers.length) {
      for (final f in fields) {
        if (idx >= numbers.length) break;
        final v = numbers[idx].clamp(0, f.max).toDouble();
        updated[f.name] = v;
        idx++;
      }
    }

    return updated;
  }
}
