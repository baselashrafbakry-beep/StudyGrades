import 'dart:io' show Directory, File;

import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_grader/models/student_model.dart';
import 'package:voice_grader/services/analytics_service.dart';

class _FakePathProviderChannel {
  static const _channel = MethodChannel('plugins.flutter.io/path_provider');

  _FakePathProviderChannel(this.directory);

  final Directory directory;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          switch (call.method) {
            case 'getTemporaryDirectory':
              return directory.path;
            default:
              return null;
          }
        });
  }
}

class _FakeShareChannel {
  static const _channel = MethodChannel('dev.fluttercommunity.plus/share');

  List<int>? lastSharedBytes;
  String? lastFilename;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          if (call.method != 'shareFiles') return null;
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final paths = List<String>.from(args['paths'] as List);
          final path = paths.single;
          lastFilename = path.split(RegExp(r'[\\/]')).last;
          lastSharedBytes = await File(path).readAsBytes();
          return 'dev.fluttercommunity.plus/share/success';
        });
  }
}

Map<String, String> _decodeCells(List<int> bytes) {
  final workbook = xl.Excel.decodeBytes(bytes);
  final sheet = workbook.sheets.values.first;
  final cells = <String, String>{};
  for (var row = 0; row < sheet.maxRows; row++) {
    for (var col = 0; col < sheet.maxColumns; col++) {
      final value = sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value;
      if (value != null) cells['$row,$col'] = value.toString();
    }
  }
  return cells;
}

bool _contains(Map<String, String> cells, String value) =>
    cells.values.any((cell) => cell.contains(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeShareChannel share;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('studygrades_excel_test_');
    _FakePathProviderChannel(tempDir).install();
    share = _FakeShareChannel()..install();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_FakePathProviderChannel._channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_FakeShareChannel._channel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'Excel export preserves report metadata when there are no fields',
    () async {
      final ok = await AnalyticsService.exportToExcel(
        students: [
          Student(id: 1, studentNumber: '101', name: 'Student One'),
          Student(id: 2, studentNumber: '102', name: 'Student Two'),
        ],
        fields: const [],
        className: 'Class Without Fields',
        subject: 'Science',
        teacherName: 'Teacher Zero',
      );

      expect(ok, isTrue);
      expect(share.lastFilename, endsWith('.xlsx'));
      final cells = _decodeCells(share.lastSharedBytes!);

      expect(_contains(cells, 'Class Without Fields'), isTrue);
      expect(_contains(cells, 'Science'), isTrue);
      expect(_contains(cells, 'Teacher Zero'), isTrue);
      expect(_contains(cells, 'Student One'), isTrue);
      expect(_contains(cells, 'Student Two'), isTrue);
    },
  );

  test(
    'Excel export includes a 100-student classroom without truncation',
    () async {
      final fields = [
        GradeField(name: 'oral', label: 'Oral', max: 10),
        GradeField(name: 'written', label: 'Written', max: 20),
        GradeField(name: 'activity', label: 'Activity', max: 5),
        GradeField(name: 'project', label: 'Project', max: 15),
        GradeField(name: 'final', label: 'Final', max: 50),
      ];
      final students = List.generate(
        100,
        (i) => Student(
          id: i + 1,
          studentNumber: '${2000 + i}',
          name: 'Student ${i + 1}',
          grades: {
            'oral': (i % 11).toDouble(),
            'written': (i % 21).toDouble(),
            'activity': (i % 6).toDouble(),
            'project': (i % 16).toDouble(),
            'final': (i % 51).toDouble(),
          },
        ),
      );

      final ok = await AnalyticsService.exportToExcel(
        students: students,
        fields: fields,
        className: 'Large Class',
        subject: 'Math',
        teacherName: 'Teacher Large',
      );

      expect(ok, isTrue);
      expect(share.lastSharedBytes!.length, greaterThan(5000));
      final cells = _decodeCells(share.lastSharedBytes!);

      for (final index in [0, 49, 99]) {
        expect(_contains(cells, students[index].name), isTrue);
        expect(_contains(cells, students[index].studentNumber), isTrue);
      }
      expect(_contains(cells, 'Large Class'), isTrue);
      expect(_contains(cells, 'Teacher Large'), isTrue);
    },
  );
}
