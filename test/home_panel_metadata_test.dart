import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/_update_db.dart';
import 'package:javit/app/data/database/db_videos.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_metadata.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:javit/app/modules/home/page_home/page_home_controller.dart';
import 'package:javit/app/modules/home/page_search/page_search_controller.dart';
import 'package:javit/app/modules/home/page_search/page_search_tab.dart';
import 'package:javit/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';
import 'package:toastification/toastification.dart';

import 'sqlite_test_database.dart';

class _MetadataBinding extends AutomatedTestWidgetsFlutterBinding {
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
  int videoRefreshes = 0;

  @override
  void onReady() {}

  @override
  Future<void> refreshVideoContent() async { videoRefreshes++; }

}

class _RefreshingHome extends HomeController {
  Completer<void>? nextRefresh;

  @override
  void onReady() {}

  @override
  Future<void> updateFooterSummary() async { totalVideo.value = await DBVideos.getCount(); }

  @override
  Future<void> refreshVideoContent() async {
    await super.refreshVideoContent();
    nextRefresh?.complete();
    nextRefresh = null;
  }
}

class _PageHome extends PageHomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

class _Search extends PageSearchController {
  @override
  // ignore: must_call_super
  void onInit() {
    tabs.addAll([PageSearchTab(0), PageSearchTab(1)..tecSearch.text = 'Original']);
  }
}

class _Explore extends PageExploreController {
  @override
  // ignore: must_call_super
  void onInit() {
    tabs.add(PageExploreTab(0)
      ..currentMenuSelected.value = 'Path'
      ..leftListSelected.value = LeftListModel(name: '/movies'));
  }
}

class _Tools extends PageToolsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

class _MainDatabase implements Database {
  final updates = <Map<String, Object?>>[];
  bool failWrites = false;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    return [{'id': 'video-1', 'is_favorite': 0}];
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'videos');
    expect(where, 'id = ? AND is_deleted = 0');
    if (failWrites) throw StateError('Database unavailable');
    updates.add(Map<String, Object?>.from(values));
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

  test('database changes reload Home, all Search tabs, Explore, cart and playlist counts', () async {
    await Get.delete<HomeController>();
    final db = await SqliteTestDatabase.open();
    try {
      await DBService.onCreate(db, DBUpdate.version);
      Get.find<DBService>().dbMain = db;
      final video = _video()..rootPath = '/movies'..filesize = 123;
      await DBVideos.addBulk([video]);
      await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
      await db.execute("INSERT INTO playlist_item VALUES ('p1',?,'created')", [video.id]);
      final refreshingHome = Get.put<HomeController>(_RefreshingHome()) as _RefreshingHome;
      final pageHome = Get.put<PageHomeController>(_PageHome());
      final search = Get.put<PageSearchController>(_Search());
      final explore = Get.put<PageExploreController>(_Explore());
      final tools = Get.put<PageToolsController>(_Tools());
      refreshingHome.cart.add(Videos.fromJson(video.toJson()));
      await refreshingHome.refreshVideoContent();
      expect(search.tabs[1].videos.single.title, 'Original title');
      expect(explore.activeTab.rightListLocal.single.title, 'Original title');
      expect(refreshingHome.playlist.single.total, 1);
      refreshingHome.nextRefresh = Completer<void>();
      final updated = refreshingHome.nextRefresh!.future;
      await DBVideos.update(Videos.fromJson(video.toJson())..title = 'Updated title');
      await updated.timeout(const Duration(seconds: 5));
      expect(pageHome.listNewAdded.single.title, 'Updated title');
      expect(search.tabs[0].videos.single.title, 'Updated title');
      expect(search.tabs[1].videos, isEmpty);
      expect(search.tabs[1].tecSearch.text, 'Original');
      expect(explore.activeTab.rightListLocal.single.title, 'Updated title');
      expect(explore.activeTab.leftListSelected.value.name, '/movies');
      expect(refreshingHome.cart.single.title, 'Updated title');
      expect(tools.topLargeFileSizeList.single.title, 'Updated title');
      refreshingHome.nextRefresh = Completer<void>();
      final deleted = refreshingHome.nextRefresh!.future;
      await DBVideos.delete(video);
      await deleted.timeout(const Duration(seconds: 5));
      expect(pageHome.listNewAdded, isEmpty);
      expect(search.tabs.every((tab) => tab.videos.isEmpty), isTrue);
      expect(explore.activeTab.rightListLocal, isEmpty);
      expect(explore.activeTab.leftList, isEmpty);
      expect(refreshingHome.cart, isEmpty);
      expect(refreshingHome.totalVideo.value, 0);
      expect(refreshingHome.playlist.single.total, 0);
      expect(tools.topLargeFileSizeList, isEmpty);
    } finally {
      await Get.delete<HomeController>();
      await Get.delete<PageHomeController>();
      await Get.delete<PageSearchController>();
      await Get.delete<PageExploreController>();
      await Get.delete<PageToolsController>();
      Get.reset();
      await db.close();
    }
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
        await Get.delete<HomeController>();
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
    expect(home.videoRefreshes, 1);
    expect(video.title, 'Original title', reason: 'the displayed lists reload after the write succeeds');
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

  metadataTest('failed writes keep the draft open without changing displayed metadata', (tester) async {
    final video = _video();
    database.failWrites = true;
    await pump(tester);
    unawaited(HomePanelMetadata.open(video));
    await tester.pumpAndSettle();
    await tester.enterText(field(1), 'Unsaved title');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(video.title, 'Original title');
    expect(database.updates, isEmpty);
    expect(home.videoRefreshes, 0);
    expect(Overlayment.count, 1);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(home.videoRefreshes, 0);
    expect(Overlayment.count, 1);
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

  metadataTest('delete soft deletes the video, refreshes content and closes the panel', (tester) async {
    await pump(tester);

    unawaited(HomePanelMetadata.open(_video()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(database.updates.single['is_deleted'], 1);
    expect(home.videoRefreshes, 1);
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

    expect(home.videoRefreshes, 1);
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

    final savedCategory = jsonDecode('${database.updates.single['category']}') as List;
    expect(savedCategory.single, {'id': 22, 'category': 'Cosplay'});
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
