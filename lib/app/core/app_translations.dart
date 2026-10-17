import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../translations/en.dart';
import '../translations/id.dart';

class AppTranslations extends Translations {
  static const fallbackLocale = Locale('en');
  static const languages = {'en': 'English', 'id': 'Bahasa Indonesia'};

  static String resolveLanguage(String? code) => languages.containsKey(code) ? code! : 'en';

  @override
  Map<String, Map<String, String>> get keys => {'en': englishTranslations, 'id': indonesianTranslations};
}

extension NamedTranslation on String {
  String trNamed(Map<String, String> params) => tr.replaceAllMapped(
    RegExp(r'@\{(\w+)\}'), (match) => params[match[1]] ?? match[0]!,
  );
}
