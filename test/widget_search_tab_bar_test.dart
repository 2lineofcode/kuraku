import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/modules/widgets/widget_search_tab_bar.dart';

void main() {
  late ScrollController scrollController;
  late List<int> selected;
  late List<int> closed;
  late int added;

  setUp(() {
    scrollController = ScrollController();
    selected = [];
    closed = [];
    added = 0;
  });
  tearDown(() {
    scrollController.dispose();
    Get.reset();
  });

  Future<void> pump(WidgetTester tester, List<({String title, bool isLoading})> tabs, {int activeIndex = 0, String? addTooltip}) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(body: SearchTabBar(
        tabs: tabs,
        activeIndex: activeIndex,
        scrollController: scrollController,
        onSelect: selected.add,
        onClose: closed.add,
        onAdd: () => added++,
        addTooltip: addTooltip ?? 'New search tab',
      )),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders one entry per tab plus the add button', (tester) async {
    await pump(tester, [(title: 'Cosplay', isLoading: false), (title: 'Drama', isLoading: false)]);

    expect(find.text('Cosplay'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.add), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsNWidgets(2));
    expect(tester.getSize(find.byType(SearchTabBar)).height, 32);
  });

  testWidgets('shows a spinner only for the tabs that are still loading', (tester) async {
    await pump(tester, [(title: 'Loading one', isLoading: true), (title: 'Ready', isLoading: false), (title: 'Loading two', isLoading: true)]);

    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('reports the tapped tab, the closed tab and the add action', (tester) async {
    await pump(tester, [(title: 'First', isLoading: false), (title: 'Second', isLoading: false), (title: 'Third', isLoading: false)], activeIndex: 1);

    await tester.tap(find.text('Third'));
    await tester.tap(find.text('First'));
    expect(selected, [2, 0]);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close).at(1));
    expect(closed, [1]);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    expect(added, 1);
    expect(selected, [2, 0], reason: 'the add button must not change the selection');
  });

  testWidgets('highlights the active tab differently from the others', (tester) async {
    await pump(tester, [(title: 'First', isLoading: false), (title: 'Second', isLoading: false)], activeIndex: 1);

    final decorations = tester
        .widgetList<Container>(find.descendant(of: find.byType(SearchTabBar), matching: find.byType(Container)))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .toList();

    expect(decorations.length, greaterThanOrEqualTo(2));
    expect(decorations[0].color, isNot(decorations[1].color), reason: 'the active tab uses the selected color');
    expect(decorations[0].borderRadius, BorderRadius.circular(6));
  });

  testWidgets('exposes the full title and the configurable add tooltip', (tester) async {
    const longTitle = 'A very long search tab title that will definitely be ellipsised';
    await pump(tester, [(title: longTitle, isLoading: false)], addTooltip: 'Open another search');

    final text = tester.widget<Text>(find.text(longTitle));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.widget<Tooltip>(find.ancestor(of: find.text(longTitle), matching: find.byType(Tooltip)).first).message, longTitle);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).tooltip, 'Open another search');
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close)).tooltip, 'Close tab');
  });

  testWidgets('renders an empty bar with only the add button when there is no tab', (tester) async {
    await pump(tester, const []);

    expect(find.widgetWithIcon(IconButton, Icons.add), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
