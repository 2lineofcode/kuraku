import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_log.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_metadata.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_controller.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_tab.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
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
  Future<void> refreshProfile() async {}

  @override
  Future<void> refreshVideoContent() async { videoRefreshes++; }

}

class _RefreshingHome extends HomeController {
  Completer<void>? nextRefresh;

  @override
  void onReady() {}

  @override
  Future<void> refreshProfile() async {}

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

class _MainDatabase implements Database, Transaction {
  Map<String, Object?> row = {};
  final updates = <Map<String, Object?>>[];
  bool failWrites = false;
  Completer<void>? pendingWrite;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (row['is_deleted'] == 1) return [];
    if (whereArgs != null && whereArgs.isNotEmpty && whereArgs.first != row['id']) return [];
    if (whereArgs != null && whereArgs.length > 1 && whereArgs[1] != row['video_path']) return [];
    return [Map.of(row)];
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'videos');
    expect(where, anyOf('id = ? AND is_deleted = 0', 'id = ? AND video_path = ? AND is_deleted = 0'));
    await pendingWrite?.future;
    if (failWrites) throw StateError('Database unavailable');
    updates.add(Map<String, Object?>.from(values));
    row.addAll(values);
    return 1;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) => action(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _R18Database implements Database {
  Completer<void>? pendingRead;
  List<Map<String, Object?>> categories = [
    {'id': 11, 'name_en': 'Drama'},
    {'id': 22, 'name_en': 'Cosplay'},
  ];
  List<Map<String, Object?>> actresses = [
    {'id': 99, 'name_romaji': 'Yua Mikami', 'name_kana': 'ユア', 'name_kanji': '三上悠亜', 'image_url': ''},
  ];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    await pendingRead?.future;
    return table == 'derived_category' ? categories : actresses;
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
      releaseDateFormated: 'Old release date',
      duration: 120,
      durationFormated: 'Old duration',
      studio: 'Prestige',
      label: 'ABP',
      director: 'Someone',
      series: 'Some series',
      actress: [VideoActress(id: 99, nameRomaji: 'Yua Mikami', imageUrl: '')],
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

  Future<void> open(Videos video) {
    database.row = Map<String, Object?>.from(Videos.fromJson(video.toJson()).toJson());
    return HomePanelMetadata.open(video);
  }

  Finder field(int index) => find.byType(CupertinoTextField).at(index);

  metadataTest('prefills every field, actress and category of the video', (tester) async {
    await pump(tester);

    unawaited(open(_video()));
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

    unawaited(open(Videos(id: 'video-2', videoCode: '', title: 'Untagged')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Metadata '), findsOneWidget);
    expect(find.text('No actress added'), findsOneWidget);
    expect(find.text('No category added'), findsOneWidget);
  });

  metadataTest('submitting saves the edited values and closes the panel', (tester) async {
    final video = _video();
    await pump(tester);

    unawaited(open(video));
    await tester.pumpAndSettle();

    await tester.enterText(field(1), 'A better title');
    await tester.enterText(field(3), '2024-02-29');
    await tester.enterText(field(4), '99');
    await tester.enterText(field(5), 'S1NO1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(database.updates, hasLength(1));
    final saved = database.updates.single;
    expect(saved['title'], 'A better title');
    expect(saved['duration'], 99);
    expect(saved['duration_formated'], '1 hours, 39 minutes');
    expect(saved['release_date'], '2024-02-29');
    expect(saved['release_date_formated'], 'Feb 29, 2024');
    expect(saved['studio'], 'S1NO1');
    expect(saved['video_code'], 'ABP-001');
    expect(saved['updated_at'], isNotNull);
    expect(home.videoRefreshes, 1);
    expect(video.title, 'Original title', reason: 'the displayed lists reload after the write succeeds');
    expect(Overlayment.count, 0);
  });

  for (final invalid in ['-1', '1.5', 'abc', 'NaN', 'Infinity']) {
    metadataTest('invalid duration $invalid keeps the edited draft open', (tester) async {
      await pump(tester);
      unawaited(open(_video()));
      await tester.pumpAndSettle();
      await tester.enterText(field(1), 'Unsaved draft');
      await tester.enterText(field(4), invalid);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(database.updates, isEmpty);
      expect(Overlayment.count, 1);
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content),
        contains('Enter a whole number of minutes (0 or more) or leave it empty.'));
    });
  }

  for (final invalid in ['2025-02-29', '2026-13-01', '2026-1-02', 'not a date']) {
    metadataTest('invalid release date $invalid keeps the draft open', (tester) async {
      await pump(tester);
      unawaited(open(_video()));
      await tester.pumpAndSettle();
      await tester.enterText(field(3), invalid);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(database.updates, isEmpty);
      expect(Overlayment.count, 1);
      expect(find.text(invalid), findsOneWidget);
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content),
        contains('Enter a valid release date (YYYY-MM-DD) or leave it empty.'));
    });
  }

  metadataTest('clearing duration and release date also clears their old display values', (tester) async {
    await pump(tester);
    unawaited(open(_video()));
    await tester.pumpAndSettle();
    await tester.enterText(field(3), '   ');
    await tester.enterText(field(4), '');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(database.updates.single['release_date'], '');
    expect(database.updates.single['release_date_formated'], '');
    expect(database.updates.single['duration'], 0);
    expect(database.updates.single['duration_formated'], '0 minutes');
  });

  metadataTest('an invalid video code is rejected before anything is written', (tester) async {
    await pump(tester);

    unawaited(open(_video()));
    await tester.pumpAndSettle();

    await tester.enterText(field(0), 'not a code');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(database.updates, isEmpty);
    expect(Overlayment.count, 1, reason: 'the panel stays open so the user can fix the code');
    expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), contains('Video code not valid'));
  });

  metadataTest('repeated submit only writes once while saving', (tester) async {
    await pump(tester);
    unawaited(open(_video()));
    await tester.pumpAndSettle();
    final write = Completer<void>();
    database.pendingWrite = write;
    try {
      await tester.tap(find.text('Submit'));
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(Overlayment.count, 1);
    } finally {
      write.complete();
      await tester.pumpAndSettle();
    }
    expect(database.updates, hasLength(1));
    expect(Overlayment.count, 0);
  });

  metadataTest('failed writes keep the draft open without changing displayed metadata', (tester) async {
    final video = _video();
    database.failWrites = true;
    await pump(tester);
    unawaited(open(video));
    await tester.pumpAndSettle();
    await tester.enterText(field(1), 'Unsaved title');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(video.title, 'Original title');
    expect(database.updates, isEmpty);
    expect(home.videoRefreshes, 0);
    expect(Overlayment.count, 1);
    expect(find.text('Unsaved title'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(home.videoRefreshes, 0);
    expect(Overlayment.count, 1);
    database.failWrites = false;
    await tester.enterText(field(1), 'Recovered draft');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(database.updates.single['title'], 'Recovered draft');
    expect(Overlayment.count, 0);
  });

  metadataTest('refreshing stored metadata during editing rejects stale save and preserves the draft', (tester) async {
    final video = _video();
    await pump(tester);
    unawaited(open(video));
    await tester.pumpAndSettle();
    await tester.enterText(field(1), 'My unsaved title');
    await DBVideos.updateMetadata(Videos.fromJson(database.row), Videos(
      poster: 'Refreshed poster', screenshot: ['Refreshed screenshot'], duration: 125,
    ));
    final refreshed = Map.of(database.row);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(database.updates, hasLength(1), reason: 'only the completed metadata refresh writes');
    expect(database.row, refreshed);
    expect(database.row['poster'], 'Refreshed poster');
    expect(database.row['duration'], 125);
    expect(Overlayment.count, 1);
    expect(find.text('My unsaved title'), findsOneWidget);
    expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content),
      anyElement(contains('Video changed or was removed. Reopen it and try again.')));
    expect(video.title, 'Original title');
  });

  metadataTest('an empty video code is allowed for non JAV videos', (tester) async {
    await pump(tester);

    unawaited(open(_video()));
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

    unawaited(open(_video()));
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

    unawaited(open(video));
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

    unawaited(open(video));
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

  metadataTest('an actress selection saves the complete catalog row', (tester) async {
    await pump(tester);
    unawaited(open(Videos(id: 'video-3', videoCode: 'ABP-002')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Add actress'));
    await tester.tap(find.byTooltip('Add actress'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).last, 'Yua');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yua Mikami').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    final actress = (jsonDecode('${database.updates.single['actress']}') as List).single;
    expect(actress, {'id': 99, 'name_romaji': 'Yua Mikami', 'name_kana': 'ユア', 'name_kanji': '三上悠亜', 'image_url': ''});
  });

  for (final kind in ['category', 'actress']) {
    metadataTest('catalog completion during editor close animation does not open an orphan $kind picker', (tester) async {
      await pump(tester);
      unawaited(open(_video()));
      await tester.pumpAndSettle();
      final pending = Completer<void>();
      (Get.find<DBService>().dbR18 as _R18Database).pendingRead = pending;
      try {
        await tester.ensureVisible(find.byTooltip('Add $kind'));
        await tester.tap(find.byTooltip('Add $kind'));
        await tester.pump();
        await tester.tap(find.byTooltip('Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(Overlayment.count, 1, reason: 'the parent is still reversing its close animation');
        pending.complete();
        await tester.pumpAndSettle();
        expect(Overlayment.count, 0);
      } finally {
        if (!pending.isCompleted) pending.complete();
      }
      await tester.pumpAndSettle();
      expect(Overlayment.count, 0);
      expect(tester.takeException(), isNull);
    });

    metadataTest('adding $kind while saving cannot leave an orphan picker', (tester) async {
      await pump(tester);
      unawaited(open(_video()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Add $kind'));
      final write = Completer<void>();
      database.pendingWrite = write;
      try {
        await tester.tap(find.text('Submit'));
        await tester.pump();
        await tester.tap(find.byTooltip('Add $kind'));
        await tester.pumpAndSettle();
        expect(Overlayment.count, 1);
      } finally {
        write.complete();
        await tester.pumpAndSettle();
      }
      expect(database.updates, hasLength(1));
      expect(Overlayment.count, 0);
      expect(tester.takeException(), isNull);
    });

    metadataTest('unknown $kind is rejected without closing or losing the draft', (tester) async {
      await pump(tester);
      unawaited(open(_video()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Add $kind'));
      await tester.tap(find.byTooltip('Add $kind'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).last, 'Unknown name');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(Overlayment.count, 2);
      expect(find.text('Unknown name'), findsOneWidget);
      expect(database.updates, isEmpty);
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content),
        contains(kind == 'category' ? 'Choose a category from the suggestions.' : 'Choose an actress from the suggestions.'));
    });

    metadataTest('adding an existing $kind does not duplicate its chip', (tester) async {
      await pump(tester);
      unawaited(open(_video()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Add $kind'));
      await tester.tap(find.byTooltip('Add $kind'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).last, kind == 'category' ? 'Drama' : 'Yua Mikami');
      await tester.tap(find.text('Submit').last);
      await tester.pumpAndSettle();
      expect(Overlayment.count, 1);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      final saved = jsonDecode('${database.updates.single[kind]}') as List;
      expect(saved, hasLength(1));
    });
  }

  metadataTest('Kana-only actress keeps its visible chip name and full catalog identity', (tester) async {
    final r18 = Get.find<DBService>().dbR18 as _R18Database;
    r18.actresses = [
      {'id': 77, 'name_romaji': null, 'name_kana': 'ユア', 'name_kanji': '三上悠亜', 'image_url': ''},
    ];
    await pump(tester);
    unawaited(open(_video()..actress = []));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Add actress'));
    await tester.tap(find.byTooltip('Add actress'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).last, 'ユア');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ユア').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit').last);
    await tester.pumpAndSettle();
    expect(find.text('ユア'), findsOneWidget);
    expect(find.byTooltip('Delete ユア'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    final actress = (jsonDecode('${database.updates.single['actress']}') as List).single;
    expect(actress, {'id': 77, 'name_romaji': '', 'name_kana': 'ユア', 'name_kanji': '三上悠亜', 'image_url': ''});
  });

  metadataTest('empty catalog category names cannot turn an empty submit into a chip', (tester) async {
    (Get.find<DBService>().dbR18 as _R18Database).categories.addAll([
      {'id': 33, 'name_en': ''},
      {'id': 44, 'name_en': '   '},
      {'id': 55, 'name_en': null},
    ]);
    await pump(tester);
    unawaited(open(_video()..category = []));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Add category'));
    await tester.tap(find.byTooltip('Add category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit').last);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 2);
    expect(find.text('No category added'), findsOneWidget);
    expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content),
      contains('Choose a category from the suggestions.'));
    expect(database.updates, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final existing in [
    VideoCategory(id: 0, category: ' drama '),
    VideoCategory(id: 11, category: 'Cosplay'),
  ]) {
    metadataTest('category names determine duplicates when API and catalog IDs differ: ${existing.category}', (tester) async {
      await pump(tester);
      unawaited(open(_video()..category = [existing]));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Add category'));
      await tester.tap(find.byTooltip('Add category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).last, 'Drama');
      await tester.tap(find.text('Submit').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      final saved = jsonDecode('${database.updates.single['category']}') as List;
      expect(saved, hasLength(existing.id == 0 ? 1 : 2));
    });
  }

  for (final brightness in Brightness.values) {
    metadataTest('compact ${brightness.name} form keeps actions visible and discards draft on close', (tester) async {
      tester.view.physicalSize = const Size(420, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final video = _video();
      await pump(tester, brightness: brightness);
      unawaited(open(video));
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
