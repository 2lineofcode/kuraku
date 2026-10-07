import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/modules/home/page_sqleditor/page_sqleditor_controller.dart';
import 'package:javit/app/modules/widgets/widget_search_tab_bar.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import 'icon_finder.dart';

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
        tabs: [for (var i = 0; i < tabs.length; i++) (id: i, title: tabs[i].title, isLoading: tabs[i].isLoading, isPinned: false)],
        activeIndex: activeIndex,
        scrollController: scrollController,
        onSelect: selected.add,
        onClose: closed.add,
        onAdd: () => added++,
        onReorder: (_, _) {},
        onPin: (_) {},
        addTooltip: addTooltip ?? 'New search tab',
      )),
    ));
    if (tabs.any((tab) => tab.isLoading)) {
      await tester.pump(const Duration(milliseconds: 200));
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('renders one entry per tab plus the add button', (tester) async {
    await pump(tester, [(title: 'Cosplay', isLoading: false), (title: 'Drama', isLoading: false)]);

    expect(find.text('Cosplay'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    expect(findHugeIconButton(HugeIcons.strokeRoundedAdd01), findsOneWidget);
    expect(findHugeIconButton(HugeIcons.strokeRoundedCancel01), findsNWidgets(2));
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

    await tester.tap(findHugeIconButton(HugeIcons.strokeRoundedCancel01).at(1));
    expect(closed, [1]);

    await tester.tap(findHugeIconButton(HugeIcons.strokeRoundedAdd01));
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
    expect(tester.widget<IconButton>(findHugeIconButton(HugeIcons.strokeRoundedAdd01)).tooltip, 'Open another search');
    expect(tester.widget<IconButton>(findHugeIconButton(HugeIcons.strokeRoundedCancel01)).tooltip, 'Close tab');
  });

  testWidgets('renders an empty bar with only the add button when there is no tab', (tester) async {
    await pump(tester, const []);

    expect(findHugeIconButton(HugeIcons.strokeRoundedAdd01), findsOneWidget);
    expect(findHugeIconButton(HugeIcons.strokeRoundedCancel01), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('dragging moves tabs and context menus pin and close the clicked tab', (tester) async {
    final notifier = ValueNotifier<scm.MenuResult?>(null);
    addTearDown(notifier.dispose);
    final request = scm.MenuRequest(onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero);
    final controller = Get.put(PageSqleditorController(sources: {'javit.db': '/javit.db'}));
    final first = controller.activeTab;
    controller.addTab();
    final second = controller.activeTab;
    controller.addTab();
    final third = controller.activeTab;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: Obx(() => SearchTabBar(
      tabs: controller.tabs.map((tab) => (id: tab.id, title: tab.title, isLoading: false, isPinned: tab.isPinned.value)).toList(),
      activeIndex: controller.activeTabIndex.value,
      scrollController: controller.tabScrollController,
      onSelect: controller.selectTab, onClose: controller.closeTab, onAdd: controller.addTab,
      onReorder: controller.reorderTab, onPin: controller.toggleTabPin,
    )))));
    await tester.pumpAndSettle();
    expect(findHugeIconButton(HugeIcons.strokeRoundedPin02), findsNothing);
    final gesture = await tester.startGesture(tester.getCenter(find.text(first.title)));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(420, 0));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.tabs, [second, third, first]);
    expect(controller.activeTab, same(third));
    final menu = (await tester.widget<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget).last).menuProvider(request))!;
    expect(menu.children.map((action) => action.title), ['Pin', 'Close tab']);
    (menu.children.first as scm.MenuAction).callback();
    await tester.pumpAndSettle();
    expect(controller.tabs, [first, second, third]);
    expect(first.isPinned.value, isTrue);
    expect(find.byTooltip('Close tab'), findsNWidgets(2));
    expect(find.byTooltip('Unpin tab'), findsOneWidget);
    final pinnedMenu = (await tester.widget<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget).first).menuProvider(request))!;
    expect(pinnedMenu.children.map((action) => action.title), ['Unpin', 'Close tab']);
    expect((pinnedMenu.children.last as scm.MenuAction).attributes.disabled, isTrue);
    await tester.tap(find.byTooltip('Unpin tab'));
    await tester.pumpAndSettle();
    expect(first.isPinned.value, isFalse);
    expect(find.byTooltip('Close tab'), findsNWidgets(3));
    expect(findHugeIconButton(HugeIcons.strokeRoundedPin02), findsNothing);
    final closeMenu = (await tester.widget<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget).last).menuProvider(request))!;
    (closeMenu.children.last as scm.MenuAction).callback();
    await tester.pumpAndSettle();
    expect(controller.tabs, [first, second]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
