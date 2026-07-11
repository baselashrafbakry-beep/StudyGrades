import '../models/student_model.dart';

/// NLP Parser for Arabic Voice Input - Egyptian & MSA Dialect Support
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

class _ArabicNumberMatch {
  final double value;
  final int consumed;

  const _ArabicNumberMatch(this.value, this.consumed);
}

class NLPParser {
  // ثغرة مُصلَحة: "صفر" معزولة = رقم 0، وليس أمر "clear"
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
      'كمل معايا',
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
      // ثغرة مُصلَحة: أُزيلت كلمة "صفر" من أوامر المسح - تُعالج كرقم 0
      'خطا',
      'غلط',
      'الغي',
      'الغاء',
      'clear',
      'cancel',
      'reset',
      'إعادة',
    ],
    'save': ['حفظ', 'احفظ', 'سجل', 'save', 'حفظ الآن'],
    'absent': [
      'غائب',
      'غايب',
      'غايبة',
      'غائبة',
      'مش موجود',
      'مش موجوده',
      'مش هنا',
      'لم يحضر',
      'لم تحضر',
      'absent',
    ],
    'confirm': [
      'تاكيد',
      'تأكيد',
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
      'إيقاف',
      'وقف',
      'توقف',
      'انهاء',
      'إنهاء',
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
      'مرة تانية',
      'تاني',
      'repeat',
      'again',
    ],
    'full': [
      'كامله',
      'كامل',
      'النهايه',
      'النهاية',
      'النهايه العظمي',
      'الدرجه كامله',
      'كامل العلامه',
      'علامه كامله',
      'درجة كاملة',
      'full',
      'max',
      'علامة كاملة',
    ],
    'zero': [
      // "صفر" وحدها بلا سياق أرقام أخرى -> رقم 0
      'صفر',
      'لا شيء',
      'مفيش',
      'zero',
    ],
  };

  /// الأرقام مُخزَّنة بعد التطبيع (ة→ه، إأآا→ا، ى→ي، بدون تشكيل)
  static const Map<String, double> _arabicNumbers = {
    // أرقام أساسية
    'صفر': 0,
    'زيرو': 0,
    'سفر': 0,
    'واحد': 1,
    'واحده': 1,
    'وحده': 1,
    'واحدة': 1,
    'اتنين': 2,
    'اثنان': 2,
    'اثنين': 2,
    'تنين': 2,
    'تلاته': 3,
    'ثلاثه': 3,
    'تلات': 3,
    'ثلاث': 3,
    'تلاتا': 3,
    'ثلاثة': 3,
    'اربعه': 4,
    'اربع': 4,
    'اربعا': 4,
    'أربعة': 4,
    'خمسه': 5,
    'خمس': 5,
    'خمسا': 5,
    'خمسة': 5,
    'سته': 6,
    'ست': 6,
    'ستا': 6,
    'ستة': 6,
    'سبعه': 7,
    'سبع': 7,
    'سبعا': 7,
    'سبعة': 7,
    'تمانيه': 8,
    'ثمانيه': 8,
    'تمان': 8,
    'ثمان': 8,
    'تمانيا': 8,
    'ثمانية': 8,
    'تسعه': 9,
    'تسع': 9,
    'تسعا': 9,
    'تسعة': 9,
    'عشره': 10,
    'عشر': 10,
    'عشرا': 10,
    'عشرة': 10,

    // 11-19
    'حدعشر': 11,
    'حداشر': 11,
    'احدعشر': 11,
    'احد عشر': 11,
    'احدي عشر': 11,
    'إحدى عشر': 11,
    'احدى عشر': 11,
    'اتناشر': 12,
    'اثناشر': 12,
    'اتنين عشر': 12,
    'اثني عشر': 12,
    'اثنا عشر': 12,
    'تلاتاشر': 13,
    'ثلاثه عشر': 13,
    'تلت عشر': 13,
    'ثلاثة عشر': 13,
    'اربعتاشر': 14,
    'اربعطاشر': 14,
    'اربعه عشر': 14,
    'اربع عشر': 14,
    'أربعة عشر': 14,
    'خمستاشر': 15,
    'خمسطاشر': 15,
    'خمسه عشر': 15,
    'خمس عشر': 15,
    'خمسة عشر': 15,
    'ستاشر': 16,
    'سطاشر': 16,
    'سته عشر': 16,
    'ست عشر': 16,
    'ستة عشر': 16,
    'سبعتاشر': 17,
    'سبعطاشر': 17,
    'سبعه عشر': 17,
    'سبع عشر': 17,
    'سبعة عشر': 17,
    'تمنتاشر': 18,
    'تمانتاشر': 18,
    'تمانيه عشر': 18,
    'ثمانيه عشر': 18,
    'ثمانية عشر': 18,
    'تسعتاشر': 19,
    'تسعطاشر': 19,
    'تسعه عشر': 19,
    'تسع عشر': 19,
    'تسعة عشر': 19,

    // عشرات
    'عشرين': 20,
    'عشرون': 20,
    'تلاتين': 30,
    'ثلاثين': 30,
    'ثلاثون': 30,
    'اربعين': 40,
    'اربعون': 40,
    'أربعون': 40,
    'خمسين': 50,
    'خمسون': 50,
    'ستين': 60,
    'ستون': 60,
    'سبعين': 70,
    'سبعون': 70,
    'تمانين': 80,
    'ثمانين': 80,
    'تسعين': 90,
    'تسعون': 90,
    'ميه': 100,
    'مايه': 100,
    'مئه': 100,
    'مايا': 100,
    'مئة': 100,
    'مية': 100,

    // كسور
    'ونص': 0.5,
    'نص': 0.5,
    'نصف': 0.5,
    'ونصف': 0.5,
    'وربع': 0.25,
    'ربع': 0.25,
    'وتلت': 0.333,
    'تلت': 0.333,
    'وثلاثه ارباع': 0.75,
  };

  /// خريطة الأرقام العربية الهندية إلى اللاتينية
  static const Map<String, String> _arabicDigitsMap = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  static String _normalize(String text) {
    var t = text.trim().toLowerCase();
    // تحويل الأرقام العربية الهندية
    _arabicDigitsMap.forEach((ar, la) => t = t.replaceAll(ar, la));
    // إزالة التشكيل
    t = t.replaceAll(RegExp(r'[\u064B-\u0652\u0670\u0640]'), '');
    // تطبيع الأحرف
    t = t.replaceAll(RegExp(r'[إأآا]'), 'ا');
    t = t.replaceAll('ى', 'ي');
    t = t.replaceAll('ة', 'ه');
    t = t.replaceAll('ؤ', 'و');
    t = t.replaceAll('ئ', 'ي');
    // Preserve decimal comma between digits before replacing punctuation.
    t = t.replaceAllMapped(
      RegExp(r'(\d)[,\u060C](\d)'),
      (m) => '${m.group(1)}.${m.group(2)}',
    );
    // إزالة علامات الترقيم (مع الحفاظ على النقطة في الأرقام مثل 8.5)
    t = t.replaceAll(RegExp(r'[,،؛؟!:؟"\(\)\[\]{}\-_/\\]'), ' ');
    // تقليص المسافات
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static NLPResult parse(String text) {
    if (text.trim().isEmpty) {
      return NLPResult(
        numbers: const [],
        commands: const {},
        originalText: text,
      );
    }

    final normalized = _normalize(text);
    final numbers = <double>[];
    final commands = <String>{};

    // Extract digit and word forms in their spoken order. Field assignment is
    // positional, so collecting all digits before Arabic words can swap grades.
    _extractNumbersInOrder(normalized, numbers);

    // 3) استخراج الأوامر
    _extractCommands(normalized, commands);

    // إصلاح ثغرة: "صفر" وحدها = رقم 0 (ليس أمر clear)
    if (commands.contains('zero') && numbers.isEmpty) {
      numbers.add(0);
      // لا نضيفها كأمر clear
      commands.remove('clear');
    }

    // إصلاح ثغرة: إذا وُجدت أرقام لا تعالج كلمة "صفر" كأمر
    if (numbers.isNotEmpty && commands.contains('zero')) {
      commands.remove('zero');
    }

    return NLPResult(numbers: numbers, commands: commands, originalText: text);
  }

  static void _extractNumbersInOrder(String normalized, List<double> numbers) {
    final words = normalized
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .toList(growable: false);

    var i = 0;
    while (i < words.length) {
      final digit = double.tryParse(words[i].replaceAll(',', '.'));
      if (digit != null && digit.isFinite) {
        var value = digit;
        var consumed = 1;
        final fraction = _matchArabicNumberAt(words, i + consumed);
        if (fraction != null && _isFraction(fraction.value)) {
          value = double.parse((value + fraction.value).toStringAsFixed(3));
          consumed += fraction.consumed;
        }
        numbers.add(value);
        i += consumed;
        continue;
      }

      final match = _matchArabicNumberAt(words, i);
      if (match == null) {
        i++;
        continue;
      }

      if (_isFraction(match.value)) {
        if (numbers.isNotEmpty) {
          numbers[numbers.length - 1] = double.parse(
            (numbers.last + match.value).toStringAsFixed(3),
          );
        } else {
          numbers.add(match.value);
        }
        i += match.consumed;
        continue;
      }

      var value = match.value;
      var consumed = match.consumed;
      final fraction = _matchArabicNumberAt(words, i + consumed);
      if (fraction != null && _isFraction(fraction.value)) {
        value = double.parse((value + fraction.value).toStringAsFixed(3));
        consumed += fraction.consumed;
      }

      numbers.add(value);
      i += consumed;
    }
  }

  static _ArabicNumberMatch? _matchArabicNumberAt(
    List<String> words,
    int index,
  ) {
    if (index >= words.length) return null;

    final current = _stripLeadingAnd(words[index]);
    final currentValue = _arabicNumbers[current];
    final next = index + 1 < words.length
        ? _stripLeadingAnd(words[index + 1])
        : null;
    final nextValue = next == null ? null : _arabicNumbers[next];

    if (currentValue != null && nextValue != null) {
      if (_isUnit(currentValue) && (_isTens(nextValue) || nextValue == 10)) {
        return _ArabicNumberMatch(currentValue + nextValue, 2);
      }
      if (_isTens(currentValue) && _isUnit(nextValue)) {
        return _ArabicNumberMatch(currentValue + nextValue, 2);
      }
    }

    final entries = _arabicNumbers.entries.toList()
      ..sort((a, b) {
        final aTokens = _normalize(a.key).split(' ').length;
        final bTokens = _normalize(b.key).split(' ').length;
        final byTokens = bTokens.compareTo(aTokens);
        if (byTokens != 0) return byTokens;
        return b.key.length.compareTo(a.key.length);
      });

    for (final entry in entries) {
      final tokens = _normalize(
        entry.key,
      ).split(' ').where((token) => token.isNotEmpty).toList(growable: false);
      if (tokens.isEmpty || index + tokens.length > words.length) continue;
      var matched = true;
      for (var offset = 0; offset < tokens.length; offset++) {
        if (_stripLeadingAnd(words[index + offset]) != tokens[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) return _ArabicNumberMatch(entry.value, tokens.length);
    }

    return null;
  }

  static String _stripLeadingAnd(String word) {
    if (_arabicNumbers.containsKey(word)) return word;
    const waw = '\u0648';
    if (!word.startsWith(waw) || word.length <= 1) return word;
    final stripped = word.substring(1);
    return _arabicNumbers.containsKey(stripped) ? stripped : word;
  }

  static bool _isUnit(double value) => value >= 1 && value <= 9;

  static bool _isTens(double value) => value >= 20 && value % 10 == 0;

  static bool _isFraction(double value) =>
      value == 0.5 || value == 0.25 || value == 0.333 || value == 0.75;

  static void _extractCommands(String normalized, Set<String> commands) {
    _commandKeywords.forEach((cmd, keys) {
      for (final k in keys) {
        final nk = _normalize(k);
        if (nk.isEmpty) continue;
        // عبارات (بمسافات) -> contains
        if (nk.contains(' ')) {
          if (normalized.contains(nk)) {
            commands.add(cmd);
            break;
          }
        } else {
          // كلمة مفردة -> تطابق كامل مع حدود الكلمات
          final pattern = RegExp('(^|\\s)${RegExp.escape(nk)}(\\s|\$)');
          if (pattern.hasMatch(normalized)) {
            commands.add(cmd);
            break;
          }
        }
      }
    });
  }

  /// توزيع الأرقام على حقول الدرجات مع احترام الحدود القصوى
  /// الاستراتيجية: ملء الحقول الفارغة أولاً، ثم الكتابة فوق القديمة
  static Map<String, double> distributeGrades(
    List<double> numbers,
    List<GradeField> fields,
    Map<String, double> currentGrades,
  ) {
    final updated = Map<String, double>.from(currentGrades);
    if (numbers.isEmpty || fields.isEmpty) return updated;

    var idx = 0;

    // المرور الأول: ملء الحقول الفارغة
    for (final f in fields) {
      if (idx >= numbers.length) break;
      final current = updated[f.name];
      if (current == null || !current.isFinite) {
        final v = GradeField.clampGrade(numbers[idx], f);
        updated[f.name] = v;
        idx++;
      }
    }

    // المرور الثاني: كتابة فوق القديمة إذا تبقت أرقام
    if (idx < numbers.length) {
      for (final f in fields) {
        if (idx >= numbers.length) break;
        final v = GradeField.clampGrade(numbers[idx], f);
        updated[f.name] = v;
        idx++;
      }
    }

    return updated;
  }
}
