import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_library.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_file_drag.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_tab.dart';
import 'package:sqflite/sqflite.dart';

class _Tab extends PageSearchTab {
  _Tab() : super(1);
  Map<String, String>? moves;
  @override
  Future<void> applyFileMoves(Map<String, Videos> files, Map<String, String> paths, List<String> missing) async {
    moves = paths;
    expect(missing, isEmpty);
  }
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database, Transaction {
  final moves = <List<Object?>>[];
  final libraries = <Map<String, Object?>>[
    {'id': 'source', 'root_folder': '/source', 'videos': jsonEncode(['/source/a.mp4', '/source/missing.mp4'])},
    {'id': 'target', 'root_folder': '/target', 'videos': '[]'},
  ];
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) => action(this);
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async => table == 'library' ? libraries : [];
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    expect(sql, contains('WHERE video_path = ?'));
    moves.add(arguments!);
    return 1;
  }
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 1;
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'library');
    libraries.firstWhere((row) => row['id'] == whereArgs!.single).addAll(values);
    return 1;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final operation in ['move', 'copy', 'cancel']) {
    testWidgets('file drag exports the entire selection and handles $operation', (tester) async {
      final folder = Directory.systemTemp.createTempSync('kuraku-drag-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final files = [File('${folder.path}/one #1.mp4')..writeAsStringSync('one'), File('${folder.path}/日本語.mp4')..writeAsStringSync('two')];
      final tab = _Tab();
      addTearDown(tab.dispose);
      final videos = files.map((file) => Videos(videoPath: file.path)).toList();
      tab.showResults('Files', videos);
      final widget = SearchFileDrag(controller: tab, video: videos.first, child: const SizedBox());
      expect(widget.canDrag, isFalse);
      tab.selectedVideos.addAll(videos);
      expect(widget.canDrag, isTrue);
      final destinations = <String, String>{};
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SearchFileDrag.channel, (call) async {
        if (call.method == 'release') return null;
        if (call.method == 'bookmark') {
          expect(call.arguments, files.map((file) => file.path).toList());
          return {for (final file in files) file.path: [1]};
        }
        if (call.method == 'drag') {
          expect(call.arguments, files.map((file) => file.path).toList());
          expect(HomePanelLibrary.fileDragInProgress, isTrue);
          tab.selectedVideos.clear();
          if (operation == 'move') {
            for (final file in files) {
              final target = '${file.path}.moved';
              file.renameSync(target);
              destinations[file.path] = target;
            }
          }
          return operation;
        }
        expect(call.method, 'resolve');
        return destinations;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SearchFileDrag.channel, null));
      await tester.runAsync(widget.startDrag);
      expect(tab.moves, operation == 'move' ? destinations : operation == 'copy' ? isEmpty : isNull);
      expect(HomePanelLibrary.fileDragInProgress, isFalse);
      expect(widget.canDrag, isFalse);
    });
  }

  test('file moves preserve video identity and update library membership after the tab closes', () async {
    final database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
    addTearDown(Get.reset);
    final tab = PageSearchTab(1);
    addTearDown(tab.dispose);
    final video = Videos(id: 'keep-id', videoPath: '/source/a.mp4', isFavorite: 1, viewCount: 9);
    tab.close();
    await tab.applyFileMoves({'/source/a.mp4': video}, {'/source/a.mp4': '/target/a.mp4'}, ['/source/missing.mp4']);
    expect([video.id, video.isFavorite, video.viewCount], ['keep-id', 1, 9]);
    expect([video.videoPath, video.rootPath], ['/target/a.mp4', '/target']);
    expect(database.moves.single.take(2), ['/target/a.mp4', '/target']);
    expect(database.moves.single.last, '/source/a.mp4');
    expect(jsonDecode(database.libraries.first['videos'] as String), isEmpty);
    expect(jsonDecode(database.libraries.last['videos'] as String), ['/target/a.mp4']);
  });
}
