// --------------------------------------------------------------------------
// المفتاح العام (Public Key) الخاص بالتحقق من توقيع أكواد الاشتراك.
//
// ⚠️ ملاحظة أمنية بالغة الأهمية:
// هذا الملف يحتوي فقط على المفتاح العام (RSA-2048، SubjectPublicKeyInfo /
// PEM)، وهو آمن تماماً لتضمينه داخل التطبيق الذي يصل للمستخدمين، لأن
// معرفة المفتاح العام لا تسمح لأي شخص بتوليد توقيعات جديدة صالحة — فقط
// بالتحقق من صحة التوقيعات الموجودة أصلاً.
//
// المفتاح الخاص (Private Key) المقابل لهذا المفتاح العام يبقى بشكل حصري
// عند المطوّر خارج هذا المستودع بالكامل (لا يُشحن أبداً داخل التطبيق)،
// ويُستخدم فقط بواسطة أداة توليد الأكواد الخارجية المستقلة الموجودة في:
//   /home/user/dev_tools/generate_license.py
//
// إذا احتجت لتدوير هذا المفتاح (Key Rotation) مستقبلاً: وّلد زوج مفاتيح
// RSA-2048 جديد، استبدل القيمة أدناه بالمفتاح العام الجديد، واحتفظ
// بالمفتاح الخاص الجديد في مكان آمن خارج أي مستودع Git.
// --------------------------------------------------------------------------

/// المفتاح العام بصيغة PEM (SubjectPublicKeyInfo, RSA-2048)
const String kLicensePublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAilBmCl8YcU3Ex0aCzVEf
piyTAlLn2FCwMqbFM5uBOcOhuwsB1n3j+35ysU4RJd26NvEUAgyguhqJj1T7KlIi
kY3NpptFNBiiJtSlwOYvLDevKQ2t2DLMxddoLwX4nvGFCAdUJaGgmW7IjqU4iseq
63VN8vBi+h+sj1pNKtoS0PJ3xuP+vXNZKJuhYZ0WjJ20PGq3aDZTy2aJY1IDLePK
qqxhsddyQ4jfUKw4YNrnB8QZT/DVCPZ/YWeiSFVjdPe+zVqZeDTIFdvgbPuteZVD
AzNJGIyuS+8Lcmq6qFdeE/GLFbg3V4C5Wyu7xqyQpovUbIPFsN/a8JWgukqsKied
PwIDAQAB
-----END PUBLIC KEY-----
''';
