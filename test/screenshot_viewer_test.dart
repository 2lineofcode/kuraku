import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/widgets/widget_screenshot_viewer.dart';
import 'package:kuraku/app/modules/widgets/widget_thumbnail.dart';
import 'package:kuraku/app/utils/helper_opener.dart';
import 'package:overlayment/overlayment.dart';

import 'icon_finder.dart';

Videos video(String code, int images) => Videos(videoCode: code,
  screenshot: List.generate(images, (index) => 'https://example.test/$code-$index.jpg'));

Future<void> itemKey(WidgetTester tester, LogicalKeyboardKey arrow) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(arrow);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
}

String? currentImage(WidgetTester tester) => tester.widgetList<ExThumbnail>(find.byType(ExThumbnail)).first.imageUrl;

void main() {
  setUp(() => Get.put(AppSettingService()..appPath = Directory.systemTemp.path));
  tearDown(Get.reset);

  test('item matching preserves local duplicate paths and converted R18 items', () {
    final a = Videos(videoCode: 'ABC-001', videoPath: '/a.mp4');
    final b = Videos(videoCode: 'ABC-001', videoPath: '/b.mp4');
    expect(HelperOpener.screenshotItemIndex(b, [a, b]), 1);
    expect(HelperOpener.screenshotItemIndex(Videos(videoCode: 'ABC-001', videoPath: '/b.mp4'), [a, b]), 1);
    expect(HelperOpener.screenshotItemIndex(Videos(videoCode: 'ABC-001'), [{'video_code': 'ABC-001'}]), 0);
    expect(HelperOpener.screenshotItemIndex(Videos(), [a]), -1);
  });

  testWidgets('Option arrow shortcuts reset images, stop at boundaries, and consume player seeking', (tester) async {
    final items = [video('A', 12), video('B', 2)];
    final loads = <dynamic>[];
    var seeks = 0;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => seeks++},
      child: ScreenshotViewer(video: items.first, items: items, itemIndex: 0,
        loadVideo: (item) async { loads.add(item); return item as Videos; },
        onClose: () {}, onWarning: (message) => fail(message)),
    ))));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(currentImage(tester), contains('A-1'));
    await itemKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(loads, isEmpty);
    expect(currentImage(tester), contains('A-1'));
    await tester.drag(find.byType(ListView), const Offset(-1000, 0));
    await tester.pump();
    expect(tester.widget<ListView>(find.byType(ListView)).controller!.offset, greaterThan(0));
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(tester.widget<ListView>(find.byType(ListView)).controller!.offset, 0);
    expect(currentImage(tester), contains('B-0'));
    expect(find.text('1/2 · B'), findsOneWidget);
    expect(seeks, 0);
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(loads, [items[1]]);
    await itemKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(currentImage(tester), contains('A-0'));
    expect(find.text('1/12 · A'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('thumbnail strip follows keyboard and arrow navigation in both directions', (tester) async {
    final a = video('A', 14);
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: ScreenshotViewer(
      video: a, items: [a], itemIndex: 0, loadVideo: (item) async => item as Videos,
      onClose: () {}, onWarning: (message) => fail(message),
    ))));
    await tester.pump();
    final list = find.byType(ListView);
    final scroll = tester.widget<ListView>(list).controller!;
    void expectVisible(int index) {
      final viewport = tester.getRect(list);
      final thumbnail = find.byWidgetPredicate((widget) => widget is ExThumbnail &&
        widget.width == 120 && widget.imageUrl == a.screenshot![index]);
      final rect = tester.getRect(thumbnail);
      expect(rect.left, greaterThanOrEqualTo(viewport.left - .01));
      expect(rect.right, lessThanOrEqualTo(viewport.right + .01));
    }
    for (var index = 1; index < 14; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expectVisible(index);
    }
    expect(scroll.offset, greaterThan(0));
    for (var index = 12; index >= 0; index--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expectVisible(index);
    }
    expect(scroll.offset, 0);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(findHugeIcon(HugeIcons.strokeRoundedArrowRight01));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(currentImage(tester), contains('A-1'));
    expectVisible(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty targets show their code and allow navigation while failures preserve the item', (tester) async {
    final a = video('A', 2);
    var failLoad = false;
    final warnings = <String>[];
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: ScreenshotViewer(
      video: a, items: [a, video('B', 0)..fanArt = 'https://example.test/B-cover.jpg', video('C', 1)], itemIndex: 0,
      loadVideo: (item) async {
        if (failLoad) throw StateError('database unavailable');
        return item as Videos;
      }, onClose: () {}, onWarning: warnings.add,
    ))));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(warnings, isEmpty);
    expect(find.text('0/0 · B'), findsOneWidget);
    expect(find.byType(ExThumbnail), findsOneWidget);
    expect(currentImage(tester), 'https://example.test/B-cover.jpg');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('0/0 · B'), findsOneWidget);
    failLoad = true;
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(warnings.last, 'Failed to load screenshots');
    expect(find.text('0/0 · B'), findsOneWidget);
    failLoad = false;
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(currentImage(tester), contains('C-0'));
    await itemKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text('0/0 · B'), findsOneWidget);
    await itemKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(currentImage(tester), contains('A-0'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rapid presses and closing during a load cannot apply stale results', (tester) async {
    final items = [video('A', 1), video('B', 2), video('C', 3)];
    final pending = Completer<Videos>();
    var loads = 0;
    var closed = false;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: ScreenshotViewer(
      video: items.first, items: items, itemIndex: 0,
      loadVideo: (_) { loads++; return pending.future; },
      onClose: () => closed = true, onWarning: (message) => fail(message),
    ))));
    await tester.pump();
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(loads, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, isTrue);
    pending.complete(items[1]);
    await tester.pump();
    expect(currentImage(tester), contains('A-0'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('close shortcuts and button only request closing once during the transition', (tester) async {
    var closes = 0;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: ScreenshotViewer(
      video: video('A', 1), items: const [], itemIndex: -1,
      loadVideo: (_) async => video('B', 1), onClose: () => closes++, onWarning: (message) => fail(message),
    ))));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(findHugeIcon(HugeIcons.strokeRoundedCancel01));
    expect(closes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('production viewer closes cleanly after its loader and preserves the panel underneath', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();
    final parent = OverPanel(child: const Text('Parent panel'));
    unawaited(Overlayment.show(parent, context: Get.context));
    await tester.pumpAndSettle();
    final closed = HelperOpener.openScreenshot(video('A', 2), localFrames: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(ScreenshotViewer), findsOneWidget);
    final other = OverPanel(child: const Text('Other overlay'));
    unawaited(Overlayment.show(other, context: Get.context));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await closed;
    expect(find.byType(ScreenshotViewer), findsNothing);
    expect(Overlayment.count, 2);
    expect(find.text('Other overlay').hitTestable(), findsOneWidget);
    unawaited(Overlayment.dismiss(other));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);
    expect(find.text('Parent panel').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    unawaited(Overlayment.dismiss(parent));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing during a load ignores the result', (tester) async {
    final a = video('A', 1);
    final pending = Completer<Videos>();
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: ScreenshotViewer(
      video: a, items: [a, video('B', 2)], itemIndex: 0,
      loadVideo: (_) => pending.future, onClose: () {}, onWarning: (message) => fail(message),
    ))));
    await tester.pump();
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(video('B', 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('animated overlay takes focus from an input and keeps compact arrows', (tester) async {
    final inputFocus = FocusNode();
    final viewerKey = GlobalKey<ScreenshotViewerState>();
    final items = [video('A', 2), video('B', 3)];
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextField(autofocus: true, focusNode: inputFocus))));
    await tester.pump();
    expect(inputFocus.hasFocus, isTrue);
    final panel = OverPanel(
      width: 720, height: 480, alignment: Alignment.center,
      animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
      actions: OverlayActions(onReady: () async => viewerKey.currentState?.requestFocus()),
      child: ScreenshotViewer(key: viewerKey, video: items.first, items: items, itemIndex: 0,
        loadVideo: (item) async => item as Videos,
        onClose: () => Overlayment.dismissLast(), onWarning: (message) => fail(message)),
    );
    unawaited(Overlayment.show(panel, context: Get.context));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(inputFocus.hasFocus, isFalse);
    for (final icon in [HugeIcons.strokeRoundedArrowLeft01, HugeIcons.strokeRoundedArrowRight01]) {
      final button = findHugeIcon(icon).evaluate().single;
      final container = find.ancestor(of: find.byWidget(button.widget), matching: find.byType(Container)).first;
      expect(tester.getSize(container).height, lessThan(80));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(currentImage(tester), contains('A-1'));
    await tester.tapAt(tester.getCenter(find.byType(ExThumbnail).last));
    await tester.pump();
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(currentImage(tester), contains('B-0'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(Overlayment.count, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    inputFocus.dispose();
  });

  testWidgets('an initially empty item has a zero counter and can open the next item', (tester) async {
    final empty = Videos(videoCode: 'EMPTY-123', fanArt: 'https://example.test/empty-cover.jpg');
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: ScreenshotViewer(
      video: empty, items: [empty, video('B', 1)], itemIndex: 0,
      loadVideo: (item) async => item as Videos, onClose: () {}, onWarning: (message) => fail(message),
    ))));
    await tester.pump();
    expect(find.text('0/0 · EMPTY-123'), findsOneWidget);
    expect(find.byType(ExThumbnail), findsOneWidget);
    expect(currentImage(tester), empty.fanArt);
    await itemKey(tester, LogicalKeyboardKey.arrowRight);
    expect(currentImage(tester), contains('B-0'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('missing R18 metadata preserves the requested video code', () async {
    Get.put(DBService());
    final resolved = await HelperOpener.resolveScreenshotVideo({'video_code': 'ABC-123'});
    expect(resolved.videoCode, 'ABC-123');
    expect(resolved.screenshot, isNull);
  });

  test('missing R18 screenshots use fan art or the full jacket from the source', () async {
    Get.put(DBService());
    for (final source in [
      {'video_code': 'ABC-123', 'fan_art': 'https://example.test/cover.jpg'},
      {'video_code': 'ABC-123', 'fan_art': '', 'jacket_full_url': 'https://example.test/cover.jpg'},
      Videos(videoCode: 'ABC-123', fanArt: 'https://example.test/cover.jpg'),
    ]) {
      final resolved = await HelperOpener.resolveScreenshotVideo(source);
      expect(resolved.fanArt, 'https://example.test/cover.jpg');
      expect(resolved.screenshot, isNull);
    }
  });

  test('local frame fallback requires an existing file', () {
    final file = File('${Directory.systemTemp.path}/kuraku-screenshot-test-${DateTime.now().microsecondsSinceEpoch}.mp4')..writeAsBytesSync([]);
    try {
      final local = Videos(videoPath: file.path);
      expect(ScreenshotViewer.hasImages(local), isFalse);
      expect(ScreenshotViewer.hasImages(local, localFrames: true), isTrue);
      file.deleteSync();
      expect(ScreenshotViewer.hasImages(local, localFrames: true), isFalse);
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  });
}
