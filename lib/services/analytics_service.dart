import 'dart:io' show File;
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/student_model.dart';
import '../services/admin_service.dart';
import '../utils/error_handler.dart';

class ClassStats {
  final int totalStudents;
  final int completedStudents;
  final double completionPercentage;
  final double averageScore;
  final double successRate;
  final double highestScore;
  final double lowestScore;
  final double totalPossible;

  ClassStats({
    required this.totalStudents,
    required this.completedStudents,
    required this.completionPercentage,
    required this.averageScore,
    required this.successRate,
    required this.highestScore,
    required this.lowestScore,
    required this.totalPossible,
  });

  factory ClassStats.empty() => ClassStats(
        totalStudents: 0,
        completedStudents: 0,
        completionPercentage: 0,
        averageScore: 0,
        successRate: 0,
        highestScore: 0,
        lowestScore: 0,
        totalPossible: 0,
      );
}

/// Service that builds an official Egyptian-style "كشف رصد الدرجات" Excel
/// matching the standard hand-written form layout teachers use:
///
///   - Header (school / class / subject / teacher / date)
///   - "بيانات الطالب" left columns (الاسم، رقم الجلوس)
///   - "بنود التقييم" middle columns with the max grade printed in the
///     header row (e.g. "قراءة من ١٥")
///   - "النتيجة" right columns: المجموع، النسبة، التقدير
///   - Empty stat rows at the bottom + signature lines
class AnalyticsService {
  static ClassStats calculate(List<Student> students, List<GradeField> fields) {
    if (students.isEmpty || fields.isEmpty) return ClassStats.empty();

    final totalPossible = fields.fold<double>(0, (s, f) => s + f.max);
    final totalStudents = students.length;

    final completed = students.where((s) {
      for (final f in fields) {
        if (!s.grades.containsKey(f.name)) return false;
      }
      return true;
    }).length;

    final totals = students.map((s) => s.total).toList();
    final sum = totals.fold<double>(0, (a, b) => a + b);
    final avg = totalStudents > 0 ? sum / totalStudents : 0.0;

    final successful =
        students.where((s) => s.total >= totalPossible * 0.5).length;
    final successRate =
        totalStudents > 0 ? (successful / totalStudents) * 100 : 0.0;

    final highest =
        totals.isEmpty ? 0.0 : totals.reduce((a, b) => a > b ? a : b);
    final lowest =
        totals.isEmpty ? 0.0 : totals.reduce((a, b) => a < b ? a : b);

    return ClassStats(
      totalStudents: totalStudents,
      completedStudents: completed,
      completionPercentage: (completed / totalStudents) * 100,
      averageScore: avg,
      successRate: successRate,
      highestScore: highest,
      lowestScore: lowest,
      totalPossible: totalPossible,
    );
  }

  /// Compute the textual grade ("ممتاز / جيد جدا / جيد / مقبول / ضعيف")
  static String _grade(double total, double totalPossible) {
    if (totalPossible <= 0) return '—';
    final pct = (total / totalPossible) * 100;
    if (pct >= 90) return 'ممتاز';
    if (pct >= 80) return 'جيد جداً';
    if (pct >= 65) return 'جيد';
    if (pct >= 50) return 'مقبول';
    return 'ضعيف';
  }

  /// Build a professional Excel file matching the official Egyptian
  /// school grade-tracking sheet format.
  /// على منصة الويب: يُعيد false مع رسالة خطأ واضحة (dart:io غير متاح).
  static Future<bool> exportToExcel({
    required List<Student> students,
    required List<GradeField> fields,
    required String className,
    required String subject,
    String? teacherName,
    String? schoolName,
  }) async {
    // Web لا يدعم حفظ ملفات عبر dart:io — استخدم CSV بدلاً منه
    if (kIsWeb) {
      ErrorHandler.logError(
        'exportToExcel: غير مدعوم على الويب — يُحوَّل تلقائياً لـ CSV',
        null,
        'AnalyticsService.exportToExcel.webFallback',
      );
      return exportToCSV(
        students: students,
        fields: fields,
        className: className,
        subject: subject,
      );
    }
    try {
      final excel = Excel.createExcel();
      final defaultSheetName = excel.getDefaultSheet() ?? 'Sheet1';
      const sheetName = 'كشف الدرجات';
      excel.rename(defaultSheetName, sheetName);
      final sheet = excel.sheets[sheetName]!;

      // Right-to-left layout for Arabic
      sheet.isRTL = true;

      final totalPossible = fields.fold<double>(0, (s, f) => s + f.max);
      final fieldsCount = fields.length;
      // Columns layout:
      //   0  : م (sequence)
      //   1  : اسم الطالب
      //   2  : رقم الجلوس
      //   3..(3+fieldsCount-1) : grade fields
      //   3+fieldsCount     : المجموع
      //   3+fieldsCount+1   : النسبة %
      //   3+fieldsCount+2   : التقدير
      final totalCols = 3 + fieldsCount + 3;
      final lastColIndex = totalCols - 1;
      final totalCol = 3 + fieldsCount;
      final pctCol = 3 + fieldsCount + 1;
      final gradeCol = 3 + fieldsCount + 2;

      // ======================== Styles ========================
      Border thinB() => Border(borderStyle: BorderStyle.Thin);
      Border medB() => Border(borderStyle: BorderStyle.Medium);

      final titleStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        bold: true,
        fontSize: 18,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: medB(),
        rightBorder: medB(),
        topBorder: medB(),
        bottomBorder: medB(),
      );

      final subTitleStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#2E75B6'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        bold: true,
        fontSize: 12,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: thinB(),
        rightBorder: thinB(),
        topBorder: thinB(),
        bottomBorder: thinB(),
      );

      final infoLabelStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#D9E1F2'),
        fontColorHex: ExcelColor.fromHexString('#1F4E78'),
        bold: true,
        fontSize: 11,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinB(),
        rightBorder: thinB(),
        topBorder: thinB(),
        bottomBorder: thinB(),
      );

      final infoValueStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
        fontColorHex: ExcelColor.fromHexString('#000000'),
        bold: false,
        fontSize: 11,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinB(),
        rightBorder: thinB(),
        topBorder: thinB(),
        bottomBorder: thinB(),
      );

      // The classic dark-blue header used for the main "بنود التقييم" table.
      final headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#305496'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        bold: true,
        fontSize: 11,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: medB(),
        rightBorder: medB(),
        topBorder: medB(),
        bottomBorder: medB(),
      );

      // Group headers: "بيانات الطالب" / "بنود التقييم" / "النتيجة النهائية"
      final groupHeaderStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        bold: true,
        fontSize: 13,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: medB(),
        rightBorder: medB(),
        topBorder: medB(),
        bottomBorder: medB(),
      );

      final maxRowStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FFE699'),
        fontColorHex: ExcelColor.fromHexString('#7F6000'),
        bold: true,
        fontSize: 10,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinB(),
        rightBorder: thinB(),
        topBorder: thinB(),
        bottomBorder: thinB(),
      );

      CellStyle dataStyle({required bool zebra, bool name = false}) {
        return CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(
            zebra ? '#F2F2F2' : '#FFFFFF',
          ),
          fontColorHex: ExcelColor.fromHexString('#000000'),
          bold: name,
          fontSize: 11,
          fontFamily: getFontFamily(FontFamily.Arial),
          horizontalAlign: name ? HorizontalAlign.Right : HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
          leftBorder: thinB(),
          rightBorder: thinB(),
          topBorder: thinB(),
          bottomBorder: thinB(),
        );
      }

      CellStyle totalStyle({required bool zebra, required bool pass}) {
        return CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(
            zebra ? '#F2F2F2' : '#FFFFFF',
          ),
          fontColorHex:
              ExcelColor.fromHexString(pass ? '#0B5394' : '#9C0006'),
          bold: true,
          fontSize: 11,
          fontFamily: getFontFamily(FontFamily.Arial),
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
          leftBorder: medB(),
          rightBorder: medB(),
          topBorder: thinB(),
          bottomBorder: thinB(),
        );
      }

      CellStyle gradeBadgeStyle({
        required bool zebra,
        required String grade,
      }) {
        // Color-coded grade text
        String fg;
        switch (grade) {
          case 'ممتاز':
            fg = '#1B5E20';
            break;
          case 'جيد جداً':
            fg = '#2E7D32';
            break;
          case 'جيد':
            fg = '#0B5394';
            break;
          case 'مقبول':
            fg = '#7F6000';
            break;
          default:
            fg = '#9C0006';
        }
        return CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(
            zebra ? '#F2F2F2' : '#FFFFFF',
          ),
          fontColorHex: ExcelColor.fromHexString(fg),
          bold: true,
          fontSize: 11,
          fontFamily: getFontFamily(FontFamily.Arial),
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
          leftBorder: medB(),
          rightBorder: medB(),
          topBorder: thinB(),
          bottomBorder: thinB(),
        );
      }

      final statsLabelStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        bold: true,
        fontSize: 11,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinB(),
        rightBorder: thinB(),
        topBorder: thinB(),
        bottomBorder: thinB(),
      );

      final statsValueStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FFF2CC'),
        fontColorHex: ExcelColor.fromHexString('#7F6000'),
        bold: true,
        fontSize: 11,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinB(),
        rightBorder: thinB(),
        topBorder: thinB(),
        bottomBorder: thinB(),
      );

      final signatureLabelStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
        fontColorHex: ExcelColor.fromHexString('#000000'),
        bold: true,
        fontSize: 11,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        topBorder: medB(),
      );

      final signatureLineStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
        fontColorHex: ExcelColor.fromHexString('#666666'),
        bold: false,
        fontSize: 10,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        bottomBorder: thinB(),
      );

      // ======================== Header (school / subtitle) ========================
      var rowIdx = 0;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
        CellIndex.indexByColumnRow(columnIndex: lastColIndex, rowIndex: rowIdx),
      );
      var c = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
      );
      c.value = TextCellValue(schoolName ?? 'كشف رصد الدرجات الرسمي');
      c.cellStyle = titleStyle;
      sheet.setRowHeight(rowIdx, 32);
      rowIdx++;

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
        CellIndex.indexByColumnRow(columnIndex: lastColIndex, rowIndex: rowIdx),
      );
      c = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
      );
      c.value = TextCellValue(
          '${AdminService.appName} - ${AdminService.appNameAr}');
      c.cellStyle = subTitleStyle;
      sheet.setRowHeight(rowIdx, 22);
      rowIdx++;

      // ======================== Info row ========================
      final now = DateTime.now();
      final dateStr =
          '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
      final infoPairs = <List<String>>[
        ['الصف الدراسي', className],
        ['المادة', subject],
        ['المعلم', teacherName ?? '—'],
        ['تاريخ الرصد', dateStr],
      ];

      final pairWidth = (totalCols / infoPairs.length).floor();
      for (var i = 0; i < infoPairs.length; i++) {
        final startCol = i * pairWidth;
        final endCol = (i == infoPairs.length - 1)
            ? lastColIndex
            : startCol + pairWidth - 1;
        final labelEndCol = startCol + ((endCol - startCol) ~/ 2);

        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: rowIdx),
          CellIndex.indexByColumnRow(
              columnIndex: labelEndCol, rowIndex: rowIdx),
        );
        var lc = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: rowIdx),
        );
        lc.value = TextCellValue(infoPairs[i][0]);
        lc.cellStyle = infoLabelStyle;

        sheet.merge(
          CellIndex.indexByColumnRow(
              columnIndex: labelEndCol + 1, rowIndex: rowIdx),
          CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: rowIdx),
        );
        var vc = sheet.cell(
          CellIndex.indexByColumnRow(
              columnIndex: labelEndCol + 1, rowIndex: rowIdx),
        );
        vc.value = TextCellValue(infoPairs[i][1]);
        vc.cellStyle = infoValueStyle;
      }
      sheet.setRowHeight(rowIdx, 24);
      rowIdx++;

      // Spacer row
      rowIdx++;

      // ======================== Group headers row ========================
      // 3 group headers across the table:
      //   "بيانات الطالب" (cols 0..2)  -- 3 cols
      //   "بنود التقييم"   (cols 3..3+fieldsCount-1)
      //   "النتيجة النهائية" (cols totalCol..lastColIndex) -- 3 cols
      final groupRow = rowIdx;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: groupRow),
        CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: groupRow),
      );
      var g1 = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: groupRow),
      );
      g1.value = TextCellValue('بيانات الطالب');
      g1.cellStyle = groupHeaderStyle;

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: groupRow),
        CellIndex.indexByColumnRow(
            columnIndex: 3 + fieldsCount - 1, rowIndex: groupRow),
      );
      var g2 = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: groupRow),
      );
      g2.value = TextCellValue('بنود التقييم');
      g2.cellStyle = groupHeaderStyle;

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: totalCol, rowIndex: groupRow),
        CellIndex.indexByColumnRow(columnIndex: gradeCol, rowIndex: groupRow),
      );
      var g3 = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: totalCol, rowIndex: groupRow),
      );
      g3.value = TextCellValue('النتيجة النهائية');
      g3.cellStyle = groupHeaderStyle;
      sheet.setRowHeight(groupRow, 28);
      rowIdx++;

      // ======================== Header row (column titles) ========================
      final headerRow = rowIdx;
      // First row: column titles (with the max written under each field)
      final headers = <String>[
        'م',
        'اسم الطالب',
        'رقم الجلوس',
        ...fields.map((f) => '${f.label}\n(من ${_fmt(f.max)})'),
        'المجموع\n(من ${_fmt(totalPossible)})',
        'النسبة %',
        'التقدير',
      ];
      for (var col = 0; col < headers.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: headerRow),
        );
        cell.value = TextCellValue(headers[col]);
        cell.cellStyle = headerStyle;
      }
      sheet.setRowHeight(headerRow, 44);
      rowIdx++;

      // ======================== Max-points reminder row ========================
      // Row that emphasizes the maximum points for each item — common on
      // official forms (i.e. "الدرجة العظمى").
      final maxRow = rowIdx;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: maxRow),
        CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: maxRow),
      );
      var mc = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: maxRow),
      );
      mc.value = TextCellValue('الدرجة العظمى');
      mc.cellStyle = maxRowStyle;

      for (var i = 0; i < fields.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 3 + i, rowIndex: maxRow),
        );
        cell.value = DoubleCellValue(fields[i].max);
        cell.cellStyle = maxRowStyle;
      }
      var totMax = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: totalCol, rowIndex: maxRow),
      );
      totMax.value = DoubleCellValue(totalPossible);
      totMax.cellStyle = maxRowStyle;

      var totPct = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: pctCol, rowIndex: maxRow),
      );
      totPct.value = TextCellValue('100%');
      totPct.cellStyle = maxRowStyle;

      var totGrade = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: gradeCol, rowIndex: maxRow),
      );
      totGrade.value = TextCellValue('—');
      totGrade.cellStyle = maxRowStyle;
      sheet.setRowHeight(maxRow, 22);
      rowIdx++;

      // ======================== Student rows ========================
      for (var i = 0; i < students.length; i++) {
        final s = students[i];
        final zebra = i % 2 == 1;
        final r = rowIdx;
        final pct = totalPossible > 0 ? (s.total / totalPossible) * 100 : 0;
        final pass = pct >= 50;
        final grade = _grade(s.total, totalPossible);

        // Sequence
        var cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        );
        cell.value = IntCellValue(i + 1);
        cell.cellStyle = dataStyle(zebra: zebra);

        // Name
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r),
        );
        cell.value = TextCellValue(s.name);
        cell.cellStyle = dataStyle(zebra: zebra, name: true);

        // Number
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r),
        );
        cell.value = TextCellValue(s.studentNumber);
        cell.cellStyle = dataStyle(zebra: zebra);

        // Field grades (each one)
        for (var k = 0; k < fields.length; k++) {
          final f = fields[k];
          final col = 3 + k;
          final v = s.grades[f.name];
          cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r),
          );
          if (v == null) {
            cell.value = TextCellValue('');
          } else if (v == v.roundToDouble()) {
            cell.value = IntCellValue(v.toInt());
          } else {
            cell.value = DoubleCellValue(v);
          }
          cell.cellStyle = dataStyle(zebra: zebra);
        }

        // Total
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: totalCol, rowIndex: r),
        );
        if (s.total == s.total.roundToDouble()) {
          cell.value = IntCellValue(s.total.toInt());
        } else {
          cell.value = DoubleCellValue(s.total);
        }
        cell.cellStyle = totalStyle(zebra: zebra, pass: pass);

        // Percentage
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: pctCol, rowIndex: r),
        );
        cell.value = TextCellValue('${pct.toStringAsFixed(1)}%');
        cell.cellStyle = totalStyle(zebra: zebra, pass: pass);

        // Grade label
        cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: gradeCol, rowIndex: r),
        );
        cell.value = TextCellValue(grade);
        cell.cellStyle = gradeBadgeStyle(zebra: zebra, grade: grade);

        sheet.setRowHeight(r, 22);
        rowIdx++;
      }

      // Spacer row
      rowIdx++;

      // ======================== Statistics block ========================
      final stats = calculate(students, fields);
      final statsItems = <List<String>>[
        ['عدد الطلاب', '${stats.totalStudents}'],
        ['الطلاب المرصودون', '${stats.completedStudents}'],
        ['نسبة الإنجاز', '${stats.completionPercentage.toStringAsFixed(1)}%'],
        ['المتوسط العام', _fmt(stats.averageScore)],
        ['نسبة النجاح', '${stats.successRate.toStringAsFixed(1)}%'],
        ['أعلى درجة', _fmt(stats.highestScore)],
        ['أقل درجة', _fmt(stats.lowestScore)],
        ['الدرجة الكلية', _fmt(stats.totalPossible)],
      ];

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
        CellIndex.indexByColumnRow(columnIndex: lastColIndex, rowIndex: rowIdx),
      );
      var sTitle = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
      );
      sTitle.value = TextCellValue('📊 الإحصائيات العامة للفصل');
      sTitle.cellStyle = subTitleStyle;
      sheet.setRowHeight(rowIdx, 24);
      rowIdx++;

      const perRow = 4; // 4 pairs per row = 8 cells
      for (var i = 0; i < statsItems.length; i += perRow) {
        final r = rowIdx;
        final pairs = statsItems.skip(i).take(perRow).toList();
        final cellsPerPair = (totalCols / perRow).floor();

        for (var j = 0; j < pairs.length; j++) {
          final startCol = j * cellsPerPair;
          final endCol = (j == pairs.length - 1)
              ? lastColIndex
              : startCol + cellsPerPair - 1;
          final mid = startCol + ((endCol - startCol) ~/ 2);

          sheet.merge(
            CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: r),
            CellIndex.indexByColumnRow(columnIndex: mid, rowIndex: r),
          );
          var lc = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: r),
          );
          lc.value = TextCellValue(pairs[j][0]);
          lc.cellStyle = statsLabelStyle;

          sheet.merge(
            CellIndex.indexByColumnRow(columnIndex: mid + 1, rowIndex: r),
            CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: r),
          );
          var vc = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: mid + 1, rowIndex: r),
          );
          vc.value = TextCellValue(pairs[j][1]);
          vc.cellStyle = statsValueStyle;
        }
        sheet.setRowHeight(r, 22);
        rowIdx++;
      }

      // 2 spacer rows before signatures
      rowIdx += 2;

      // ======================== Signatures ========================
      final sigPairs = <String>[
        'توقيع المعلم',
        'توقيع وكيل المدرسة',
        'توقيع المدير',
      ];
      final sigWidth = (totalCols / sigPairs.length).floor();

      // Row of empty (signature lines)
      final lineRow = rowIdx;
      for (var i = 0; i < sigPairs.length; i++) {
        final startCol = i * sigWidth;
        final endCol = (i == sigPairs.length - 1)
            ? lastColIndex
            : startCol + sigWidth - 1;
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: lineRow),
          CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: lineRow),
        );
        var lc = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: lineRow),
        );
        lc.value = TextCellValue('................................');
        lc.cellStyle = signatureLineStyle;
      }
      sheet.setRowHeight(lineRow, 30);
      rowIdx++;

      // Row of labels
      final labelRow = rowIdx;
      for (var i = 0; i < sigPairs.length; i++) {
        final startCol = i * sigWidth;
        final endCol = (i == sigPairs.length - 1)
            ? lastColIndex
            : startCol + sigWidth - 1;
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: labelRow),
          CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: labelRow),
        );
        var sc = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: labelRow),
        );
        sc.value = TextCellValue(sigPairs[i]);
        sc.cellStyle = signatureLabelStyle;
      }
      sheet.setRowHeight(labelRow, 24);

      // ======================== Column widths ========================
      sheet.setColumnWidth(0, 6);  // #
      sheet.setColumnWidth(1, 28); // Name
      sheet.setColumnWidth(2, 14); // Number
      for (var i = 0; i < fields.length; i++) {
        sheet.setColumnWidth(3 + i, 14);
      }
      sheet.setColumnWidth(totalCol, 13);
      sheet.setColumnWidth(pctCol, 11);
      sheet.setColumnWidth(gradeCol, 12);

      // ======================== Save & share ========================
      final encoded = excel.encode();
      if (encoded == null) return false;

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'كشف_درجات_${_safeName(className)}_${_safeName(subject)}_'
          '${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(encoded);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'كشف درجات $className - $subject',
        text: 'تم تصدير الدرجات من تطبيق ${AdminService.appName}',
      );
      return true;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'AnalyticsService.exportToExcel');
      return false;
    }
  }

  /// Legacy CSV export (kept as fallback + Web-compatible).
  static Future<bool> exportToCSV({
    required List<Student> students,
    required List<GradeField> fields,
    required String className,
    required String subject,
  }) async {
    try {
      final headers = <String>[
        'م',
        'اسم الطالب',
        'رقم الجلوس',
        ...fields.map((f) => f.label),
        'المجموع',
        'النسبة %',
        'التقدير',
      ];
      final totalPossible = fields.fold<double>(0, (s, f) => s + f.max);

      final rows = <List<dynamic>>[headers];
      for (var i = 0; i < students.length; i++) {
        final s = students[i];
        final pct = totalPossible > 0
            ? '${((s.total / totalPossible) * 100).toStringAsFixed(1)}%'
            : '0%';
        final row = <dynamic>[
          i + 1,
          s.name,
          s.studentNumber,
          ...fields.map((f) {
            final v = s.grades[f.name];
            return v == null ? '' : _fmt(v);
          }),
          _fmt(s.total),
          pct,
          _grade(s.total, totalPossible),
        ];
        rows.add(row);
      }

      final stats = calculate(students, fields);
      rows.add(['']);
      rows.add(['الإحصائيات']);
      rows.add(['عدد الطلاب', stats.totalStudents]);
      rows.add(['المتوسط', _fmt(stats.averageScore)]);
      rows.add(['نسبة النجاح', '${stats.successRate.toStringAsFixed(1)}%']);
      rows.add(['أعلى درجة', _fmt(stats.highestScore)]);
      rows.add(['أقل درجة', _fmt(stats.lowestScore)]);

      final csv = const ListToCsvConverter().convert(rows);
      final content = '\uFEFF$csv';

      // Web: لا يوجد file system — نشارك النص مباشرةً عبر share_plus
      if (kIsWeb) {
        await Share.share(
          content,
          subject: 'درجات $className - $subject',
        );
        return true;
      }

      // Mobile/Desktop: حفظ ملف CSV ثم مشاركته
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'Grades_${_safeName(className)}_${_safeName(subject)}_'
          '${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString(content);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'درجات $className - $subject',
        text: 'تم تصدير الدرجات من تطبيق ${AdminService.appName}',
      );
      return true;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'AnalyticsService.exportToCSV');
      return false;
    }
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  static String _safeName(String input) {
    return input.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
  }
}
