import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_search_site.dart';
import 'package:kuraku/app/data/models/search_site.dart';
import 'package:kuraku/app/modules/home/page_settings/search_sites_dialog.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/utils/helper_opener.dart';

import 'sqlite_test_database.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteTestDatabase db;
  setUp(() async {
    Get.testMode = true;
    db = await SqliteTestDatabase.open();
    await DBService.onCreate(db, DBUpdate.version);
    Get.put<DBService>(DBService()..dbMain = db);
    Get.put<AppSettingService>(AppSettingService()..pref = _Preferences());
    await DBSearchSite.load();
  });
  tearDown(() async {
    await db.close();
    Get.reset();
    DBSearchSite.sites.assignAll(SearchSite.defaults);
  });

  test('seeds five defaults, persists edits and custom sites, rejects duplicates', () async {
    expect(DBSearchSite.sites.map((site) => site.name), ['NJAV', 'MISSAV', 'JAVMOST', 'SEXTB', 'JAVGURU']);
    expect(DBSearchSite.resolve('njav').urlFor('ABC-001'), 'https://njavtv.com/en/search/ABC-001');
    const custom = SearchSite('Custom', 'https://example.test/search?q={code}', 'https://example.test/watch/{code}');
    await DBSearchSite.save(custom);
    AppPref.setDefaultSearchEngine('Custom');
    expect(HelperOpener.downloadUrlForVideo('A/B ?&'), 'https://example.test/watch/A%2FB%20%3F%26');
    expect(custom.urlFor('A/B ?&'), 'https://example.test/search?q=A%2FB%20%3F%26');
    expect(HelperOpener.downloadUrlForVideo('ABC-001', sourceUrl: 'https://source.test/watch'), 'https://source.test/watch');
    await expectLater(DBSearchSite.save(const SearchSite('custom', 'https://x.test/{code}', 'https://x.test/{code}')), throwsException);
    await DBSearchSite.save(const SearchSite('NJAV', 'https://mirror.test/search/{code}', 'https://mirror.test/watch/{code}'), update: true);
    await DBSearchSite.load();
    expect(DBSearchSite.resolve('NJAV').searchUrl, 'https://mirror.test/search/{code}');
    await expectLater(DBSearchSite.remove(DBSearchSite.resolve('NJAV')), throwsStateError);
    await DBSearchSite.remove(custom);
    expect(AppPref.getDefaultSearchEngine(), 'NJAV');
    expect(await db.query('search_site'), hasLength(5));
  });

  test('resolves Unicode names exactly when SQLite stores both case variants', () async {
    await DBSearchSite.save(const SearchSite('Ä', 'https://one.test/{code}', 'https://one.test/{code}'));
    await DBSearchSite.save(const SearchSite('ä', 'https://two.test/{code}', 'https://two.test/{code}'));
    AppPref.setDefaultSearchEngine('ä');
    expect(AppPref.getDefaultSearchEngine(), 'ä');
    expect(HelperOpener.downloadUrlForVideo('ABC-001'), 'https://two.test/ABC-001');
    expect(HelperOpener.downloadUrlForVideo('ABC-001', searchEngine: 'Ä'), 'https://one.test/ABC-001');
    expect(DBSearchSite.resolve('njav').name, 'NJAV');
  });

  test('validates URL templates and names before writing', () async {
    for (final value in ['javascript:{code}', 'file:///tmp/{code}', 'https://user:pass@x.test/{code}', 'https://{code}.test/search',
      'https://x.test/search', 'https://x.test/#{code}', 'https://x.test/{code} space', 'https:///{code}']) {
      await expectLater(DBSearchSite.save(SearchSite('Bad', value, value)), throwsFormatException, reason: value);
    }
    await expectLater(DBSearchSite.save(const SearchSite('', 'https://x.test/{code}', 'https://x.test/{code}')), throwsFormatException);
    expect(await db.query('search_site'), hasLength(5));
  });

  testWidgets('compact editor validates, preserves optional URLs and confirms deletion', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: AppButton(
      onPressed: () => Get.dialog(const SearchSitesDialog()), child: const Text('Manage'),
    ))));
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Default'), findsOneWidget);
    expect(find.text('https://njavtv.com/en/search/{code}'), findsNothing);
    final semantics = tester.ensureSemantics();
    await tester.tap(find.text('Add site'));
    await tester.pumpAndSettle();
    try {
      final field = tester.getSemantics(find.descendant(of: find.byKey(const ValueKey('site-name')), matching: find.byType(EditableText))).getSemanticsData();
      expect(field.label, 'Name');
      expect(field.flagsCollection.isTextField, isTrue);
    } finally {
      semantics.dispose();
    }
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const ValueKey('site-download-url')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('site-name')), 'Custom');
    await tester.enterText(find.byKey(const ValueKey('site-search-url')), 'javascript:{code}');
    await tester.runAsync(() => tester.tap(find.text('Save')));
    await tester.pumpAndSettle();
    expect(find.text('Use an HTTP(S) URL with {code}.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('site-search-url')), 'https://example.test/?q={code}');
    await tester.runAsync(() => tester.testTextInput.receiveAction(TextInputAction.done));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 150)); });
    await tester.pumpAndSettle();
    expect(DBSearchSite.resolve('Custom').downloadUrl, 'https://example.test/?q={code}');
    await tester.tap(find.byKey(const ValueKey('search-site-Custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('site-name')), findsNothing);
    expect(find.byKey(const ValueKey('site-download-url')), findsNothing);
    await tester.tap(find.text('Download URL (optional)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('site-download-url')), 'https://example.test/watch/{code}');
    await tester.tap(find.text('Download URL (optional)'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Save')));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 150)); });
    await tester.pumpAndSettle();
    expect(DBSearchSite.resolve('Custom').downloadUrl, 'https://example.test/watch/{code}');
    await tester.tap(find.byKey(const ValueKey('search-site-Custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('site-download-url')), findsOneWidget);
    AppPref.setDefaultSearchEngine('Custom');
    await tester.tap(find.byTooltip('Delete site'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this site?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('site-download-url')));
    await tester.runAsync(() => tester.testTextInput.receiveAction(TextInputAction.done));
    await tester.pumpAndSettle();
    expect(find.text('Delete this site?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(DBSearchSite.resolve('Custom').name, 'Custom');
    await tester.tap(find.byTooltip('Delete site'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Delete')));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 150)); });
    await tester.pumpAndSettle();
    expect(find.text('Custom'), findsNothing);
    expect(AppPref.getDefaultSearchEngine(), 'NJAV');
    await tester.tap(find.byKey(const ValueKey('search-site-NJAV')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete site'), findsNothing);
    expect(find.byKey(const ValueKey('site-download-url')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('list and editor fit narrow windows, long names and both languages', (tester) async {
    const longName = 'My custom site with a very long name to check compact rows';
    await tester.runAsync(() => DBSearchSite.save(const SearchSite(longName, 'https://very-long-domain.example.test/?q={code}', 'https://very-long-domain.example.test/?q={code}')));
    const output = String.fromEnvironment('SEARCH_SITES_QA_PATH');
    const font = String.fromEnvironment('VISUAL_QA_FONT');
    if (font.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('VisualQA');
        loader.addFont(File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
        await (FontLoader('packages/${CupertinoIcons.iconFontPackage}/${CupertinoIcons.iconFont}')
          ..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'))).load();
      });
    }
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    Future<void> capture(String label) async {
      if (output.isEmpty) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output-$label.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    for (final language in ['en', 'id']) {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        for (final width in [360.0, 900.0]) {
          tester.view.physicalSize = Size(width, 650);
          Get.locale = Locale(language);
          await tester.pumpWidget(GetMaterialApp(
            translations: AppTranslations(), locale: Locale(language),
            theme: ThemeData(brightness: brightness, fontFamily: font.isEmpty ? null : 'VisualQA',
              cupertinoOverrideTheme: font.isEmpty ? null : const CupertinoThemeData(textTheme: CupertinoTextThemeData(actionTextStyle: TextStyle(fontFamily: 'VisualQA')))),
            builder: (_, child) => RepaintBoundary(key: boundary, child: child!),
            home: Scaffold(body: AppButton(onPressed: () => Get.dialog(const SearchSitesDialog()), child: const Text('Manage'))),
          ));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Manage'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'list $language $width');
          final edits = find.byTooltip('Edit'.tr);
          for (var index = 1; index < edits.evaluate().length; index++) {
            expect(tester.getRect(edits.at(index)).right, closeTo(tester.getRect(edits.first).right, 1));
          }
          if (width == 900 && language == 'en') await capture('list-${brightness.name}');
          await tester.tap(find.byKey(const ValueKey('search-site-NJAV')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'editor $language $width');
          if (width == 900 && language == 'en') await capture('edit-${brightness.name}');
          await tester.tap(find.text('Cancel'.tr));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add site'.tr));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'add $language $width');
          if (width == 900 && language == 'en') await capture('add-${brightness.name}');
          await tester.tap(find.text('Cancel'.tr));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Close'.tr));
          await tester.pumpAndSettle();
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    Get.clearTranslations();
  });
}
