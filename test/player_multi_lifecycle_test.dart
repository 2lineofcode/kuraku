import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/player/player_multi_view.dart';
import 'package:javit/app/utils/semantic_search_service.dart';

void main() {
  testWidgets('Multi Player unmounts tiles before cleanup and only pops once', (tester) async {
    addTearDown(Get.reset);
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const Scaffold(body: Text('Home')),
    ));
    await tester.pumpAndSettle();
    unawaited(Get.to(() => const Scaffold(body: Text('Library'))));
    await tester.pumpAndSettle();

    for (final close in ['q', 'tile', 'back']) {
      unawaited(Get.to(() => const PlayerMultiView(), arguments: [Videos(videoPath: '')]));
      await tester.pumpAndSettle();
      expect(SemanticSearchService.playbackActive, isTrue);
      final tileFocus = tester.widget<Focus>(find.ancestor(
        of: find.text('Invalid video path'), matching: find.byType(Focus),
      ).first).focusNode!;
      void listener() {}

      if (close == 'q') {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      } else if (close == 'tile') {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close_rounded)).onPressed!();
      } else {
        Get.back();
      }
      // The old tile is still mounted until the next frame.
      tileFocus.addListener(listener);
      tileFocus.removeListener(listener);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsOneWidget, reason: 'Close via $close: ${Get.currentRoute}');
      expect(find.byType(PlayerMultiView), findsNothing);
      expect(SemanticSearchService.playbackActive, isFalse);
      Get.changeThemeMode(close == 'tile' ? ThemeMode.light : ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
