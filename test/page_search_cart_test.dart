import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/page_search/page_search_tab.dart';
import 'package:javit/app/modules/home/page_search/page_search_view.dart';

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
    final marker = find.byIcon(Icons.shopping_bag);
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
    expect(find.byType(ListView), findsOneWidget);
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
