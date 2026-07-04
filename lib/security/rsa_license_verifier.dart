import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/export.dart' show RSAEngine, PSSSigner;
import 'package:pointycastle/api.dart'
    show ParametersWithSaltConfiguration, PublicKeyParameter;
import 'package:pointycastle/random/fortuna_random.dart';

import 'license_public_key.dart';

/// --------------------------------------------------------------------------
/// نظام التحقق من تراخيص الاشتراك — توقيع رقمي غير متماثل (RSA-2048 / PSS)
///
/// ⚠️ لماذا التحويل من HMAC/SHA-256 المتماثل إلى RSA غير المتماثل؟
/// النظام القديم كان يعتمد على "salt" ثابت مُخزَّن كنص داخل الكود المصدري،
/// وبالتالي داخل الـ APK/الويب المُصرَّف نفسه. وبما أن هذا الـ salt يمكن
/// استخراجه بسهولة عبر أوامر مثل `strings` على الملف الثنائي المُصرَّف،
/// فإن أي مستخدم يستطيع إعادة حساب نفس دالة الـ hash محلياً وتوليد أكواد
/// اشتراك مزوَّرة صالحة (بما فيها خطة "مدرسة" غير المنتهية) — تم إثبات هذه
/// الثغرة فعلياً عبر اختبار حي في هذا المستودع.
///
/// الحل الجذري: التوقيع الرقمي غير المتماثل. المفتاح الخاص (الذي يُستخدم
/// للتوقيع/توليد الأكواد) لا يُشحن أبداً داخل التطبيق — يبقى حصرياً لدى
/// المطوّر ويُستخدم فقط عبر أداة خارجية منفصلة تعمل على جهاز المطوّر
/// (انظر: dev_tools/generate_license.py). التطبيق نفسه يحتوي فقط على
/// المفتاح العام (Public Key)، وهذا آمن تماماً لأن معرفة المفتاح العام
/// لا تُمكِّن أي أحد من توليد توقيع صالح جديد — فقط من التحقق من توقيع
/// موجود مسبقاً. حتى لو استخرج المهاجم المفتاح العام بالكامل من الـ APK،
/// فلن يتمكن من تزوير أي كود اشتراك جديد.
/// --------------------------------------------------------------------------

/// طول الـ salt المستخدم في مخطط RSA-PSS (يجب أن يطابق تماماً القيمة
/// المستخدمة في أداة التوقيع الخارجية dev_tools/generate_license.py)
const int kPssSaltLengthBytes = 32;

/// البادئة المستخدمة في نص الرسالة الموقَّعة (فصل السياق/النطاق لمنع
/// إعادة استخدام التوقيع في سياق مختلف — Domain Separation)
const String kLicenseSignatureDomainPrefix = 'SGV-LICENSE-V2';

/// أبجدية Base32 القياسية (RFC 4648) — تتكون بالكامل من أحرف كبيرة
/// وأرقام، وبالتالي "آمنة" تجاه أي منطق `.toUpperCase()` مطبَّق مسبقاً
/// في واجهة المستخدم (حقل إدخال الكود، زر اللصق...)، دون الحاجة لتعديل
/// تلك الواجهات.
const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// ترميز مصفوفة بايتات إلى نص Base32 (بدون padding)
String base32Encode(Uint8List data) {
  final buffer = StringBuffer();
  int bits = 0;
  int value = 0;
  for (final byte in data) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      buffer.write(_base32Alphabet[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) {
    buffer.write(_base32Alphabet[(value << (5 - bits)) & 31]);
  }
  return buffer.toString();
}

/// فك ترميز نص Base32 (يتجاهل أي محارف غير صالحة مثل الفواصل '-')
Uint8List base32Decode(String input) {
  final clean = input.toUpperCase();
  final bytes = <int>[];
  int bits = 0;
  int value = 0;
  for (final char in clean.split('')) {
    final idx = _base32Alphabet.indexOf(char);
    if (idx == -1) continue; // تجاهل '-' أو أي محارف فاصلة أخرى
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bytes.add((value >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  return Uint8List.fromList(bytes);
}

/// يحوّل نص PEM لمفتاح عام (SubjectPublicKeyInfo, RSA) إلى كائن RSAPublicKey
/// يمكن استخدامه مباشرة مع pointycastle للتحقق من التواقيع.
RSAPublicKey parseRsaPublicKeyFromPem(String pem) {
  final derBytes = ASN1Utils.getBytesFromPEMString(pem);
  final asn1Parser = ASN1Parser(derBytes);
  final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

  final bitString = topLevelSeq.elements!.elementAt(1) as ASN1BitString;
  final publicKeyDer = Uint8List.fromList(bitString.stringValues!);

  final pubKeyParser = ASN1Parser(publicKeyDer);
  final pubKeySeq = pubKeyParser.nextObject() as ASN1Sequence;

  final modulus = (pubKeySeq.elements!.elementAt(0) as ASN1Integer).integer!;
  final exponent = (pubKeySeq.elements!.elementAt(1) as ASN1Integer).integer!;

  return RSAPublicKey(modulus, exponent);
}

/// المفتاح العام الفعلي المُحمَّل مرة واحدة من الثابت المُضمَّن في التطبيق
final RSAPublicKey _productionPublicKey =
    parseRsaPublicKeyFromPem(kLicensePublicKeyPem);

/// يبني نص الرسالة القياسي الذي يتم توقيعه/التحقق منه.
/// **يجب** أن يطابق تماماً المنطق المستخدم في أداة التوقيع الخارجية.
Uint8List buildLicenseMessageBytes({
  required String deviceId,
  required String planCode,
  required int days,
}) {
  final normalizedDeviceId = deviceId.trim().toUpperCase();
  final normalizedPlan = planCode.trim().toUpperCase();
  final message =
      '$kLicenseSignatureDomainPrefix:$normalizedDeviceId:$normalizedPlan:$days';
  return Uint8List.fromList(utf8.encode(message));
}

/// يتحقق من صحة توقيع كود الاشتراك مقابل مفتاح عام مُحدَّد (يُستخدم
/// أساساً في الاختبارات لحقن مفتاح اختباري مؤقت؛ الاستخدام الفعلي في
/// التطبيق يمر عبر [verifyLicenseSignature] الذي يستخدم المفتاح الإنتاجي).
bool verifyLicenseSignatureWithKey({
  required String deviceId,
  required String planCode,
  required int days,
  required Uint8List signatureBytes,
  required RSAPublicKey publicKey,
}) {
  try {
    final message = buildLicenseMessageBytes(
        deviceId: deviceId, planCode: planCode, days: days);

    final signer = PSSSigner(RSAEngine(), SHA256Digest(), SHA256Digest());
    final params = ParametersWithSaltConfiguration(
      PublicKeyParameter<RSAPublicKey>(publicKey),
      FortunaRandom(), // غير مُستخدَم فعلياً في مسار التحقق (verify)
      kPssSaltLengthBytes,
    );
    signer.init(false, params);

    return signer.verifySignature(message, PSSSignature(signatureBytes));
  } catch (_) {
    // أي خطأ في الـ ASN1/التوقيع/الترميز يعني ببساطة أن الكود غير صالح
    return false;
  }
}

/// نقطة الدخول الفعلية المستخدمة داخل التطبيق — تتحقق من التوقيع مقابل
/// المفتاح العام الإنتاجي المُضمَّن (kLicensePublicKeyPem).
bool verifyLicenseSignature({
  required String deviceId,
  required String planCode,
  required int days,
  required Uint8List signatureBytes,
}) {
  return verifyLicenseSignatureWithKey(
    deviceId: deviceId,
    planCode: planCode,
    days: days,
    signatureBytes: signatureBytes,
    publicKey: _productionPublicKey,
  );
}
