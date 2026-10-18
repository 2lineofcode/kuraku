import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_log.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_video_info.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_controller.dart';
import 'package:kuraku/app/modules/widgets/widget_thumbnail.dart';
import 'package:kuraku/app/utils/helper_loading.dart';
import 'package:kuraku/app/utils/helper_opener.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;
import 'package:toastification/toastification.dart';

import 'api_test_http_client.dart';

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
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _PageHome extends PageHomeController {
  int favoriteRefreshes = 0;

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> getListFavorite() async => favoriteRefreshes++;
}

class _Explore extends PageExploreController {
  String? selectedMenu;
  String? selectedName;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> openSelection(String menu, String name, {bool newTab = false}) async {
    selectedMenu = menu;
    selectedName = name;
  }
}

class _Database implements Database, Transaction {
  final row = _video().toJson();
  bool failWrites = false;
  final updates = <Map<String, Object?>>[];

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) => action(this);

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (row['is_deleted'] == 1 && (where ?? '').contains('is_deleted = 0')) return [];
    if (whereArgs != null && whereArgs.isNotEmpty
        && whereArgs.first != row[(where ?? '').contains('video_path = ?') && !(where ?? '').startsWith('id = ?') ? 'video_path' : 'id']) return [];
    return [Map<String, Object?>.from(row)];
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    if (failWrites) throw StateError('Database unavailable');
    row.addAll(values);
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
    expect(find.byTooltip('Renew Metadata'), findsNothing);
    expect(find.byTooltip('Trailer'), findsOneWidget);
    expect(find.byTooltip('Open File Path'), findsOneWidget);
    expect(find.byTooltip('Add to Panel Cart'), findsOneWidget);
    expect(find.byTooltip('Add To Playlist'), findsOneWidget);
    expect(find.byTooltip('Edit Metadata'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('opener preserves the selected local record without an R18 lookup', (tester) async {
    await pump(tester);
    final first = _video()..title = 'First copy';
    final selected = _video()..id = 'video-2'..title = 'Selected copy'..videoPath = '/missing/selected.mp4';
    unawaited(HelperOpener.openVideoInfo(selected, items: [first, selected]));
    await tester.pumpAndSettle();
    expect(find.text('Selected copy'), findsOneWidget);
    expect(find.text('First copy'), findsNothing);
    expect(find.text('Yua Mikami'), findsOneWidget);
    expect(find.byTooltip('/missing/selected.mp4'), findsWidgets);
    await cleanup(tester);

    final nonJav = _video()..videoCode = ''..title = 'Personal clip'..videoPath = '/missing/personal.mp4';
    unawaited(HelperOpener.openVideoInfo(nonJav));
    await tester.pumpAndSettle();
    expect(find.text('Personal clip'), findsWidgets);
    expect(find.text('Yua Mikami'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('local info exposes the trailer action and hides renew metadata', (tester) async {
    final video = _video();
    await pump(tester);

    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Trailer'), findsOneWidget);
    expect(find.byTooltip('Renew Metadata'), findsNothing);
    await cleanup(tester);
  });

  testWidgets('trailer is hidden for NON-JAV and recognizes codes from local filenames', (tester) async {
    await pump(tester);
    for (final (code, path, showTrailer) in [
      (null, '/Volumes/Movies/Personal clip.mp4', false),
      ('NON-JAV', '/Volumes/Movies/Personal clip.mp4', false),
      ('', '/Volumes/Movies/ABP-001.mp4', true),
    ]) {
      final video = _video()..videoCode = code..videoPath = path;
      unawaited(HomePanelVideoInfo.open(video));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Trailer'), showTrailer ? findsOneWidget : findsNothing);
      unawaited(Overlayment.dismissLast());
      await tester.pumpAndSettle();
    }
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

  testWidgets('deleting the tracked video closes only its Info panel', (tester) async {
    await pump(tester);
    final video = _video();
    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    unawaited(Overlayment.show(context: Get.context, OverPanel(child: const Text('Other panel'))));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 2);
    await DBVideos.delete(video);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    expect(find.text('Other panel'), findsOneWidget);
    expect(find.byTooltip('Add to Panel Cart'), findsNothing);
    await cleanup(tester);
  });

  testWidgets('external Info remains open on unrelated revisions and shows Kanji-only cast', (tester) async {
    await pump(tester);
    final external = _video()..id = 'external'..actress = [VideoActress(id: 7, nameKanji: '日本語')];
    unawaited(HomePanelVideoInfo.open(external));
    await tester.pumpAndSettle();
    await DBVideos.addToFavorite(_video());
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    expect(find.text('日本語'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('Info follows a tracked video moved to a new path', (tester) async {
    await pump(tester);
    final video = _video();
    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    database.row['video_path'] = '/new/ABP-001.mp4';
    await DBVideos.addToFavorite(video);
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    expect(find.byTooltip('/new/ABP-001.mp4'), findsWidgets);
    expect(find.byTooltip(video.videoPath!), findsNothing);
    await cleanup(tester);
  });

  testWidgets('clicking Kanji-only cast explores the displayed name', (tester) async {
    final explore = Get.put<PageExploreController>(_Explore()) as _Explore;
    await pump(tester);
    final video = _video()..actress = [VideoActress(id: 7, nameKanji: '日本語')];
    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(home.currentMenuSelected.value, kMenuExplore);
    expect(explore.selectedMenu, kActress);
    expect(explore.selectedName, '日本語');
    expect(Overlayment.count, 0);
    expect(tester.takeException(), isNull);
    await cleanup(tester);
  });

  testWidgets('refresh context action updates the open info panel and preserves it on empty or failed responses', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dev.irondash.engine_context'), (_) => Completer<Object?>().future);
    messenger.setMockMethodCallHandler(const MethodChannel('flutter.arthenica.com/ffmpeg_kit_event'), (_) async => null);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(const MethodChannel('dev.irondash.engine_context'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('flutter.arthenica.com/ffmpeg_kit_event'), null);
    });
    final directory = Directory.systemTemp.createTempSync('kuraku-info-refresh-');
    addTearDown(() => directory.deleteSync(recursive: true));
    Get.find<AppSettingService>().appPath = directory.path;
    final client = ApiTestHttpClient();
    final video = _video()
      ..releaseDate = '2025-01-01'
      ..releaseDateFormated = 'Jan 01, 2025'
      ..durationFormated = '2 hours'
      ..site = 'Local';
    database.row.addAll(video.toJson());
    await pump(tester);
    unawaited(HomePanelVideoInfo.open(video));
    await tester.pumpAndSettle();
    final notifier = ValueNotifier<scm.MenuResult?>(null);
    addTearDown(notifier.dispose);
    final request = scm.MenuRequest(onShowMenu: notifier, onHideMenu: notifier,
      onPreviewAction: notifier, location: Offset.zero);

    Future<void> refresh(Map<String, Object?> response, {int statusCode = 200, Future<void> Function()? duringRequest}) async {
      client.response = response;
      client.statusCode = statusCode;
      final thumbnail = find.byType(ExThumbnail).first;
      final contextMenu = find.descendant(of: thumbnail, matching: find.byType(scm.ContextMenuWidget)).first;
      final menu = await tester.widget<scm.ContextMenuWidget>(contextMenu).menuProvider(request);
      final action = menu!.children.whereType<scm.MenuAction>().singleWhere((action) => action.title == 'Refresh Metadata');
      HomePanelAppLog.clear();
      await tester.runAsync(() async {
        final requests = client.requests.length;
        action.callback();
        if (duringRequest != null) {
          for (var attempt = 0; attempt < 100 && client.requests.length == requests; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          expect(client.requests.length, requests + 1);
          await duringRequest();
        }
        for (var attempt = 0; attempt < 100 && (!HomePanelAppLog.appLogRuntime.any((entry) => entry.type == 'SUCCESS' || entry.type == 'ERROR'
            || entry.content == 'Video changed or was removed. Reopen it and try again.')
            || find.text(database.row['title'] as String).evaluate().isEmpty); attempt++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(Overlayment.count, 1);
    }

    await HttpOverrides.runZoned(() async {
      await refresh({'video_code': 'ABP-001', 'title': 'Updated title', 'duration': 125, 'release_date': '2026-10-01'});
      expect(database.updates, hasLength(1));
      expect(find.text('Updated title'), findsOneWidget);
      expect(find.text('Oct 01, 2026'), findsOneWidget);
      expect(find.text('2 hours, 5 minutes'), findsOneWidget);
      expect(find.text('Yua Mikami'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
      expect(video.title, 'A R**e of a title');
      expect(video.releaseDate, '2025-01-01');
      expect(client.requests, hasLength(1));
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), contains('ABP-001 metadata updated'));

      await refresh({'title': 'Newest title'});
      expect(database.updates, hasLength(2));
      expect(client.requests, hasLength(2), reason: 'manual refresh must fetch again instead of using a cached response');
      expect(find.text('Newest title'), findsOneWidget);
      expect(find.text('Oct 01, 2026'), findsOneWidget);
      expect(find.text('2 hours, 5 minutes'), findsOneWidget);
      final saved = Map.of(database.row);

      await refresh({});
      expect(database.updates, hasLength(2));
      expect(database.row, saved);
      expect(find.text('Newest title'), findsOneWidget);
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), contains('No metadata found for ABP-001'));
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), isNot(contains('ABP-001 metadata updated')));

      await refresh({'error': 'Unavailable'}, statusCode: 503);
      expect(database.updates, hasLength(2));
      expect(database.row, saved);
      expect(find.text('Newest title'), findsOneWidget);
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), isNot(contains('ABP-001 metadata updated')));

      database.failWrites = true;
      await refresh({'title': 'Failed write title'});
      expect(database.updates, hasLength(2));
      expect(database.row, saved);
      expect(find.text('Failed write title'), findsNothing);
      expect(find.text('Newest title'), findsOneWidget);
      expect(video.title, 'A R**e of a title');

      database.failWrites = false;
      final pending = Completer<void>();
      client.pendingResponse = pending;
      try {
        await refresh({'title': 'Late response title'}, duringRequest: () async {
          await tester.pump();
          HelperLoading.dismiss();
          await tester.pumpAndSettle();
          await DBVideos.update(Videos.fromJson(database.row)..title = 'Manual title');
          pending.complete();
        });
      } finally {
        if (!pending.isCompleted) pending.complete();
        client.pendingResponse = null;
      }
      expect(database.updates, hasLength(3), reason: 'the manual edit is the only new write');
      expect(database.row['title'], 'Manual title');
      expect(find.text('Manual title'), findsOneWidget);
      expect(find.text('Late response title'), findsNothing);
      expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content),
        contains('Video changed or was removed. Reopen it and try again.'));
    }, createHttpClient: (_) => client);
    await cleanup(tester);
    debugDefaultTargetPlatformOverride = null;
  });

}
