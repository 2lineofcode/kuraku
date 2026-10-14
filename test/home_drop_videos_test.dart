import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
// DropItem.dataReader exposes this type from super_drag_and_drop's dependency.
// ignore: depend_on_referenced_packages
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

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

    for (final count in [2, 3]) {
      final items = <DropItem>[];
      for (var i = 0; i < count; i++) {
        final file = File('${directory.path}/video_$i.mp4')..createSync();
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
