import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:javit/app/modules/widgets/widget_thumbnail.dart';
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
    expect(where, 'video_path = ?');
    expect(whereArgs, ['/missing/video.mp4']);
    return [{'id': 'video-1', 'is_favorite': favorite}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
    expect(await titles(), ['Play', 'Add to Panel Cart', '---', 'Add To Favorite', 'Add to Playlist', '---', 'Edit Metadata', 'Refresh Metadata', 'Open File Path']);
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
