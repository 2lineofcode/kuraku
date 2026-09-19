import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/page_search/page_search_tab.dart';
import 'package:javit/app/modules/home/page_search/page_search_view.dart';
import 'package:javit/app/modules/widgets/widget_double_tap.dart';
import 'package:sqflite/sqflite.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;
import 'package:toastification/toastification.dart';

class _Home extends GetxController implements HomeController {
  final home = HomeController();
  @override
  Future<void> onInit() async { super.onInit(); }
  @override
  bool isInCart(Videos video) => home.isInCart(video);
  @override
  bool addToCart(Videos video) => home.addToCart(video);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final favorites = <String>[];
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'videos');
    expect(where, 'id = ?');
    expect(values['is_favorite'], 1);
    favorites.add(whereArgs!.single as String);
    return 1;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tab extends PageSearchTab {
  _Tab(super.id);
  final actions = <({String action, List<Videos> videos})>[];
  @override
  Future<void> performSelectionAction(String action, List<Videos> selected) async {
    actions.add((action: action, videos: selected));
  }
}

void main() {
  testWidgets('Command selection works in grid and list with a captured batch menu', (tester) async {
    Get.put<HomeController>(_Home());
    final tab = _Tab(0);
    addTearDown(tab.dispose);
    addTearDown(Get.reset);
    final videos = List.generate(3, (i) => Videos(id: '$i', title: 'Video $i', videoCode: '', viewCount: i));
    tab.showResults('Video', videos);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageSearchTabView(controller: tab))));
    await tester.pumpAndSettle();

    Future<void> commandClick(int index) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(DoubleTap).at(index)), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
    }

    await commandClick(0);
    await commandClick(1);
    expect(tab.selectedVideos, {videos[0], videos[1]});
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true), findsNWidgets(2));
    await commandClick(0);
    expect(tab.selectedVideos, {videos[1]});
    await commandClick(0);

    tab.toggleViewMode();
    await tester.pumpAndSettle();
    expect(find.byType(DoubleTap), findsNWidgets(3));
    expect(tab.selectedVideos.length, 2);
    await commandClick(1);
    expect(tab.selectedVideos, {videos[0]});
    await commandClick(1);

    final notifier = ValueNotifier<scm.MenuResult?>(null);
    addTearDown(notifier.dispose);
    final request = scm.MenuRequest(onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero);
    final menus = tester.widgetList<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget)).toList();
    final batch = menus.where((menu) => menu.contextMenuIsAllowed(Offset.zero)).first;
    final menu = (await batch.menuProvider(request))!;
    expect(menu.children.map((item) => item.title), ['Play', 'Play Multi Player', 'Add to cart', 'Add to Playlist', 'Add to favorite']);
    expect(menus.where((menu) => !menu.contextMenuIsAllowed(Offset.zero)).length, 3);
    tab.toggleSelection(videos[1]);
    for (final action in menu.children.cast<scm.MenuAction>()) { action.callback(); }
    expect(tab.actions.map((item) => item.action), ['play', 'playMulti', 'cart', 'playlist', 'favorite']);
    expect(tab.actions.every((item) => item.videos.length == 2 && item.videos[0] == videos[0] && item.videos[1] == videos[1]), isTrue);

    tab.showResults('New', videos);
    expect(tab.selectedVideos, isEmpty);
    menu.children.cast<scm.MenuAction>().first.callback();
    expect(tab.actions.length, 5);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('Command taps do not trigger normal single or double tap actions', (tester) async {
    var singles = 0;
    var doubles = 0;
    var commands = 0;
    await tester.pumpWidget(MaterialApp(home: Material(child: DoubleTap(
      onSingleTap: () => singles++, onDoubleTap: () => doubles++, onCommandTap: () => commands++,
      child: const SizedBox(width: 100, height: 100),
    ))));
    final item = find.byType(DoubleTap);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(item);
    await tester.tap(item);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 200));
    expect([commands, singles, doubles], [2, 0, 0]);
    await tester.tap(item);
    await tester.pump(kDoubleTapTimeout);
    expect([singles, doubles], [1, 0]);
    await tester.tap(item);
    await tester.pump(const Duration(milliseconds: 250));
    expect([singles, doubles], [1, 0]);
    await tester.tap(item);
    await tester.pump(kDoubleTapTimeout);
    expect([singles, doubles], [1, 1]);

    await tester.tap(item);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(kDoubleTapTimeout);
    expect([singles, doubles], [1, 1]);

    await tester.pumpWidget(MaterialApp(home: Material(child: DoubleTap(
      onSingleTap: () => singles++,
      child: const SizedBox(width: 100, height: 100),
    ))));
    await tester.tap(item);
    await tester.tap(item);
    expect(singles, 3);
  });

  testWidgets('batch cart deduplicates and favorite updates every selected video', (tester) async {
    final home = Get.put<HomeController>(_Home()) as _Home;
    final database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
    addTearDown(Get.reset);
    final tab = PageSearchTab(0);
    addTearDown(tab.dispose);
    final selected = [Videos(id: '1'), Videos(id: '2')];
    await tester.pumpWidget(ToastificationWrapper(child: MaterialApp(home: Scaffold())));
    await tab.performSelectionAction('cart', selected);
    await tab.performSelectionAction('cart', selected);
    expect(home.home.cart.map((video) => video.id), ['1', '2']);
    await tab.performSelectionAction('favorite', selected);
    expect(database.favorites, ['1', '2']);
    expect(selected.every((video) => video.isFavorite == 1), isTrue);
    tab.close();
    await tab.performSelectionAction('favorite', selected);
    expect(database.favorites.length, 2);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    toastification.dismissAll(delayForAnimation: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test('selection is tab-local, follows visible results and clears on new search or close', () async {
    final tab = _Tab(0);
    final other = _Tab(1);
    addTearDown(tab.dispose);
    addTearDown(other.dispose);
    final first = Videos(id: '1', videoCode: 'ABC-123', viewCount: 1);
    final second = Videos(id: '2', videoCode: '', viewCount: 2);
    tab.showResults('Video', [first, second]);
    other.showResults('Video', [first, second]);
    tab.toggleSelection(first);
    tab.toggleSelection(second);
    expect(other.selectedVideos, isEmpty);
    await tab.onSortByChange('View Count');
    expect(tab.selectedVideos, {first, second});
    await tab.onSortByChange('Release Date');
    expect(tab.selectedVideos, {first});
    tab.showResults('New', [first]);
    expect(tab.selectedVideos, isEmpty);
    tab.toggleSelection(first);
    tab.close();
    expect(tab.selectedVideos, isEmpty);
    tab.toggleSelection(first);
    expect(tab.selectedVideos, isEmpty);
  });
}
