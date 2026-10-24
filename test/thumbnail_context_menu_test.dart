import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
import 'package:kuraku/app/modules/widgets/widget_thumbnail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import 'icon_finder.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  int favorite = 0;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expect(where, 'video_path = ? AND is_deleted = 0');
    expect(whereArgs, ['/missing/video.mp4']);
    return [{'id': 'video-1', 'is_favorite': favorite}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('small valid FFmpeg previews are accepted while video_compress validation stays intact', (tester) async {
    final bytes = base64Decode('/9j/4AAQSkZJRgABAgAAAQABAAD//gAPTGF2YzYzLjEuMTAyAP/bAEMACAoKCwoLDQ0NDQ0NEA8QEBAQEBAQEBAQEBISEhUVFRISEhAQEhIUFBUVFxcXFRUVFRcXGRkZHh4cHCMjJCsrM//EAEsAAQEAAAAAAAAAAAAAAAAAAAAIAQEAAAAAAAAAAAAAAAAAAAAAEAEAAAAAAAAAAAAAAAAAAAAAEQEAAAAAAAAAAAAAAAAAAAAA/8AAEQgBaADKAwEiAAIRAAMRAP/aAAwDAQACEQMRAD8An8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAH/9k=');
    expect(bytes.length, lessThanOrEqualTo(1000));
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        expect([frame.image.width, frame.image.height], [202, 360]);
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    });
    expect(isUsableThumbnailPreview(bytes, fromFfmpeg: true), isTrue);
    expect(isUsableThumbnailPreview(bytes, fromFfmpeg: false), isFalse);
    expect(isUsableThumbnailPreview(Uint8List(0), fromFfmpeg: true), isFalse);
    expect(isUsableThumbnailPreview(null, fromFfmpeg: true), isFalse);
  });

  testWidgets('network error icon stays centered in the actual thumbnail frame', (tester) async {
    final directory = Directory.systemTemp.createTempSync('kuraku-thumbnail-test-');
    final previousFactory = databaseFactoryOrNull;
    databaseFactory = databaseFactorySqflitePlugin;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (call) async {
      switch (call.method) {
        case 'getDatabasesPath': return directory.path;
        case 'openDatabase': return {'id': 1};
        case 'query': return (call.arguments as Map)['sql'] == 'PRAGMA user_version' ? [{'user_version': 3}] : <Map<String, Object?>>[];
        case 'batch': return [];
        default: return null;
      }
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.irondash.engine_context'), (_) => Completer<Object?>().future);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => directory.path);
    Get.put(AppSettingService()..appPath = directory.path);
    addTearDown(() async {
      Get.reset();
      databaseFactory = previousFactory;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), null);
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.irondash.engine_context'), null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    });
    Object? sharedCache;
    for (final prefix in [1.0, 1.9]) {
      await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
        width: 200, height: 200,
        child: ExThumbnail(key: ValueKey(prefix), imageUrl: 'invalid-url', withProxy: false, width: 300, height: 200, prefix: prefix),
      ))));
      for (var attempt = 0; attempt < 20 && findHugeIcon(HugeIcons.strokeRoundedImage01).evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      final cache = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage)).cacheManager!;
      if (sharedCache != null) expect(cache, same(sharedCache));
      sharedCache = cache;
      expect((cache as CacheManager).config.maxNrOfCacheObjects, 100000000);
      expect(cache.config.stalePeriod, const Duration(days: 365));
      expect(tester.getCenter(findHugeIcon(HugeIcons.strokeRoundedImage01)), tester.getCenter(find.byType(ExThumbnail)));
      expect(tester.getSize(findHugeIcon(HugeIcons.strokeRoundedImage01)), const Size.square(AppStyle.emptyIconSize));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('thumbnail placeholder icons fit small frames and keep the shared default', (tester) async {
    addTearDown(Get.reset);
    for (final dimensions in [(20.0, 16.0, null, 16.0), (80.0, 64.0, null, AppStyle.emptyIconSize),
      (80.0, 64.0, AppStyle.largeIconSize, AppStyle.largeIconSize), (300.0, 200.0, null, AppStyle.emptyIconSize), (0.0, 0.0, null, 0.0)]) {
      await tester.pumpWidget(MaterialApp(home: Center(child: ExThumbnail(
        key: ValueKey(dimensions), imageUrl: '', width: dimensions.$1, height: dimensions.$2, iconSize: dimensions.$3,
      ))));
      await tester.pumpAndSettle();
      expect(tester.widget<HugeIcon>(findHugeIcon(HugeIcons.strokeRoundedImage01)).size, dimensions.$4);
      expect(tester.getSize(findHugeIcon(HugeIcons.strokeRoundedImage01)), Size.square(dimensions.$4));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('thumbnail native menu keeps local and online actions and primary taps', (tester) async {
    final database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
    addTearDown(Get.reset);
    final notifier = ValueNotifier<scm.MenuResult?>(null);
    addTearDown(notifier.dispose);
    final request = scm.MenuRequest(onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero);
    var taps = 0;

    Future<void> show(String path) async {
      await tester.pumpWidget(MaterialApp(home: Center(child: GestureDetector(
        onTap: () => taps++,
        child: ExThumbnail(imageUrl: '', videoPath: path, position: 10, width: 120, height: 160),
      ))));
      await tester.pumpAndSettle();
    }

    Future<List<String?>> titles() async {
      final widget = tester.widget<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget));
      final menu = await widget.menuProvider(request);
      return menu!.children.map((item) => item is scm.MenuSeparator ? '---' : item.title).toList();
    }

    await show('/missing/video.mp4');
    expect(await titles(), ['Play', 'Add to Panel Cart', '---', 'Add To Favorite', 'Add to Playlist', '---', 'Edit Metadata', 'Refresh Metadata', 'Open File Path', 'Properties']);
    database.favorite = 1;
    expect((await titles())[3], 'Remove From Favorite');
    await tester.tap(find.byType(ExThumbnail));
    expect(taps, 1);

    await show('');
    expect(await titles(), ['Download', 'Open Screenshot', 'Open Trailer']);
    final provider = tester.widget<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget)).menuProvider;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await provider(request), isNull);
    expect(tester.takeException(), isNull);
  });
}
