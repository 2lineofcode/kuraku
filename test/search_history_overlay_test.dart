import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/player/player_multi_view.dart';
import 'package:javit/app/modules/widgets/widget_search_history.dart';
import 'package:javit/app/modules/widgets/widget_search_suggestions_overlay.dart';

void main() {
  testWidgets('Covered search overlay survives resize, Settings action and Multi Player exit', (tester) async {
    final home = HomeController();
    addTearDown(() {
      home.fnTopNavSearch.dispose();
      home.tecTopNavSearch.dispose();
      tester.view.reset();
      Get.reset();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: Obx(() {
      if (home.currentMenuSelected.value == kMenuSetting) return const Text('Settings');
      return SizedBox(width: 400, child: Column(children: [
        const CupertinoTextField(),
        SearchHistoryDropdown(suggestions: const [], selectedIndex: -1,
          onPick: (_) {}, onDelete: (_) {}, onClear: () async {}),
      ]));
    }))));
    await tester.pumpAndSettle();
    unawaited(Get.to(() => const PlayerMultiView(), arguments: [Videos(videoPath: '')]));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(700, 700);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(SearchSuggestionsOverlay, skipOffstage: false),
      matching: find.byType(OverlayPortal, skipOffstage: false), skipOffstage: false), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(SearchSuggestionsOverlay),
      matching: find.byType(OverlayPortal)), findsOneWidget);
    unawaited(Get.to(() => const PlayerMultiView(), arguments: [Videos(videoPath: '')]));
    await tester.pumpAndSettle();
    // Cmd+, runs this action even while a player route covers Home.
    await home.onMenuChange(kMenuSetting);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(PlayerMultiView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('History overlays results, follows field width and disappears with its owner', (tester) async {
    var suggestions = <String>[];
    var width = 400.0;
    String? picked;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return SizedBox(width: width, child: Column(children: [
          const CupertinoTextField(),
          SearchHistoryDropdown(
            suggestions: suggestions,
            selectedIndex: -1,
            onPick: (query) => picked = query,
            onDelete: (_) {},
            onClear: () async {},
          ),
          const Text('Results'),
        ]));
      },
    ))));
    final resultsPosition = tester.getTopLeft(find.text('Results')).dy;
    rebuild(() => suggestions = ['Alpha', 'Beta']);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Results')).dy, resultsPosition);
    expect(tester.getSize(find.byType(SearchHistoryDropdown)).height, 0);
    expect(tester.getSize(find.byType(ListView)).width, closeTo(width, 1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Remove from history').first));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Remove from history'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    expect(picked, 'Alpha');
    rebuild(() => width = 280);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ListView)).width, closeTo(width, 1));
    rebuild(() => suggestions = []);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(tester.getTopLeft(find.text('Results')).dy, resultsPosition);
    rebuild(() => suggestions = ['Beta']);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.text('Beta'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
