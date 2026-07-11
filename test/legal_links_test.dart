import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/config/legal_links.dart';

void main() {
  test('public legal links use the production HTTPS origin', () {
    for (final uri in [
      LegalLinks.privacy,
      LegalLinks.terms,
      LegalLinks.support,
    ]) {
      expect(uri.scheme, 'https');
      expect(uri.host, 'studygrades-2026.netlify.app');
    }
  });

  test('support email is a valid mail link', () {
    expect(LegalLinks.supportEmail.scheme, 'mailto');
    expect(LegalLinks.supportEmail.path, 'baselashraf.bakry@gmail.com');
  });
}
