import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/models/library_entity.dart';
import 'package:javit/app/modules/img_viewer/img_viewer_controller.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _AlbumsDatabase implements Database {
  bool fail = false;
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where,
    List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (fail) throw StateError('Database unavailable');
    return [
      {'root_folder': '/album', 'alias': 'Album', 'images': '["/album/a.png"]'},
      {'root_folder': '/videos', 'total_video': 1, 'images': '[]'},
    ];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  ImgViewerController build(List<String> images, {String title = ''}) {
    final controller = ImgViewerController();
    controller.images.assignAll(images);
    controller.title.value = title;
    addTearDown(controller.onClose);
    return controller;
  }

  test('album panel starts hidden, reloads on open and keeps the gallery on load failure', () async {
    final db = _AlbumsDatabase();
    Get.put<DBService>(_Service()..dbMain = db);
    addTearDown(Get.reset);
    final controller = build(['/dropped.png']);
    expect(controller.albumPanelVisible.value, isFalse);
    await controller.toggleAlbumPanel();
    expect(controller.albumPanelVisible.value, isTrue);
    expect(controller.albums.map((album) => album.rootFolder), ['/album']);
    expect(controller.images, ['/dropped.png']);
    await controller.toggleAlbumPanel();
    expect(controller.albumPanelVisible.value, isFalse);
    db.fail = true;
    await controller.toggleAlbumPanel();
    expect(controller.albumError.value, isNotEmpty);
    expect(controller.albumsLoading.value, isFalse);
    expect(controller.images, ['/dropped.png']);
    await controller.toggleAlbumPanel();
    db.fail = false;
    await controller.toggleAlbumPanel();
    expect(controller.albumError.value, isEmpty);
  });

  test('album selection resets navigation and All skips missing files and duplicate paths', () async {
    final directory = Directory.systemTemp.createTempSync('viewer_albums_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final first = File('${directory.path}/first.png')..writeAsStringSync('image');
    final second = File('${directory.path}/second.png')..writeAsStringSync('image');
    final album = Library(rootFolder: directory.path, alias: 'Album', images: [first.path, second.path]);
    final offline = Library(rootFolder: '${directory.path}/offline', images: ['${directory.path}/offline/missing.png']);
    final controller = build(['/old.png', '/other.png']);
    controller.albums.assignAll([album, Library(rootFolder: directory.path, images: [first.path]), offline]);
    controller.selectedIndex.value = 1;
    controller.videoPath.value = '/old.mp4';
    controller.zoomIn();
    controller.albumError.value = 'Previous selection failed';
    await controller.selectAlbum(album);
    expect(controller.albumError.value, isEmpty);
    expect(controller.images, [first.path, second.path]);
    expect(controller.selectedIndex.value, 0);
    expect(controller.selectedAlbumRoot.value, directory.path);
    expect(controller.videoPath.value, isEmpty);
    expect(controller.transformationController.value, Matrix4.identity());
    await controller.selectAlbum(offline);
    expect(controller.images, [first.path, second.path]);
    await controller.selectAlbum(null);
    expect(controller.images, [first.path, second.path]);
    expect(controller.selectedAlbumRoot.value, 'all');
    expect(album.images, [first.path, second.path]);
    controller.albums.clear();
    await controller.selectAlbum(null);
    expect(controller.images, isEmpty);
    expect(controller.currentImage, isEmpty);
  });

  test('latest album selection wins and closing ignores pending results', () async {
    final directory = await Directory.systemTemp.createTemp('viewer_album_race_');
    addTearDown(() => directory.delete(recursive: true));
    final image = await File('${directory.path}/image.png').writeAsString('image');
    final album = Library(rootFolder: directory.path, images: [image.path]);
    final controller = build(['/old.png']);
    final first = controller.selectAlbum(album);
    final second = controller.selectAlbum(null);
    await Future.wait([first, second]);
    expect(controller.selectedAlbumRoot.value, 'all');
    expect(controller.images, isEmpty);

    final closing = ImgViewerController()..images.assignAll(['/old.png']);
    final pending = closing.selectAlbum(album);
    closing.onClose();
    await pending;
    expect(closing.images, ['/old.png']);
  });

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
      'albumRoot': '/album',
    });
    expect(fromMap.images, ['/a.jpg', '/b.jpg']);
    expect(fromMap.selectedIndex.value, 1, reason: 'the index is clamped to the last image');
    expect(fromMap.title.value, 'Screenshots');
    expect(fromMap.videoPath.value, '/Volumes/Movies/one.mp4');
    expect(fromMap.selectedAlbumRoot.value, '/album');
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
