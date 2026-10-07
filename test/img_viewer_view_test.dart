import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/modules/img_viewer/img_viewer_controller.dart';
import 'package:javit/app/modules/img_viewer/img_viewer_view.dart';

import 'icon_finder.dart';

/// A 1x1 PNG, enough for `Image.file` to take the real file branch.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  late Directory directory;
  late List<String> images;
  late ImgViewerController controller;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('img_viewer_view');
    images = ['first.png', 'second.png', 'third.png'].map((name) {
      final file = File('${directory.path}/$name')..writeAsBytesSync(base64Decode(_png));
      return file.path;
    }).toList();
    controller = Get.put(ImgViewerController());
    controller.images.assignAll(images);
    controller.title.value = 'Screenshots';
  });
  tearDown(() {
    Get.reset();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const ImgViewerView()));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the file name, the counter and one thumbnail per image', (tester) async {
    await pump(tester);

    expect(find.text('first.png  1/3'), findsOneWidget);
    expect(find.descendant(of: find.byType(ListView), matching: find.byType(GestureDetector)), findsNWidgets(3));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('No image found'), findsNothing);
  });

  testWidgets('falls back to an empty state without images', (tester) async {
    controller.images.clear();
    await pump(tester);

    expect(find.text('No image found'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(findHugeIcon(HugeIcons.strokeRoundedArrowRight01), findsNothing);
  });

  testWidgets('only offers the navigation arrows that make sense', (tester) async {
    await pump(tester);

    expect(findHugeIcon(HugeIcons.strokeRoundedArrowLeft01), findsNothing, reason: 'already on the first image');
    expect(findHugeIcon(HugeIcons.strokeRoundedArrowRight01), findsOneWidget);

    await tester.tap(findHugeIcon(HugeIcons.strokeRoundedArrowRight01));
    await tester.pumpAndSettle();
    expect(find.text('second.png  2/3'), findsOneWidget);
    expect(findHugeIcon(HugeIcons.strokeRoundedArrowLeft01), findsOneWidget);

    await tester.tap(findHugeIcon(HugeIcons.strokeRoundedArrowRight01));
    await tester.pumpAndSettle();
    expect(find.text('third.png  3/3'), findsOneWidget);
    expect(findHugeIcon(HugeIcons.strokeRoundedArrowRight01), findsNothing, reason: 'last image reached');

    await tester.tap(findHugeIcon(HugeIcons.strokeRoundedArrowLeft01));
    await tester.pumpAndSettle();
    expect(controller.selectedIndex.value, 1);
  });

  testWidgets('a thumbnail tap jumps straight to that image', (tester) async {
    await pump(tester);

    await tester.tap(find.descendant(of: find.byType(ListView), matching: find.byType(GestureDetector)).at(2));
    await tester.pumpAndSettle();

    expect(controller.selectedIndex.value, 2);
    expect(find.text('third.png  3/3'), findsOneWidget);
  });

  testWidgets('the app bar actions drive zoom, rotation and shuffle', (tester) async {
    await pump(tester);
    double scale() => controller.transformationController.value.getMaxScaleOnAxis();

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(scale(), greaterThan(1));

    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 1e-9));

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(scale(), lessThan(1));

    await tester.tap(find.byTooltip('Rotate right'));
    await tester.pumpAndSettle();
    expect(controller.getCurrentQuarterTurns(), 1);
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox).first).quarterTurns, 1);

    await tester.tap(find.byTooltip('Rotate left'));
    await tester.tap(find.byTooltip('Rotate left'));
    await tester.pumpAndSettle();
    expect(controller.getCurrentQuarterTurns(), 3);

    await tester.tap(find.byTooltip('Shuffle'));
    await tester.pumpAndSettle();
    expect(controller.images.toSet(), images.toSet(), reason: 'shuffling keeps every image');
    expect(controller.selectedIndex.value, 0);
  });

  testWidgets('keyboard shortcuts mirror the toolbar', (tester) async {
    await pump(tester);
    double scale() => controller.transformationController.value.getMaxScaleOnAxis();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.selectedIndex.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(controller.selectedIndex.value, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    expect(scale(), greaterThan(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(controller.getCurrentQuarterTurns(), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    expect(controller.getCurrentQuarterTurns(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(controller.selectedIndex.value, 0, reason: 'unknown keys are ignored');
  });

  testWidgets('Q closes the viewer route', (tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Gallery'))));
    await tester.pumpAndSettle();

    await Get.to(() => const ImgViewerView());
    await tester.pumpAndSettle();
    expect(find.byType(ImgViewerView), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();

    expect(find.byType(ImgViewerView), findsNothing);
    expect(find.text('Gallery'), findsOneWidget);
  });
}
