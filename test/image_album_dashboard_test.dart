import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_library.dart';
import 'package:kuraku/app/data/models/library_entity.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_view.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:kuraku/app/modules/img_viewer/img_viewer_view.dart';
import 'package:kuraku/app/routes/app_pages.dart';

import 'sqlite_test_database.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  Future<void> writeIfNull(String key, dynamic value) async { values.putIfAbsent(key, () => value); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Home extends PageHomeController {
  @override
  Future<void> onRefresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteTestDatabase db;
  final pref = _Preferences();
  late AppSettingService settings;
  setUp(() async {
    db = await SqliteTestDatabase.open();
    await DBService.onCreate(db, DBUpdate.version);
    Get.put<DBService>(_Service()..dbMain = db);
    pref.values.clear();
    settings = Get.put(AppSettingService()..pref = pref);
  });
  tearDown(() async {
    settings.onClose();
    Get.reset();
    await db.close();
  });

  test('existing Home order and hidden sections survive adding the album section', () async {
    pref.values['_kHomeOrderList'] = [AppPref.homeSecFavorite, AppPref.homeSecRecommendation];
    pref.values[AppPref.homeSecFavorite] = false;
    await settings.setupAppPref();
    await settings.setupAppPref();
    expect(AppPref.getHomeOrderList(), [AppPref.homeSecFavorite, AppPref.homeSecRecommendation, AppPref.homeSecImageAlbums]);
    expect(AppPref.getBool(AppPref.homeSecFavorite), isFalse);
    expect(AppPref.getBool(AppPref.homeSecImageAlbums), isTrue);
    pref.values[AppPref.homeSecImageAlbums] = false;
    await settings.setupAppPref();
    expect(AppPref.getBool(AppPref.homeSecImageAlbums), isFalse);
  });

  test('Home and Settings include mixed and offline albums and refresh stored counts', () async {
    await DBLibrary.add(Library(rootFolder: '/video', totalVideo: 1));
    await DBLibrary.add(Library(rootFolder: '/offline', images: ['/offline/a.png', '/offline/b.png']));
    final mixed = Library(rootFolder: '/mixed', totalVideo: 1, images: ['/mixed/a.png']);
    await DBLibrary.add(mixed);
    final home = Get.put<PageHomeController>(_Home());
    final info = PageSettingsController();
    addTearDown(info.onClose);
    await home.getImageAlbums();
    await info.refreshLibraryStats();
    expect(home.listImageAlbums.map((album) => album.rootFolder), ['/offline', '/mixed']);
    expect(['/offline/a.png', '/offline/b.png'], contains(home.imageAlbumCovers['/offline']));
    expect(home.imageAlbumCovers['/mixed'], '/mixed/a.png');
    expect(home.listImageAlbums.first.images, ['/offline/a.png', '/offline/b.png']);
    expect((await DBLibrary.getByRootFolder('/offline')).single.images, ['/offline/a.png', '/offline/b.png']);
    expect(info.totalLibrary.value, 3);
    expect(info.totalAlbums.value, 2);
    expect(info.totalImages.value, 3);
    await DBLibrary.delete(mixed);
    await home.getImageAlbums();
    await info.refreshLibraryStats();
    expect(home.listImageAlbums, hasLength(1));
    expect(home.imageAlbumCovers.containsKey('/mixed'), isFalse);
    expect(info.totalAlbums.value, 1);
    expect(info.totalImages.value, 2);
    await DBLibrary.delete(home.listImageAlbums.single);
    await home.getImageAlbums();
    expect(home.imageAlbumCovers, isEmpty);

  });

  testWidgets('image-only Home shows album covers and opens the viewer with an offline placeholder', (tester) async {
    final directory = Directory.systemTemp.createTempSync('home_album_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/cover.png')..writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
    pref.values[AppPref.homeSecImageAlbums] = true;
    final home = Get.put<PageHomeController>(_Home());
    home.homeSectionOrder.assignAll([AppPref.homeSecImageAlbums]);
    await tester.runAsync(() async {
      await DBLibrary.add(Library(rootFolder: directory.path, alias: 'My album', images: [image.path]));
      await DBLibrary.add(Library(rootFolder: '/offline', alias: 'Offline album', images: ['/offline/cover.png']));
      await home.getImageAlbums();
    });
    await tester.pumpWidget(GetMaterialApp(
      getPages: AppPages.routes.where((page) => page.name == Routes.IMG_VIEWER).toList(),
      home: const Scaffold(body: PageHomeView()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Image Albums'), findsOneWidget);
    expect(find.text('My album'), findsOneWidget);
    expect(find.text('Images: 1'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    final cover = tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(cover.width, 440);
    expect(cover.height, 880);
    expect(cover.policy, ResizeImagePolicy.fit);
    expect(find.text('~ Fresh ~'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('My album'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ImgViewerView), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ImgViewerView), findsNothing);
    home.listImageAlbums.clear();
    await tester.pumpAndSettle();
    expect(find.text('~ Fresh ~'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
