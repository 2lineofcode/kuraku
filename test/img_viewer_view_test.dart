import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/modules/img_viewer/img_viewer_controller.dart';
import 'package:javit/app/modules/img_viewer/img_viewer_view.dart';
import 'package:sqflite/sqflite.dart';

import 'icon_finder.dart';

/// A 1x1 PNG, enough for `Image.file` to take the real file branch.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _AlbumsDatabase implements Database {
  final rows = <Map<String, Object?>>[];
  int queries = 0;
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where,
    List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    queries++;
    return rows;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  testWidgets('Cmd+B toggles the hidden album panel and album clicks retain image navigation', (tester) async {
    final nested = Directory('${directory.path}/nested')..createSync();
    final other = File('${nested.path}/other.png')..writeAsBytesSync(base64Decode(_png));
    final db = _AlbumsDatabase()..rows.addAll([
      {'root_folder': directory.path, 'alias': 'Album A', 'images': jsonEncode(images.take(2).toList())},
      {'root_folder': nested.path, 'alias': 'Album B', 'images': jsonEncode([other.path])},
      {'root_folder': '/missing/album', 'alias': 'Offline album', 'images': '["/missing/album/one.png"]'},
    ]);
    Get.put<DBService>(_Service()..dbMain = db);
    await pump(tester);
    expect(find.text('Image Albums'), findsNothing);
    expect(db.queries, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(controller.albumPanelVisible.value, isFalse);
    Future<void> toggle() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }
    Future<void> selectAlbum(String label) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }
    await toggle();
    expect(find.text('Image Albums'), findsOneWidget);
    expect(tester.getTopLeft(find.text('All')).dy, lessThan(tester.getTopLeft(find.text('Album A')).dy));
    expect(find.text('Unavailable'), findsOneWidget);
    controller.selectImage(2);
    controller.zoomIn();
    await selectAlbum('Album B');
    expect(controller.images, [other.path]);
    expect(controller.selectedIndex.value, 0);
    expect(controller.transformationController.value, Matrix4.identity());
    await selectAlbum('All');
    expect(controller.images, [images[0], images[1], other.path]);
    expect(controller.selectedAlbumRoot.value, 'all');
    await tester.tap(find.text('Offline album'));
    await tester.pumpAndSettle();
    expect(controller.images, [images[0], images[1], other.path]);
    await selectAlbum('Album A');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.currentImage, images[1]);
    await toggle();
    expect(find.text('Image Albums'), findsNothing);
    expect(controller.currentImage, images[1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the file name, the counter and one thumbnail per image', (tester) async {
    await pump(tester);

    expect(find.text('first.png  1/3'), findsOneWidget);
    expect(find.descendant(of: find.byType(ListView), matching: find.byType(GestureDetector)), findsNWidgets(3));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('No image found'), findsNothing);
  });

  testWidgets('album toolbar button toggles the panel and title follows both themes', (tester) async {
    Get.put<DBService>(_Service()..dbMain = _AlbumsDatabase());
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      Get.changeTheme(theme);
      await tester.pumpWidget(GetMaterialApp(theme: theme, home: const ImgViewerView()));
      await tester.pumpAndSettle();
      final title = find.text('first.png  1/3');
      final rendered = tester.widget<RichText>(find.descendant(of: title, matching: find.byType(RichText)));
      expect(rendered.text.style?.color, theme.colorScheme.onSurface);
      final button = find.byTooltip('Image Albums (⌘B)');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.albumPanelVisible.value, isTrue);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.albumPanelVisible.value, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('only thumbnails use a bounded decode and the main image keeps its original provider', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester);
    final main = tester.widget<Image>(find.descendant(of: find.byType(InteractiveViewer), matching: find.byType(Image)));
    expect(main.image, isA<FileImage>());
    expect((main.image as FileImage).file.path, images.first);
    final thumbnails = tester.widgetList<Image>(find.descendant(of: find.byType(ListView), matching: find.byType(Image)));
    expect(thumbnails, hasLength(3));
    for (final thumbnail in thumbnails) {
      final provider = thumbnail.image as ResizeImage;
      expect(provider.width, 232);
      expect(provider.height, 136);
      expect(provider.policy, ResizeImagePolicy.fit);
      expect(provider.allowUpscaling, isFalse);
    }
  });


  testWidgets('missing local images show a placeholder without requesting a remote thumbnail', (tester) async {
    controller.images.assignAll(['${directory.path}/missing.png']);
    await pump(tester);
    expect(find.byType(Image), findsNothing);
    expect(findHugeIcon(HugeIcons.strokeRoundedImage01), findsNWidgets(2));
    expect(tester.takeException(), isNull);
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

    unawaited(Get.to(() => const ImgViewerView()));
    await tester.pumpAndSettle();
    expect(find.byType(ImgViewerView), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();

    expect(find.byType(ImgViewerView), findsNothing);
    expect(find.text('Gallery'), findsOneWidget);
  });
}
