import 'package:flutter/material.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/local_video_selection_item.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_tab.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_view.dart';
import 'package:kuraku/app/modules/widgets/widget_thumbnail.dart';

class _CartController extends GetxController implements HomeController {
  final HomeController home;
  _CartController(this.home);

  @override
  Future<void> onInit() async { super.onInit(); }

  @override
  bool isInCart(Videos video) => home.isInCart(video);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('compact Search rows fit more results at desktop and narrow widths', (tester) async {
    final home = HomeController();
    Get.put<HomeController>(_CartController(home));
    final search = PageSearchTab(0);
    addTearDown(search.dispose);
    addTearDown(Get.reset);
    addTearDown(() { home.tecTopNavSearch.dispose(); home.fnTopNavSearch.dispose(); });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    search.showResults('Test', List.generate(20, (i) => Videos(id: '$i', videoCode: 'TEST-$i',
      title: 'A long title that should stay compact without overflowing the row',
      quality: '1920x1080', filesize: 3500000000, releaseDate: '2025-01-01', viewCount: 10,
      actress: [VideoActress(nameRomaji: 'First actress, Second actress')])));
    for (final width in [1000.0, 360.0]) {
      tester.view.physicalSize = Size(width, 600);
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: Size(width, 600), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: PageSearchTabView(controller: search).modeListView()),
        )));
        await tester.pumpAndSettle();
        final rows = find.byType(LocalVideoSelectionItem, skipOffstage: false);
        expect(tester.getSize(rows.first).height, lessThanOrEqualTo(scale == 1 ? 90 : 160));
        if (scale == 1) expect(tester.getRect(find.text('TEST-5', skipOffstage: false)).bottom, lessThan(600));
        expect(tester.getSize(find.byType(ExThumbnail, skipOffstage: false).first), const Size(112, 76));
        expect(find.textContaining('2025', skipOffstage: false), findsWidgets);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Search cart backdrop follows identity, removal and clearing without blocking input', (tester) async {
    final home = HomeController();
    Get.put<HomeController>(_CartController(home));
    final search = PageSearchTab(0);
    addTearDown(search.dispose);
    addTearDown(Get.reset);
    final video = Videos(id: 'video-1', videoCode: '', title: 'Test');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: PageSearchTabView(controller: search).buildLayoutPoster(video, 150, 230, showReleaseDate: false),
    ))));
    await tester.pumpAndSettle();
    final marker = find.byWidgetPredicate((widget) => widget is HugeIcon && widget.icon == HugeIcons.strokeRoundedShoppingBag01, skipOffstage: false);
    expect(marker, findsNothing);

    final stored = Videos(id: ' VIDEO-1 ', title: 'Stored copy');
    expect(home.addToCart(stored), isTrue);
    expect(home.addToCart(video), isFalse);
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget);
    final overlay = find.ancestor(of: marker, matching: find.byType(IgnorePointer)).first;
    expect(tester.widget<IgnorePointer>(overlay).ignoring, isTrue);

    home.cart.remove(stored);
    await tester.pumpAndSettle();
    expect(marker, findsNothing);
    home.addToCart(video);
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget);
    home.cart.clear();
    await tester.pumpAndSettle();
    expect(marker, findsNothing);

    home.addToCart(Videos(id: 'video-2', videoPath: '/videos/test.mp4'));
    expect(home.isInCart(Videos(id: 'other', videoPath: '/videos/test.mp4')), isTrue);
    expect(home.isInCart(Videos(id: 'video-2', videoPath: '/videos/other.mp4')), isFalse);
    search.showResults('Test', [video]);
    search.toggleViewMode();
    home.addToCart(video);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageSearchTabView(controller: search))));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterListView), findsOneWidget);
    expect(marker, findsOneWidget);
    home.cart.clear();
    await tester.pumpAndSettle();
    expect(marker, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    home.tecTopNavSearch.dispose();
    home.fnTopNavSearch.dispose();
  });
}
