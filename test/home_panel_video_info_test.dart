import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_video_info.dart';
import 'package:javit/app/modules/home/page_home/page_home_controller.dart';
import 'package:javit/app/modules/home/page_search/page_search_controller.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';
import 'package:toastification/toastification.dart';

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

class _Search extends PageSearchController {
  Videos? renewed;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> renewMetadata(Videos videos) async => renewed = videos;
}

class _PageHome extends PageHomeController {
  int favoriteRefreshes = 0;

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> getListFavorite() async => favoriteRefreshes++;
}

class _Database implements Database {
  final updates = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    return [{'id': 'video-1', 'is_favorite': 0}];
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    updates.add(Map<String, Object?>.from(values));
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Videos _video({int favorite = 0}) => Videos(
      id: 'video-1',
      videoCode: 'ABP-001',
      title: 'A R**e of a title',
      videoPath: '/Volumes/Movies/ABP-001.mp4',
      fanArt: '',
      quality: '1920x1080',
      filesize: 1024 * 1024 * 700,
      duration: 120,
      isFavorite: favorite,
      createdAt: '2026-01-02 10:00:00',
      studio: 'Prestige',
      actress: [VideoActress(id: 1, nameRomaji: 'Yua Mikami', nameKana: 'ユア', imageUrl: '')],
      category: [VideoCategory(id: 11, category: 'Drama')],
    );

void main() {
  late _Database database;
  late _Home home;
  late _Search search;
  late _PageHome pageHome;

  setUp(() {
    database = _Database();
    Get.put(AppSettingService()..pref = _Preferences());
    Get.put<DBService>(_Service()..dbMain = database);
    home = _Home();
    Get.put<HomeController>(home);
    search = _Search();
    Get.put<PageSearchController>(search);
    pageHome = _PageHome();
    Get.put<PageHomeController>(pageHome);
    HomePanelAppLog.clear();
  });
  tearDown(() async {
    Get.reset();
  });

  Future<void> cleanup(WidgetTester tester) async {
    while (Overlayment.count > 0) {
      unawaited(Overlayment.dismissLast());
      await tester.pumpAndSettle();
    }
    toastification.dismissAll(delayForAnimation: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ToastificationWrapper(
      child: GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Home'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the code, the decensored title, the quality badge and the metadata', (tester) async {
    await pump(tester);

    unawaited(HomePanelVideoInfo.open(_video()));
    await tester.pumpAndSettle();

    expect(Overlayment.count, 1);
    expect(find.text('ABP-001'), findsOneWidget);
    expect(find.text('A Rape of a title'), findsOneWidget, reason: 'the masked title is expanded for display');
    expect(find.textContaining('FHD'), findsOneWidget);
    expect(find.text('# Metadata'), findsOneWidget);
    expect(find.text('Actress:'), findsOneWidget);
    expect(find.text('Yua Mikami'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    expect(find.text('1920x1080'), findsOneWidget);
    expect(find.byTooltip('/Volumes/Movies/ABP-001.mp4'), findsWidgets);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Add/Remove Favorite'), findsOneWidget);
    expect(find.byTooltip('Renew Metadata'), findsOneWidget);
    expect(find.byTooltip('Open File Path'), findsOneWidget);
    expect(find.byTooltip('Add to Panel Cart'), findsOneWidget);
    expect(find.byTooltip('Add To Playlist'), findsOneWidget);
    expect(find.byTooltip('Edit Metadata'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('the favorite action toggles the stored flag and refreshes the home list', (tester) async {
    final video = _video();
    await pump(tester);

    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add/Remove Favorite'));
    await tester.pumpAndSettle();
    expect(database.updates.single['is_favorite'], 1);
    expect(video.isFavorite, 1);
    expect(pageHome.favoriteRefreshes, 1);

    await tester.tap(find.byTooltip('Add/Remove Favorite'));
    await tester.pumpAndSettle();
    expect(database.updates.last['is_favorite'], 0);
    expect(pageHome.favoriteRefreshes, 2);
    await cleanup(tester);
  });

  testWidgets('adding to the panel cart closes the panel and refuses duplicates', (tester) async {
    final video = _video();
    await pump(tester);

    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to Panel Cart'));
    await tester.pumpAndSettle();

    expect(home.cart, [video]);
    expect(Overlayment.count, 0);

    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to Panel Cart'));
    await tester.pumpAndSettle();

    expect(home.cart, hasLength(1));
    expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), contains('Already in panel cart'));
    await cleanup(tester);
  });

  testWidgets('renew metadata is delegated to the search controller', (tester) async {
    final video = _video();
    await pump(tester);

    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Renew Metadata'));
    await tester.pumpAndSettle();

    expect(search.renewed, same(video));
    await cleanup(tester);
  });

  testWidgets('the down arrow and the I shortcut close the panel', (tester) async {
    await pump(tester);

    unawaited(HomePanelVideoInfo.open(_video()));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);

    unawaited(HomePanelVideoInfo.open(_video()));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    await cleanup(tester);
  });

  testWidgets('editing the metadata swaps this panel for the editor', (tester) async {
    await pump(tester);

    unawaited(HomePanelVideoInfo.open(_video()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit Metadata'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Metadata (ABP-001)'), findsOneWidget);
    expect(find.text('# Metadata'), findsNothing);
    expect(Overlayment.count, 1);
    await cleanup(tester);
  });
}
