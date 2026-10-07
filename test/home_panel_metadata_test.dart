import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_metadata.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';
import 'package:toastification/toastification.dart';

class _MetadataBinding extends AutomatedTestWidgetsFlutterBinding {
  // Get.forceAppUpdate uses hot reload, which conflicts with fake animation frames.
  @override
  // ignore: must_call_super
  Future<void> performReassemble() async {}
}

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  void writeInMemory(String key, dynamic value) => values[key] = value;

  @override
  Future<void> write(String key, dynamic value) async => writeInMemory(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  void onClose() {
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
  }
}

class _MainDatabase implements Database {
  final updates = <Map<String, Object?>>[];
  final deletes = <List<Object?>>[];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    return [{'id': 'video-1', 'is_favorite': 0}];
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'videos');
    expect(where, 'id = ?');
    updates.add(Map<String, Object?>.from(values));
    return 1;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    expect(table, 'videos');
    deletes.add(whereArgs ?? const []);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _R18Database implements Database {
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (table == 'derived_category') {
      return [
        {'id': 11, 'name_en': 'Drama'},
        {'id': 22, 'name_en': 'Cosplay'},
      ];
    }
    return [
      {'id': 99, 'name_romaji': 'Yua Mikami', 'name_kana': 'ユア', 'name_kanji': '三上悠亜', 'image_url': ''},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Videos _video() => Videos(
      id: 'video-1',
      videoCode: 'ABP-001',
      title: 'Original title',
      videoPath: '/movies/ABP-001.mp4',
      fanArt: 'https://img/cover.jpg',
      releaseDate: '2026-01-02',
      duration: 120,
      studio: 'Prestige',
      label: 'ABP',
      director: 'Someone',
      series: 'Some series',
      actress: [VideoActress(id: 1, nameRomaji: 'Yua Mikami', imageUrl: '')],
      category: [VideoCategory(id: 11, category: 'Drama')],
    );

void main() {
  _MetadataBinding();
  late _MainDatabase database;
  late _Home home;

  setUp(() {
    database = _MainDatabase();
    Get.put(AppSettingService()..pref = _Preferences());
    Get.put<DBService>(_Service()
      ..dbMain = database
      ..dbR18 = _R18Database());
    home = _Home();
    Get.put<HomeController>(home);
    HomePanelAppLog.clear();
  });
  void metadataTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        while (Overlayment.count > 0) {
          unawaited(Overlayment.dismissLast());
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        Get.reset();
      }
    });
  }

  Future<void> pump(WidgetTester tester, {Brightness brightness = Brightness.dark}) async {
    await tester.pumpWidget(ToastificationWrapper(
      child: GetMaterialApp(theme: ThemeData(brightness: brightness), home: const Scaffold(body: Text('Home'))),
    ));
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(CupertinoTextField).at(index);

  metadataTest('prefills every field, actress and category of the video', (tester) async {
    await pump(tester);

    unawaited(HomePanelMetadata.open(_video()));
    await tester.pumpAndSettle();

    expect(Overlayment.count, 1);
    expect(find.text('Edit Metadata (ABP-001)'), findsOneWidget);
    expect(find.text('Original title'), findsOneWidget);
    expect(find.text('https://img/cover.jpg'), findsOneWidget);
    expect(find.text('2026-01-02'), findsOneWidget);
    expect(find.text('Prestige'), findsOneWidget);
    expect(find.text('Some series'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('No actress added'), findsNothing);
    expect(find.text('No category added'), findsNothing);
  });

  metadataTest('shows the empty hints when there is no cast or tag yet', (tester) async {
    await pump(tester);

    unawaited(HomePanelMetadata.open(Videos(id: 'video-2', videoCode: '', title: 'Untagged')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Metadata '), findsOneWidget);
    expect(find.text('No actress added'), findsOneWidget);
    expect(find.text('No category added'), findsOneWidget);
  });

  metadataTest('submitting saves the edited values and closes the panel', (tester) async {
    final video = _video();
    await pump(tester);

    unawaited(HomePanelMetadata.open(video));
    await tester.pumpAndSettle();

    await tester.enterText(field(1), 'A better title');
    await tester.enterText(field(4), '99');
    await tester.enterText(field(5), 'S1NO1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(database.updates, hasLength(1));
    final saved = database.updates.single;
    expect(saved['title'], 'A better title');
    expect(saved['duration'], 99);
    expect(saved['studio'], 'S1NO1');
    expect(saved['video_code'], 'ABP-001');
    expect(saved['updated_at'], isNotNull);
    expect(video.title, 'A better title');
    expect(Overlayment.count, 0);
  });

  metadataTest('an invalid video code is rejected before anything is written', (tester) async {
    await pump(tester);

    unawaited(HomePanelMetadata.open(_video()));
    await tester.pumpAndSettle();

    await tester.enterText(field(0), 'not a code');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(database.updates, isEmpty);
    expect(Overlayment.count, 1, reason: 'the panel stays open so the user can fix the code');
    expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), contains('Video code not valid'));
  });

  metadataTest('an empty video code is allowed for non JAV videos', (tester) async {
    await pump(tester);

    unawaited(HomePanelMetadata.open(_video()));
    await tester.pumpAndSettle();

    await tester.enterText(field(0), '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(database.updates.single['video_code'], '');
    expect(Overlayment.count, 0);
  });

  metadataTest('delete removes the video and closes the panel', (tester) async {
    await pump(tester);

    unawaited(HomePanelMetadata.open(_video()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(database.deletes.single, ['video-1']);
    expect(database.updates, isEmpty);
    expect(Overlayment.count, 0);
  });

  metadataTest('a category chip can be removed and the change is persisted', (tester) async {
    final video = _video();
    await pump(tester);

    unawaited(HomePanelMetadata.open(video));
    await tester.pumpAndSettle();
    expect(find.text('Drama'), findsOneWidget);

    final chip = find.ancestor(of: find.text('Drama'), matching: find.byType(Row)).first;
    await tester.ensureVisible(chip);
    await tester.tap(find.descendant(of: chip, matching: find.byWidgetPredicate((widget) => widget is Icon && widget.size == 10)));
    await tester.pumpAndSettle();

    expect(find.text('No category added'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(video.category, isEmpty);
    expect(jsonDecode('${database.updates.single['category']}'), isEmpty);
  });

  metadataTest('a category can be picked from the R18 catalogue', (tester) async {
    final video = Videos(id: 'video-3', videoCode: 'ABP-002', title: 'Fresh');
    await pump(tester);

    unawaited(HomePanelMetadata.open(video));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Add category'));
    await tester.tap(find.byTooltip('Add category'));
    await tester.pumpAndSettle();
    expect(find.text('Add Category'), findsOneWidget);
    expect(Overlayment.count, 2);

    await tester.enterText(find.byType(CupertinoTextField).last, 'Cos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cosplay').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit').last);
    await tester.pumpAndSettle();

    expect(Overlayment.count, 1, reason: 'only the category dialog closes');
    expect(find.text('Add Category'), findsNothing);
    expect(find.text('Cosplay'), findsOneWidget, reason: 'the new chip is rendered in the panel');

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(video.category, hasLength(1));
    expect(video.category!.single.category, 'Cosplay');
    expect(video.category!.single.id, 22);
    expect('${database.updates.single['category']}', contains('Cosplay'));
  });

  for (final brightness in Brightness.values) {
    metadataTest('compact ${brightness.name} form keeps actions visible and discards draft on close', (tester) async {
      tester.view.physicalSize = const Size(420, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final video = _video();
      await pump(tester, brightness: brightness);
      unawaited(HomePanelMetadata.open(video));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoFormSection), findsNWidgets(3));
      final header = tester.getTopLeft(find.text('Edit Metadata (ABP-001)'));
      final submit = tester.getTopLeft(find.text('Submit'));
      await tester.ensureVisible(find.byTooltip('Delete Drama'));
      await tester.tap(find.byTooltip('Delete Drama'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Delete Yua Mikami'));
      await tester.tap(find.byTooltip('Delete Yua Mikami'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field(8));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Edit Metadata (ABP-001)')), header);
      expect(tester.getTopLeft(find.text('Submit')), submit);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(video.category!.single.category, 'Drama');
      expect(video.actress!.single.nameRomaji, 'Yua Mikami');
      expect(database.updates, isEmpty);
      expect(Overlayment.count, 0);
    });
  }
}
