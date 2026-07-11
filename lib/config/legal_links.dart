class LegalLinks {
  const LegalLinks._();

  static final Uri privacy = Uri.parse(
    'https://studygrades-2026.netlify.app/privacy.html',
  );
  static final Uri terms = Uri.parse(
    'https://studygrades-2026.netlify.app/terms.html',
  );
  static final Uri support = Uri.parse(
    'https://studygrades-2026.netlify.app/support.html',
  );
  static final Uri supportEmail = Uri(
    scheme: 'mailto',
    path: 'baselashraf.bakry@gmail.com',
    queryParameters: {'subject': 'StudyGrades Support'},
  );
}
