import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:overlayment/overlayment.dart';

import 'chat_test_database.dart';

class _Database extends ChatTestDatabase {
  List<Map<String, Object?>> result = [];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async => result;
}

class _Controller extends PlayerController {
  @override
  Future<void> changeVideo(Videos video) async { currentVideo.value = video; }
}

void main() {
  testWidgets('player playlist searches, clears, highlights and plays without overflow', (tester) async {
    final directory = Directory.systemTemp.createTempSync('kuraku-playlist-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    addTearDown(Get.reset);
    addTearDown(tester.view.reset);
    Get.put(AppSettingService()..pref = ChatTestPreferences()..appPath = directory.path);
    final database = _Database();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    final controller = _Controller();
    final thumbnailDirectory = Directory('${directory.path}/vid_thumbnail')..createSync();
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1sAAAAASUVORK5CYII=');
    for (var index = 0; index < 8; index++) {
      final file = File('${directory.path}/video-$index.mp4')..writeAsStringSync('fixture');
      File('${thumbnailDirectory.path}/video-$index.jpg').writeAsBytesSync(png);
      controller.playlist.add(Videos(id: '$index', videoCode: 'TEST-$index', title: 'Long video title ' * 8,
        videoPath: file.path, quality: '1920x1080', filesize: 1000000,
        actress: [VideoActress(nameRomaji: 'Example')], series: 'Series'));
    }
    controller.currentVideo.value = controller.playlist.last;
    controller.currentIndexPlaying.value = 7;
    for (final width in [760.0, 360.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: SizedBox.expand())));
      final panel = controller.openList();
      await tester.pumpAndSettle();
      expect(find.text('Playlist'), findsOneWidget);
      expect(find.text('TEST-7').hitTestable(), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
      expect(tester.takeException(), isNull);
      database.result = [controller.playlist.first.toJson()];
      await tester.enterText(find.byType(CupertinoSearchTextField), 'TEST-0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((widget) => widget is Text && widget.data == 'TEST-0'), findsOneWidget);
      expect(find.text('TEST-7'), findsNothing);
      await tester.enterText(find.byType(CupertinoSearchTextField), '');
      await tester.pumpAndSettle();
      expect(find.text('TEST-7').hitTestable(), findsOneWidget);
      final closing = Overlayment.dismissLast();
      await tester.pumpAndSettle();
      await closing;
      await panel;
      expect(Overlayment.count, 0);
      expect(tester.takeException(), isNull);
    }
    final panel = controller.openList();
    await tester.pumpAndSettle();
    database.result = [controller.playlist.first.toJson()];
    await tester.enterText(find.byType(CupertinoSearchTextField), 'TEST-0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) => widget is Text && widget.data == 'TEST-0'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byWidgetPredicate((widget) => widget is Text && widget.data == 'TEST-0'));
    await tester.pumpAndSettle();
    await panel;
    expect(controller.currentVideo.value.id, '0');
    expect(Overlayment.count, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
