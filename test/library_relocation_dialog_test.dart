import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_library.dart';
import 'package:kuraku/app/data/database/library_relocation.dart';
import 'package:kuraku/app/data/models/library_entity.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_library_relocation.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'sqlite_test_database.dart';

class _Picker with MockPlatformInterfaceMixin implements FilePickerPlatform {
  String? path;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getDirectoryPath) return Future<String?>.value(path);
    return super.noSuchMethod(invocation);
  }
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteTestDatabase db;
  late Directory folder, source, target;
  late Library library;
  late _Picker picker;
  late FilePickerPlatform previousPicker;

  setUp(() async {
    db = await SqliteTestDatabase.open();
    await DBService.onCreate(db, DBUpdate.version);
    Get.put<DBService>(_Service()..dbMain = db);
    folder = await Directory.systemTemp.createTemp('kuraku-relocation-dialog-');
    source = Directory('${folder.path}/original root')..createSync();
    target = Directory('${folder.path}/new 日本語 root')..createSync();
    final file = File('${target.path}/a movie.mp4');
    final handle = file.openSync(mode: FileMode.write);
    handle.truncateSync(12 * 1024 * 1024);
    handle.closeSync();
    library = Library(rootFolder: source.path, alias: 'Movies');
    await DBLibrary.add(library);
    await db.execute('INSERT INTO videos(id,root_path,video_path,title,filesize,is_favorite,view_count) VALUES (?,?,?,?,?,1,7)',
      ['keep', source.path, '${source.path}/a movie.mp4', 'Keep title', file.lengthSync()]);
    previousPicker = FilePickerPlatform.instance;
    picker = _Picker()..path = target.path;
    FilePickerPlatform.instance = picker;
  });
  tearDown(() async {
    FilePickerPlatform.instance = previousPicker;
    Get.reset();
    await db.close();
    folder.deleteSync(recursive: true);
  });

  Finder button(String label) => find.byWidgetPredicate((widget) => widget is AppButton && widget.label == label);

  Future<void> open(WidgetTester tester, {bool narrow = false, bool dark = false,
    Future<void> Function(LibraryRelocation)? onApply}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(narrow ? 320 : 800, 650);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(GetMaterialApp(
      theme: AppStyle.theme(dark ? Brightness.dark : Brightness.light),
      translations: AppTranslations(), locale: const Locale('en'),
      home: const Scaffold(body: Text('Home')),
    ));
    unawaited(showDialog<void>(context: Get.context!, barrierDismissible: false,
      builder: (_) => LibraryRelocationDialog(library: library, onApply: onApply ?? (preview) => preview.apply())));
    await tester.pumpAndSettle();
  }

  Future<void> selectFolder(WidgetTester tester) async {
    final dynamic action = tester.widget<AppIconButton>(find.byWidgetPredicate((widget) =>
      widget is AppIconButton && widget.tooltip == 'Select folder')).onPressed;
    await tester.runAsync(() async { await action(); });
    await tester.pumpAndSettle();
  }

  testWidgets('root labels stay on one compact line and paths align with the input in both themes', (tester) async {
    for (final dark in [false, true]) {
      await open(tester, narrow: true, dark: dark);
      for (final label in ['Current root', 'New root']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: find.text(label), matching: find.byType(RichText)));
        expect(paragraph.size.height, lessThan(20));
      }
      expect(tester.getTopLeft(find.text(source.path)).dx,
        closeTo(tester.getTopLeft(find.byType(AppTextField)).dx, 1));
      expect(tester.takeException(), isNull);
      await tester.tap(button('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('preview shows path-only matches in both themes and Cancel leaves the root and records unchanged', (tester) async {
    for (final dark in [false, true]) {
      await open(tester, narrow: true, dark: dark);
      expect(tester.widget<AppButton>(button('Apply')).onPressed, isNull);
      await selectFolder(tester);
      expect(find.text('Path match'), findsOneWidget);
      expect(find.textContaining('0 matched • 1 path matches • 0 missing • 0 conflicts'), findsOneWidget);
      expect(find.textContaining('${source.path}/a movie.mp4\n→ ${target.path}/a movie.mp4'), findsOneWidget);
      expect(tester.widget<AppButton>(button('Apply')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.tap(button('Cancel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect((await DBLibrary.getAll()).single.rootFolder, source.path);
        expect((await db.query('videos')).single['video_path'], '${source.path}/a movie.mp4');
      });
    }
  });

  testWidgets('Apply commits the preview once and closes the dialog', (tester) async {
    var calls = 0;
    await open(tester, onApply: (preview) async { calls++; await preview.apply(); });
    await selectFolder(tester);
    await tester.runAsync(() async {
      final dynamic apply = tester.widget<AppButton>(button('Apply')).onPressed;
      await apply();
      expect((await DBLibrary.getAll()).single.rootFolder, target.path);
      final video = (await db.query('videos')).single;
      expect([video['id'], video['is_favorite'], video['view_count']], ['keep', 1, 7]);
    });
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(LibraryRelocationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing or unavailable roots disable Apply, and stale preview errors allow a new preview', (tester) async {
    await open(tester);
    picker.path = '${folder.path}/offline';
    await selectFolder(tester);
    expect(find.text('Could not read the selected folder.'), findsOneWidget);
    expect(tester.widget<AppButton>(button('Apply')).onPressed, isNull);
    picker.path = source.path;
    await selectFolder(tester);
    expect(find.text('Choose a different root folder.'), findsOneWidget);
    picker.path = target.path;
    await selectFolder(tester);
    File('${target.path}/a movie.mp4').setLastModifiedSync(DateTime(2030));
    final dynamic apply = tester.widget<AppButton>(button('Apply')).onPressed;
    await tester.runAsync(() async { await apply(); });
    await tester.pumpAndSettle();
    expect(find.text('The files changed. Build a new preview before applying.'), findsOneWidget);
    expect(tester.widget<AppButton>(button('Apply')).onPressed, isNull);
    await selectFolder(tester);
    expect(tester.widget<AppButton>(button('Apply')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.tap(button('Cancel'));
    await tester.pumpAndSettle();
  });
}
