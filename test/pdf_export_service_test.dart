import 'dart:io' show Directory, File;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_grader/models/student_model.dart';
import 'package:voice_grader/services/pdf_export_service.dart';

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

bool _looksLikePdf(List<int> bytes) {
  if (bytes.length < 5) return false;
  return String.fromCharCodes(bytes.take(5)) == '%PDF-';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeShareChannel share;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('studygrades_pdf_test_');
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

  test('exports a valid PDF for a normal classroom', () async {
    final ok = await PdfExportService.exportToPdf(
      students: [
        Student(
          id: 1,
          studentNumber: '101',
          name: 'Student One',
          grades: {'oral': 8, 'written': 9},
        ),
        Student(
          id: 2,
          studentNumber: '102',
          name: 'Student Two',
          grades: {'oral': 10, 'written': 7},
        ),
      ],
      fields: [
        GradeField(name: 'oral', label: 'Oral', max: 10),
        GradeField(name: 'written', label: 'Written', max: 10),
      ],
      className: 'Class 1',
      subject: 'Math',
      teacherName: 'Teacher',
    );

    expect(ok, isTrue);
    expect(share.lastSharedBytes, isNotNull);
    expect(_looksLikePdf(share.lastSharedBytes!), isTrue);
    expect(share.lastSharedBytes!.length, greaterThan(1000));
    expect(share.lastFilename, contains('.pdf'));
  });

  test('exports without grade fields or students', () async {
    final ok = await PdfExportService.exportToPdf(
      students: const [],
      fields: const [],
      className: 'Empty Class',
      subject: 'Science',
    );

    expect(ok, isTrue);
    expect(_looksLikePdf(share.lastSharedBytes!), isTrue);
  });

  test('exports a large classroom without truncation', () async {
    final students = List.generate(
      100,
      (i) => Student(
        id: i + 1,
        studentNumber: '${1000 + i}',
        name: 'Student ${i + 1}',
        grades: {
          'oral': (i % 11).toDouble(),
          'written': ((i + 3) % 11).toDouble(),
        },
      ),
    );

    final ok = await PdfExportService.exportToPdf(
      students: students,
      fields: [
        GradeField(name: 'oral', label: 'Oral', max: 10),
        GradeField(name: 'written', label: 'Written', max: 10),
      ],
      className: 'Large Class',
      subject: 'Arabic',
    );

    expect(ok, isTrue);
    expect(_looksLikePdf(share.lastSharedBytes!), isTrue);
    expect(share.lastSharedBytes!.length, greaterThan(5000));
  });
}
