import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
// DropItem.dataReader exposes this type from super_drag_and_drop's dependency.
// ignore: depend_on_referenced_packages
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'chat_test_database.dart';

class _Database extends ChatTestDatabase {
  final videos = <Map<String, Object?>>[];
  final paths = <String>[];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (table != 'videos') return super.query(table, where: where, whereArgs: whereArgs);
    expect(where, anyOf('video_path = ? AND is_deleted = 0', 'video_path = ? COLLATE NOCASE AND is_deleted = 0'));
    final path = whereArgs!.single as String;
    paths.add(path);
    return videos.where((video) => video['video_path'] == path && video['is_deleted'] != 1).toList();
  }
}

class _RecordingPlayer extends GetxController implements PlayerController {
  final opened = <Videos>[];

  @override
  Future<void> onClose() async { super.onClose(); }

  @override
  Future<bool> startPlayback(Videos video, {List<Videos>? playlist}) async {
    opened.add(video);
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reader implements DataReader {
  _Reader(this.uri);
  final Uri uri;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getValue) {
      Function.apply(invocation.positionalArguments[1] as Function, [uri]);
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _Item extends Fake with Diagnosticable implements DropItem {
  _Item(this.path);
  final String path;

  @override
  DataReader get dataReader => _Reader(Uri.file(path));
}

class _Session extends Fake with Diagnosticable implements DropSession {
  _Session(this.items);

  @override
  final List<DropItem> items;
}

void main() {
  late _Database database;

  setUp(() {
    database = _Database();
    Get.put<AppSettingService>(AppSettingService()..pref = ChatTestPreferences());
    Get.put<DBService>(ChatTestService()..dbMain = database);
  });

  tearDown(Get.reset);

  for (final source in ['Home', 'Player']) {
    testWidgets('$source drop reuses tracked metadata and preserves periods in external titles', (tester) async {
      final directory = Directory.systemTemp.createTempSync('kuraku_drop_identity_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final home = HomeController();
      addTearDown(() { home.tecTopNavSearch.dispose(); home.fnTopNavSearch.dispose(); });
      final player = PlayerController();
      final recording = Get.put<PlayerController>(_RecordingPlayer()) as _RecordingPlayer;
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('Home'))));
      final trackedFile = File('${directory.path}/tracked.part.1.MKV')..writeAsStringSync('fixture');
      final externalFile = File('${directory.path}/external.part.2.webm')..writeAsStringSync('fixture');
      final stored = Videos(id: 'database-id', videoPath: trackedFile.path, title: 'Library title',
        actress: [VideoActress(id: 7, nameRomaji: 'Library Cast')], isFavorite: 1, viewCount: 12);
      database.videos.add(stored.toJson());
      database.videos.add((Videos(id: 'deleted-id', videoPath: externalFile.path, title: 'Deleted title').toJson())..['is_deleted'] = 1);

      for (final path in [trackedFile.path, externalFile.path]) {
        final expectedOpened = recording.opened.length + 1;
        await tester.runAsync(() async {
          final event = PerformDropEvent(session: _Session([_Item(path)]),
            position: DropPosition(local: Offset.zero, global: Offset.zero), acceptedOperation: DropOperation.copy);
          if (source == 'Home') {
            await home.onDropEvent(event);
          } else {
            await player.onDropEvent(event);
          }
          for (var attempt = 0; attempt < 50 && recording.opened.length < expectedOpened; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
      }
      expect(recording.opened, hasLength(2));
      expect(recording.opened.first.id, 'database-id');
      expect(recording.opened.first.title, 'Library title');
      expect(recording.opened.first.actress!.single.nameRomaji, 'Library Cast');
      expect(recording.opened.first.isFavorite, 1);
      expect(recording.opened.first.viewCount, 12);
      expect(recording.opened.last.id, isNot(anyOf('database-id', 'deleted-id', isEmpty)));
      expect(recording.opened.last.videoPath, externalFile.path);
      expect(recording.opened.last.title, 'external.part.2');
      expect(database.paths, [trackedFile.path, externalFile.path, if (Platform.isWindows) externalFile.path]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('multiple dropped videos ask for player mode and can cancel', (tester) async {
    final directory = Directory.systemTemp.createTempSync('kuraku_drop_test_');
    final home = HomeController();
    addTearDown(() {
      home.tecTopNavSearch.dispose();
      home.fnTopNavSearch.dispose();
      directory.deleteSync(recursive: true);
      Get.reset();
    });
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: Text('Home'))));

    for (final extensions in [
      ['mp4', 'mp4'],
      ['mp4', 'mp4', 'mp4'],
      ['MKV', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'],
    ]) {
      final items = <DropItem>[];
      for (var i = 0; i < extensions.length; i++) {
        final file = File('${directory.path}/video_$i.${extensions[i]}')..createSync();
        items.add(_Item(file.path));
      }
      await tester.runAsync(() async {
        await home.onDropEvent(PerformDropEvent(
          session: _Session(items),
          position: DropPosition(local: Offset.zero, global: Offset.zero),
          acceptedOperation: DropOperation.copy,
        ));
      });
      for (var attempt = 0; attempt < 50 && find.text('Single Player').evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Single Player'), findsOneWidget);
      expect(find.text('Multi Player'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Open Videos'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
