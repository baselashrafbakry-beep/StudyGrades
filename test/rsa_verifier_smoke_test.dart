import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/security/rsa_license_verifier.dart';

void main() {
  test('يتحقق من صحة الكود المُوقَّع فعلياً من أداة Python الخارجية', () {
    const deviceId = 'A1B2C3D4E5F60708';
    const planCode = 'SCHOOL';
    const days = 9999;
    const generatedCode =
        'SGV2-SCHOOL-9999-IEYUEMSDGNCDIRJVIY3DANZQHA-MOHIII2PTPZRWBFXHIENEXUMGLUOXM7W3WRKNWQZO6WI2DF3TEGR4OB7GSBCSO3UYOJQB347AZOLNTXSZPATKDWG7MLXRLJEUD3UDKJBGVFNFCO6TX36TVEGKOI6V5JW67G3MTSORCMMPANWUCYMCROYMWNDGZVGTYR6LLQVFUB56V42TTCQX4JILAHHXNFHX72ACKPFNFNHCVZY7LDRHC6PEKPU7PQ4CZDQ43BRUCQKR7F362CFVQCZT3A47RZLHOUP3RME663EXGKSVZZVSBLMKAZW4YZE7O4UJE6DZHAAIQCM5TU23NJ2F6S3T67E65NR7OF5RE6EEAID7YPGJ5ESV5KJUAHWYDMTF43LSEOFUT73MZGQ75RL27IA2G72RFVUJ5YFH5ASOB3T6IEUV2OKVM';

    final parts = generatedCode.split('-');
    final sigB32 = parts.sublist(4).join('-');
    final sigBytes = base32Decode(sigB32);

    final result = verifyLicenseSignature(
      deviceId: deviceId,
      planCode: planCode,
      days: days,
      signatureBytes: sigBytes,
    );

    expect(result, true,
        reason: 'يجب أن يتحقق Dart من صحة توقيع تم توليده فعلياً بواسطة '
            'أداة Python الخارجية باستخدام المفتاح الخاص المطابق');
  });

  test('يرفض كوداً موقَّعاً لجهاز مختلف (حماية ربط الجهاز)', () {
    const differentDeviceId = 'FFFFFFFFFFFFFFFF'; // جهاز مختلف
    const planCode = 'SCHOOL';
    const days = 9999;
    const generatedCode =
        'SGV2-SCHOOL-9999-IEYUEMSDGNCDIRJVIY3DANZQHA-MOHIII2PTPZRWBFXHIENEXUMGLUOXM7W3WRKNWQZO6WI2DF3TEGR4OB7GSBCSO3UYOJQB347AZOLNTXSZPATKDWG7MLXRLJEUD3UDKJBGVFNFCO6TX36TVEGKOI6V5JW67G3MTSORCMMPANWUCYMCROYMWNDGZVGTYR6LLQVFUB56V42TTCQX4JILAHHXNFHX72ACKPFNFNHCVZY7LDRHC6PEKPU7PQ4CZDQ43BRUCQKR7F362CFVQCZT3A47RZLHOUP3RME663EXGKSVZZVSBLMKAZW4YZE7O4UJE6DZHAAIQCM5TU23NJ2F6S3T67E65NR7OF5RE6EEAID7YPGJ5ESV5KJUAHWYDMTF43LSEOFUT73MZGQ75RL27IA2G72RFVUJ5YFH5ASOB3T6IEUV2OKVM';

    final parts = generatedCode.split('-');
    final sigB32 = parts.sublist(4).join('-');
    final sigBytes = base32Decode(sigB32);

    final result = verifyLicenseSignature(
      deviceId: differentDeviceId, // نحاول التحقق بمعرّف جهاز مختلف
      planCode: planCode,
      days: days,
      signatureBytes: sigBytes,
    );

    expect(result, false,
        reason: 'التوقيع تم إصداره لجهاز A1B2C3D4E5F60708 فقط، ويجب أن '
            'يُرفَض عند محاولة استخدامه مع معرّف جهاز مختلف');
  });

  test('يرفض كوداً تم التلاعب بخطته (تغيير BASIC إلى SCHOOL)', () {
    const deviceId = 'A1B2C3D4E5F60708';
    const days = 9999;
    const generatedCode =
        'SGV2-SCHOOL-9999-IEYUEMSDGNCDIRJVIY3DANZQHA-MOHIII2PTPZRWBFXHIENEXUMGLUOXM7W3WRKNWQZO6WI2DF3TEGR4OB7GSBCSO3UYOJQB347AZOLNTXSZPATKDWG7MLXRLJEUD3UDKJBGVFNFCO6TX36TVEGKOI6V5JW67G3MTSORCMMPANWUCYMCROYMWNDGZVGTYR6LLQVFUB56V42TTCQX4JILAHHXNFHX72ACKPFNFNHCVZY7LDRHC6PEKPU7PQ4CZDQ43BRUCQKR7F362CFVQCZT3A47RZLHOUP3RME663EXGKSVZZVSBLMKAZW4YZE7O4UJE6DZHAAIQCM5TU23NJ2F6S3T67E65NR7OF5RE6EEAID7YPGJ5ESV5KJUAHWYDMTF43LSEOFUT73MZGQ75RL27IA2G72RFVUJ5YFH5ASOB3T6IEUV2OKVM';

    final parts = generatedCode.split('-');
    final sigB32 = parts.sublist(4).join('-');
    final sigBytes = base32Decode(sigB32);

    // محاولة تزوير الخطة إلى BASIC مع إبقاء نفس التوقيع الصادر لـ SCHOOL
    final result = verifyLicenseSignature(
      deviceId: deviceId,
      planCode: 'BASIC', // تلاعب: تغيير الخطة
      days: days,
      signatureBytes: sigBytes,
    );

    expect(result, false,
        reason: 'التوقيع صالح فقط لمحتوى (deviceId:SCHOOL:9999) الأصلي؛ أي '
            'تعديل على أي حقل (بما فيها الخطة) يجب أن يُبطل التوقيع فوراً');
  });

  test('يرفض توقيعاً عشوائياً/مزوَّراً بالكامل', () {
    final fakeSignature =
        Uint8List.fromList(List<int>.generate(256, (i) => i % 256));

    final result = verifyLicenseSignature(
      deviceId: 'A1B2C3D4E5F60708',
      planCode: 'SCHOOL',
      days: 9999,
      signatureBytes: fakeSignature,
    );

    expect(result, false,
        reason: 'توقيع عشوائي غير صادر عن المفتاح الخاص الحقيقي يجب أن '
            'يُرفَض دائماً');
  });
}
