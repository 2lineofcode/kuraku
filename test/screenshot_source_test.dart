import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/widgets/widget_screenshot_source.dart';
import 'package:kuraku/app/modules/widgets/widget_screenshot_viewer.dart';
import 'package:kuraku/app/utils/helper_opener.dart';

void main() {
  tearDown(Get.reset);

  List<Videos> videos() => List.generate(60, (index) => Videos(
    videoCode: 'VIDEO-$index', videoPath: '/video-$index.mp4',
  ));

  for (final mode in ['grid', 'list', 'horizontal']) {
    testWidgets('$mode returns to the last screenshot item without moving while browsing', (tester) async {
      final items = videos();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Widget itemBuilder(BuildContext context, int index) => TextButton(
        onPressed: () => unawaited(HelperOpener.openScreenshot(items[index], items: items, localFrames: true)),
        child: Text('Item $index'),
      );
      final source = mode == 'grid'
          ? ScreenshotSource.grid(items: items, controller: scroll,
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160, mainAxisExtent: 100, mainAxisSpacing: 8, crossAxisSpacing: 8,
              ), itemBuilder: itemBuilder)
          : ScreenshotSource.list(items: items, controller: scroll,
              itemExtent: 100, scrollDirection: mode == 'horizontal' ? Axis.horizontal : Axis.vertical,
              itemBuilder: itemBuilder);
      await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: SizedBox(width: 500, height: 300, child: source))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item 0'));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotViewer), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(find.text('Video 21/60 · VIDEO-20 · 0/0'), findsOneWidget);
      expect(scroll.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotViewer), findsNothing);
      expect(scroll.offset, greaterThan(0));
      final target = find.text('Item 20');
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.widgetList<Focus>(find.ancestor(of: target, matching: find.byType(Focus)))
        .any((widget) => widget.focusNode?.hasPrimaryFocus == true), isTrue);
      expect(tester.widgetList<Semantics>(find.ancestor(of: target, matching: find.byType(Semantics)))
        .any((widget) => widget.properties.selected == true), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('snapshot chains preserve the origin and visible items keep the current scroll offset', (tester) async {
    final items = videos();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(height: 300,
      child: ScreenshotSource.list(items: items, itemExtent: 100, controller: scroll,
        itemBuilder: (_, index) => Text('Item $index')),
    ))));
    await tester.pumpAndSettle();
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    final snapshot = ScreenshotSource.snapshot(ScreenshotSource.snapshot(items));
    final restored = ScreenshotSource.restore(snapshot, items[6], focus: false);
    await tester.pumpAndSettle();
    await restored;
    expect(scroll.offset, 500);
    expect(Focus.of(tester.element(find.text('Item 6'))).hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('separated lists reveal variable-height rows without estimating their offsets', (tester) async {
    final items = videos();
    final scroll = FlutterListViewController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(height: 300,
      child: ScreenshotSource.separated(items: items, controller: scroll,
        separatorBuilder: (_, index) => const SizedBox(height: 4),
        itemBuilder: (_, index) => SizedBox(height: index.isEven ? 120 : 200, child: Text('Item $index'))),
    ))));
    await tester.pumpAndSettle();
    final snapshot = ScreenshotSource.snapshot(items);
    final restored = ScreenshotSource.restore(snapshot, items[30]);
    await tester.pumpAndSettle();
    await restored;
    expect(find.text('Item 30', skipOffstage: false).hitTestable(), findsOneWidget);
    final offset = scroll.offset;
    final again = ScreenshotSource.restore(snapshot, items[30]);
    await tester.pumpAndSettle();
    await again;
    expect(scroll.offset, offset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('return matches the current item after reordering and ignores removed items or disposed origins', (tester) async {
    final items = videos();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Widget source() => MaterialApp(home: Scaffold(body: SizedBox(height: 300,
      child: ScreenshotSource.list(items: items, itemExtent: 100, controller: scroll,
        itemBuilder: (_, index) => Text(items[index].videoPath!)),
    )));
    await tester.pumpWidget(source());
    final snapshot = ScreenshotSource.snapshot(items);
    final target = items.removeAt(20);
    target.videoCode = items.first.videoCode;
    items.insert(30, target);
    await tester.pumpWidget(source());
    final restored = ScreenshotSource.restore(snapshot, target);
    await tester.pumpAndSettle();
    await restored;
    expect(scroll.offset, 2800);
    expect(find.text(target.videoPath!).hitTestable(), findsOneWidget);
    items.remove(target);
    await tester.pumpWidget(source());
    await ScreenshotSource.restore(snapshot, target);
    expect(scroll.offset, 2800);
    await tester.pumpWidget(const SizedBox.shrink());
    await ScreenshotSource.restore(snapshot, snapshot.first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate groups reveal their last item through the surrounding scroll view', (tester) async {
    final items = videos().take(10).toList();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(height: 300,
      child: SingleChildScrollView(controller: scroll,
        child: ScreenshotSource.column(items: items,
          itemBuilder: (_, index) => SizedBox(height: 100, child: Text('Item $index')))),
    ))));
    final snapshot = ScreenshotSource.snapshot(items);
    final restored = ScreenshotSource.restore(snapshot, items[8]);
    await tester.pumpAndSettle();
    await restored;
    expect(scroll.offset, 600);
    expect(find.text('Item 8').hitTestable(), findsOneWidget);
    final again = ScreenshotSource.restore(snapshot, items[8]);
    await tester.pumpAndSettle();
    await again;
    expect(scroll.offset, 600);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
