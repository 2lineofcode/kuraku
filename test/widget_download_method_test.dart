import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/modules/widgets/widget_download_method.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('only arrow opens engines while the row uses the default', (tester) async {
    ({String method, String? engine})? selected;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(
      body: Center(child: DownloadMethodDialog(defaultEngine: 'MISSAV', onSelected: (value) => selected = value)),
    )));
    expect(find.text('Downie'), Platform.isMacOS ? findsOneWidget : findsNothing);
    expect(tester.getTopLeft(find.text('Native')).dy, lessThan(tester.getTopLeft(find.text('Just Open URL')).dy));
    for (final option in {'Native': 'native', if (Platform.isMacOS) 'Downie': 'downie', 'Just Open URL': 'url'}.entries) {
      selected = null;
      await tester.tap(find.text(option.key));
      await tester.pumpAndSettle();
      expect(selected, (method: option.value, engine: 'MISSAV'));
      expect(find.text('JAVGURU'), findsNothing);
      selected = null;
      await tester.tap(find.byKey(ValueKey('download-engine-${option.value}')));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      for (final engine in AppPref.searchEngines) {
        expect(find.text(engine), findsOneWidget);
      }
      await tester.tap(find.text('JAVGURU'));
      await tester.pumpAndSettle();
      expect(selected, (method: option.value, engine: 'JAVGURU'));
    }
    await tester.tap(find.text('Cancel'));
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source URL stays available and dismissing the menu does not select', (tester) async {
    ({String method, String? engine})? selected;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(
      body: Center(child: DownloadMethodDialog(defaultEngine: 'NJAV', hasSourceUrl: true, onSelected: (value) => selected = value)),
    )));
    await tester.tap(find.text('Native'));
    await tester.pumpAndSettle();
    expect(selected, (method: 'native', engine: null));
    expect(find.text('Original URL'), findsNothing);
    selected = null;
    await tester.tap(find.byKey(const ValueKey('download-engine-native')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.byKey(const ValueKey('download-engine-url')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original URL'));
    await tester.pumpAndSettle();
    expect(selected, (method: 'url', engine: null));
    expect(tester.takeException(), isNull);
  });
}
