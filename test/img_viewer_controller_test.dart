import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/modules/img_viewer/img_viewer_controller.dart';

void main() {
  ImgViewerController build(List<String> images, {String title = ''}) {
    final controller = ImgViewerController();
    controller.images.assignAll(images);
    controller.title.value = title;
    addTearDown(controller.onClose);
    return controller;
  }

  test('navigates through the gallery and stops at both ends', () {
    final controller = build(['/a.jpg', '/b.jpg', '/c.jpg']);

    expect(controller.canGoPrevious, isFalse);
    expect(controller.canGoNext, isTrue);
    controller.previous();
    expect(controller.selectedIndex.value, 0);

    controller.next();
    controller.next();
    expect(controller.selectedIndex.value, 2);
    expect(controller.canGoNext, isFalse);
    controller.next();
    expect(controller.selectedIndex.value, 2);

    controller.previous();
    expect(controller.selectedIndex.value, 1);
    expect(controller.currentImage, '/b.jpg');
  });

  test('selecting an image clamps the index and ignores an empty gallery', () {
    final controller = build(['/a.jpg', '/b.jpg']);

    controller.selectImage(99);
    expect(controller.selectedIndex.value, 1);
    controller.selectImage(-5);
    expect(controller.selectedIndex.value, 0);

    final empty = build([]);
    empty.selectImage(3);
    expect(empty.selectedIndex.value, 0);
    expect(empty.currentImage, '');
    expect(empty.canGoNext, isFalse);
    expect(empty.canGoPrevious, isFalse);
  });

  test('the window title uses the current file name and falls back gracefully', () {
    final controller = build(['https://cdn.example.com/img/eyan00181pl.jpg?size=large', '/Volumes/Movies/shot 01.png']);
    expect(controller.currentTitle, 'eyan00181pl.jpg');

    controller.next();
    expect(controller.currentTitle, 'shot 01.png');

    expect(build([], title: 'Screenshots').currentTitle, 'Screenshots');
    expect(build([]).currentTitle, 'Image Viewer');
    expect(build(['   '], title: 'Screenshots').currentTitle, 'Screenshots');
    expect(build(['   ']).currentTitle, 'Image Viewer');
  });

  test('rotation is remembered per image and wraps in both directions', () {
    final controller = build(['/a.jpg', '/b.jpg']);

    expect(controller.getCurrentQuarterTurns(), 0);
    controller.rotateClockwise();
    controller.rotateClockwise();
    expect(controller.getCurrentQuarterTurns(), 2);

    controller.next();
    expect(controller.getCurrentQuarterTurns(), 0, reason: 'each image keeps its own rotation');
    controller.rotateCounterClockwise();
    expect(controller.getCurrentQuarterTurns(), 3);
    controller.rotateCounterClockwise();
    expect(controller.getCurrentQuarterTurns(), 2);

    controller.previous();
    expect(controller.getCurrentQuarterTurns(), 2);
    controller.rotateClockwise();
    controller.rotateClockwise();
    expect(controller.getCurrentQuarterTurns(), 0, reason: 'four quarter turns are a full turn');

    final empty = build([]);
    empty.rotateClockwise();
    empty.rotateCounterClockwise();
    expect(empty.imageQuarterTurns, isEmpty);
    expect(empty.getCurrentQuarterTurns(), 0);
  });

  test('zooming stays inside the supported scale range and can be reset', () {
    final controller = build(['/a.jpg']);
    double scale() => controller.transformationController.value.getMaxScaleOnAxis();

    expect(scale(), closeTo(1, 1e-9));
    controller.zoomIn();
    expect(scale(), closeTo(1.2, 1e-9));
    for (var i = 0; i < 20; i++) {
      controller.zoomIn();
    }
    expect(scale(), closeTo(5, 1e-9));

    for (var i = 0; i < 40; i++) {
      controller.zoomOut();
    }
    expect(scale(), closeTo(0.6, 1e-9));

    controller.resetZoom();
    expect(controller.transformationController.value, Matrix4.identity());
  });

  test('changing the selection resets the zoom', () {
    final controller = build(['/a.jpg', '/b.jpg']);
    controller.zoomIn();
    expect(controller.transformationController.value, isNot(Matrix4.identity()));

    controller.next();
    expect(controller.transformationController.value, Matrix4.identity());
  });

  test('shuffle keeps the same images, restarts at the first one and is a no-op for a single image', () {
    final controller = build(['/a.jpg', '/b.jpg', '/c.jpg', '/d.jpg', '/e.jpg']);
    controller.selectImage(3);
    controller.zoomIn();

    controller.shuffleImages();
    expect(controller.selectedIndex.value, 0);
    expect(controller.images.toSet(), {'/a.jpg', '/b.jpg', '/c.jpg', '/d.jpg', '/e.jpg'});
    expect(controller.images, hasLength(5));
    expect(controller.transformationController.value, Matrix4.identity());

    final single = build(['/only.jpg']);
    single.shuffleImages();
    expect(single.images, ['/only.jpg']);

    final empty = build([]);
    empty.shuffleImages();
    expect(empty.images, isEmpty);
  });

  testWidgets('reads the gallery, index, title and video path from the route arguments', (tester) async {
    addTearDown(Get.reset);
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();

    Future<ImgViewerController> open(Object? arguments) async {
      unawaited(Get.to(() => const Scaffold(body: Text('Viewer')), arguments: arguments));
      await tester.pumpAndSettle();
      final controller = Get.put(ImgViewerController());
      await tester.pumpAndSettle();
      return controller;
    }

    Future<void> close() async {
      await Get.delete<ImgViewerController>();
      Get.back();
      await tester.pumpAndSettle();
    }

    final fromMap = await open({
      'images': ['/a.jpg', '  ', '/b.jpg'],
      'index': 5,
      'title': 'Screenshots',
      'videoPath': '/Volumes/Movies/one.mp4',
    });
    expect(fromMap.images, ['/a.jpg', '/b.jpg']);
    expect(fromMap.selectedIndex.value, 1, reason: 'the index is clamped to the last image');
    expect(fromMap.title.value, 'Screenshots');
    expect(fromMap.videoPath.value, '/Volumes/Movies/one.mp4');
    await close();

    final fromString = await open('/single.jpg');
    expect(fromString.images, ['/single.jpg']);
    expect(fromString.selectedIndex.value, 0);
    await close();

    final fromList = await open(['/a.jpg', '', '/b.jpg']);
    expect(fromList.images, ['/a.jpg', '/b.jpg']);
    await close();

    final fromAlias = await open({'imageUrls': '/only.jpg', 'initialIndex': 0});
    expect(fromAlias.images, ['/only.jpg']);
    expect(fromAlias.title.value, '');
    expect(fromAlias.videoPath.value, '');
    await close();

    final empty = await open(null);
    expect(empty.images, isEmpty);
    expect(empty.title.value, '');
    await close();
  });
}
