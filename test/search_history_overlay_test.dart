import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/modules/widgets/widget_search_history.dart';

void main() {
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
