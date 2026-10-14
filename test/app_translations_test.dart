import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_color.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/core/translations/en.dart';
import 'package:kuraku/app/core/translations/id.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_view.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  bool failWrite = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async {
    values[key] = value;
    if (failWrite) throw StateError('Storage unavailable');
  }
  @override
  void writeInMemory(String key, dynamic value) { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> onRefreshStorage() async {}
}

void main() {
  test('Indonesian covers every English key and preserves placeholders', () {
    expect(indonesianTranslations.keys.toSet(), englishTranslations.keys.toSet());
    final token = RegExp(r'@\{\w+\}');
    final emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u2600-\u27BF\u2328\uFE0E\uFE0F]', unicode: true);
    for (final entry in indonesianTranslations.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      expect(emoji.hasMatch(entry.value), isFalse, reason: entry.key);
      expect(emoji.hasMatch(englishTranslations[entry.key]!), isFalse, reason: entry.key);
      final expected = token.allMatches(entry.key).map((match) => match[0]!).toList()..sort();
      final actual = token.allMatches(entry.value).map((match) => match[0]!).toList()..sort();
      expect(actual, expected, reason: entry.key);
      if (entry.key.startsWith('/')) expect(entry.value, entry.key);
    }
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('id');
    Get.fallbackLocale = AppTranslations.fallbackLocale;
    addTearDown(() { Get.clearTranslations(); Get.locale = null; Get.fallbackLocale = null; });
    expect(AppTranslations.resolveLanguage('id'), 'id');
    expect('Settings'.tr, 'Setelan');
    expect('Daily relapse limit'.tr, 'Jatah coli harian');
    expect('(@{viewCount} Views)'.trNamed({'viewCount': '12'}), '(12 kali ditonton)');
    expect('Cant access file: @{videoPath}'.trNamed({'videoPath': '/Folder/@{count}/日本語.mp4'}), 'File nggak bisa diakses: /Folder/@{count}/日本語.mp4');
  });

  test('Every static translation reference has an English mapping', () {
    final reference = RegExp(r"(?<![\w'])'((?:\\.|[^'\\\r\n])*)'\.tr(?:Named)?\b");
    var count = 0;
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'))) {
      for (final match in reference.allMatches(file.readAsStringSync())) {
        final escaped = match[1]!;
        if (RegExp(r'(?<!\\)\$').hasMatch(escaped)) continue;
        final key = escaped.replaceAllMapped(RegExp(r'\\(.)'), (part) => switch (part[1]) {
          'n' => '\n', 'r' => '\r', 't' => '\t', _ => part[1]!,
        });
        expect(englishTranslations.containsKey(key), isTrue, reason: '${file.path}: $key');
        count++;
      }
    }
    expect(count, greaterThan(900));
  });

  test('English fallback and named parameters preserve values and token boundaries', () {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('unavailable');
    Get.fallbackLocale = AppTranslations.fallbackLocale;
    addTearDown(() { Get.clearTranslations(); Get.locale = null; Get.fallbackLocale = null; });
    expect(AppTranslations.resolveLanguage(null), 'en');
    expect(AppTranslations.resolveLanguage('invalid'), 'en');
    expect('Settings'.tr, 'Settings');
    expect('Unknown key'.tr, 'Unknown key');
    expect('Finished @{count} / @{count2} · @{path}'.trNamed({
      'count': '3', 'count2': '15', 'path': '/Folder/@{count2}/日本語',
    }), 'Finished 3 / 15 · /Folder/@{count2}/日本語');
    expect('@{missing}'.trNamed({}), '@{missing}');
    Get.appendTranslations({'test': {'Available: @{size}': '@{size} available'}});
    Get.locale = const Locale('test');
    expect('Available: @{size}'.trNamed({'size': '10 GB'}), '10 GB available');
    expect('Cancel'.tr, 'Cancel');
  });

  test('View count loads the English template and substitutes the actual value', () {
    Get.addTranslations(AppTranslations().keys);
    Get.fallbackLocale = AppTranslations.fallbackLocale;
    addTearDown(() { Get.clearTranslations(); Get.locale = null; Get.fallbackLocale = null; });
    for (final locale in [const Locale('en'), const Locale('unavailable')]) {
      Get.locale = locale;
      expect('(@{viewCount} Views)'.tr, '(@{viewCount} Views)');
      for (final count in [1, 12, 123456]) {
        expect('(@{viewCount} Views)'.trNamed({'viewCount': '$count'}), '($count Views)');
      }
    }
  });

  testWidgets('Language dropdown switches languages, persists and rejects unsupported choices', (tester) async {
    Get.testMode = true;
    final pref = _Preferences();
    final service = Get.put<AppSettingService>(AppSettingService()..pref = pref);
    addTearDown(() { service.onClose(); Get.reset(); Get.clearTranslations(); Get.locale = null; Get.fallbackLocale = null; });
    expect(AppPref.getAppLanguage(), 'en');
    pref.values['_kAppLanguage'] = 'invalid';
    expect(AppPref.getAppLanguage(), 'en');
    pref.values['_kAppLanguage'] = 12;
    expect(AppPref.getAppLanguage(), 'en');
    final controller = Get.put<PageSettingsController>(_Settings());
    await tester.pumpWidget(GetMaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates, supportedLocales: const [Locale('en'), Locale('id')],
      translations: AppTranslations(), locale: const Locale('en'), fallbackLocale: AppTranslations.fallbackLocale,
      home: Scaffold(body: SizedBox(width: 320, child: Builder(builder: (context) {
        AppColor.dependOn(context);
        return const PageSettingsView().buildLanguageSetting();
      }))),
    ));
    expect(find.text('Language'), findsOneWidget);
    expect(MaterialLocalizations.of(tester.element(find.byType(AppDropdown<String>))).okButtonLabel, 'OK');
    await tester.tap(find.byType(AppDropdown<String>));
    await tester.pumpAndSettle();
    final options = tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).items;
    expect(options.map((item) => item.value), ['en', 'id']);
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(pref.read<String>('_kAppLanguage'), 'en');
    expect(controller.appLanguage.value, 'en');
    expect(Get.locale, const Locale('en'));
    final recreated = _Settings();
    expect(recreated.appLanguage.value, 'en');
    recreated.onClose();
    await tester.tap(find.byType(AppDropdown<String>));
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await tester.tap(find.text('Bahasa Indonesia').last); });
    await tester.pumpAndSettle();
    expect(find.text('Bahasa'), findsOneWidget);
    expect(pref.read<String>('_kAppLanguage'), 'id');
    expect(controller.appLanguage.value, 'id');
    expect(Get.locale, const Locale('id'));
    expect(MaterialLocalizations.of(tester.element(find.byType(AppDropdown<String>))).cancelButtonLabel, 'Batal');
    final restored = _Settings();
    expect(restored.appLanguage.value, 'id');
    restored.onClose();
    await tester.tap(find.byType(AppDropdown<String>));
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await tester.tap(find.text('English').last); });
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    await expectLater(AppPref.setAppLanguage('unsupported'), throwsArgumentError);
    expect(pref.read<String>('_kAppLanguage'), 'en');
    pref.values['_kAppLanguage'] = 'invalid';
    pref.failWrite = true;
    await expectLater(AppPref.setAppLanguage('en'), throwsStateError);
    expect(pref.read<String>('_kAppLanguage'), 'invalid');
    expect(AppPref.getAppLanguage(), 'en');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
