import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_controller.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_controller.dart';
import 'package:sqflite/sqflite.dart';

class _Database implements Database {
  final requests = <Completer<List<Map<String, Object?>>>>[];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) {
    expect(table, 'videos');
    expect(where, contains('is_deleted = 0'));
    final request = Completer<List<Map<String, Object?>>>();
    requests.add(request);
    return request.future;
  }

  void complete(int index, Videos? video) => requests[index].complete(video == null ? [] : [video.toJson()]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends HomeController {
  @override
  Future<void> getAllPlaylist() async {}

  @override
  Future<void> updateFooterSummary() async {}
}

class _PageHome extends PageHomeController {
  int refreshes = 0;
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  Future<void> onRefresh() async { refreshes++; }
}

class _Search extends PageSearchController {
  int refreshes = 0;
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  Future<void> onRefresh() async { refreshes++; }
  @override
  // ignore: must_call_super
  void onClose() { tabScrollController.dispose(); }
}

class _Download extends PageDownloadController {
  int refreshes = 0;
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  Future<void> onRefresh() async { refreshes++; }
  @override
  // ignore: must_call_super
  void onClose() { tabScrollController.dispose(); }
}

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Videos _video(String id, {String? title}) => Videos(id: id, title: title ?? id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Home home;
  late _Database database;

  setUp(() {
    home = _Home();
    database = _Database();
    Get.put<DBService>(DBService()..dbMain = database);
  });

  tearDown(() {
    home.tecTopNavSearch.dispose();
    home.fnTopNavSearch.dispose();
    Get.reset();
  });

  test('video changes refresh only the active page and defer hidden pages until selected', () async {
    Get.put(AppSettingService()..pref = _Preferences());
    final dashboard = Get.put<PageHomeController>(_PageHome()) as _PageHome;
    final search = Get.put<PageSearchController>(_Search()) as _Search;
    final download = Get.put<PageDownloadController>(_Download()) as _Download;
    await home.refreshVideoContent();
    await home.refreshVideoContent();
    expect(dashboard.refreshes, 2);
    expect(search.refreshes, 0);
    expect(download.refreshes, 0);
    await home.onMenuChange(kMenuSearch);
    expect(search.refreshes, 1);
    await home.onMenuChange(kMenuSearch);
    expect(search.refreshes, 1);
    await home.refreshVideoContent();
    expect(search.refreshes, 2);
    expect(dashboard.refreshes, 2);
    await home.onMenuChange(kMenuHome);
    expect(dashboard.refreshes, 3);
    await home.onMenuChange(kMenuDownload);
    expect(download.refreshes, 1);
    await home.onMenuChange(kMenuDownload);
    expect(download.refreshes, 1);
    await home.refreshVideoContent();
    expect(download.refreshes, 2);
  });

  test('cart paths preserve case on POSIX and ignore case on Windows', () {
    final upper = Videos(id: 'upper', videoPath: '/movies/A.mp4');
    final lower = Videos(id: 'lower', videoPath: '/movies/a.mp4');
    expect(home.addToCart(upper), isTrue);
    expect(home.isInCart(lower), Platform.isWindows);
    expect(home.addToCart(lower), !Platform.isWindows);
    home.cart.add(lower);
    home.deduplicateCart();
    expect(home.cart, hasLength(Platform.isWindows ? 1 : 2));
    expect(home.isInCart(Videos(videoCode: 'ABP-001')), isFalse);
    expect(home.addToCart(Videos(videoCode: ' ABP-001 ')), isTrue);
    expect(home.addToCart(Videos(videoCode: 'abp-001')), isFalse);
  });

  test('refresh updates retained items and preserves additions and removals during lookup', () async {
    final retained = _video('retained');
    final removed = _video('removed');
    final added = _video('added');
    home.cart.addAll([retained, removed]);
    final refresh = home.refreshVideoContent();
    expect(database.requests, hasLength(2));
    home.cart.remove(removed);
    home.addToCart(added);
    database.complete(0, _video('retained', title: 'Updated'));
    database.complete(1, _video('removed', title: 'Removed update'));
    await refresh;
    expect(home.cart.map((video) => video.id), ['retained', 'added']);
    expect(home.cart.first.title, 'Updated');
    expect(home.cart.last, same(added));
  });

  test('clearing the cart during lookup does not restore its snapshot', () async {
    home.cart.add(_video('original'));
    final refresh = home.refreshVideoContent();
    home.cart.clear();
    database.complete(0, _video('original', title: 'Updated'));
    await refresh;
    expect(home.cart, isEmpty);
  });

  test('refresh deduplicates a moved item added again at its new path', () async {
    home.cart.add(Videos(id: 'original', videoPath: '/old/video.mp4', title: 'Old metadata'));
    final refresh = home.refreshVideoContent();
    expect(database.requests, hasLength(1));
    expect(home.addToCart(Videos(id: 'original', videoPath: '/new/video.mp4', title: 'Added copy')), isTrue);
    database.complete(0, Videos(id: 'original', videoPath: '/new/video.mp4', title: 'Latest metadata'));
    await refresh;
    expect(home.cart, hasLength(1));
    expect(home.cart.single.videoPath, '/new/video.mp4');
    expect(home.cart.single.title, 'Latest metadata');
    expect(home.addToCart(Videos(id: 'original', videoPath: '/new/video.mp4')), isFalse);
  });

  test('remove and re-add preserves the new item with the same identity', () async {
    home.cart.add(_video('original'));
    final refresh = home.refreshVideoContent();
    home.cart.clear();
    final replacement = _video('original', title: 'New selection');
    home.addToCart(replacement);
    database.complete(0, _video('original', title: 'Old lookup'));
    await refresh;
    expect(home.cart.single, same(replacement));
  });

  test('an older overlapping refresh cannot overwrite the latest metadata', () async {
    home.cart.add(_video('original'));
    final first = home.refreshVideoContent();
    final second = home.refreshVideoContent();
    database.complete(1, _video('original', title: 'Latest'));
    await second;
    database.complete(0, _video('original', title: 'Stale'));
    await first;
    expect(home.cart.single.title, 'Latest');
  });

  test('an older refresh finishing first leaves the newest lookup able to update the cart', () async {
    final original = _video('original');
    home.cart.add(original);
    final first = home.refreshVideoContent();
    final second = home.refreshVideoContent();
    database.complete(0, _video('original', title: 'Stale'));
    await first;
    expect(home.cart.single, same(original));
    database.complete(1, _video('original', title: 'Latest'));
    await second;
    expect(home.cart.single.title, 'Latest');
  });

  test('a missing database row is removed while an unsaved item stays in the cart', () async {
    home.cart.addAll([Videos(videoPath: '/movies/deleted.mp4'), Videos(title: 'Unsaved')]);
    final refresh = home.refreshVideoContent();
    database.complete(0, null);
    await refresh;
    expect(home.cart.single.title, 'Unsaved');
  });
}
