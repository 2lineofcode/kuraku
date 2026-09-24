import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:javit/app/modules/home/page_tools/page_tools_view.dart';

class _Tools extends PageToolsController {
  final pending = <Videos>[Videos(id: 'one', videoPath: '/one.mp4'), Videos(id: 'two', videoPath: '/two.mp4')];
  final saved = <String>[];
  Completer<String?>? probe;
  int loads = 0;
  bool failFirst = false;

  @override
  Future<void> onRefresh() async {}
  @override
  Future<List<Videos>> loadMissingQuality() async { loads++; return pending.toList(); }
  @override
  Future<String?> extractQuality(String path) async {
    if (failFirst && path == '/one.mp4') throw StateError('Unreadable file');
    return probe == null ? '1920x1080' : probe!.future;
  }
  @override
  Future<int> saveMissingQuality(Videos video, String quality) async {
    saved.add(video.id!);
    pending.removeWhere((item) => item.id == video.id);
    return 1;
  }
  @override
  Future<void> checkIsHasDataNotScanned() async { missingQualityCount.value = pending.length; }
  @override
  Future<void> getTopLargeFileSize({String mode = 'all'}) async {}
}

void main() {
  test('Scan rejects duplicate starts, cancels stale results and resumes missing items', () async {
    final controller = _Tools()..probe = Completer<String?>();
    final scan = controller.scanAndUpdateDBVideoRes();
    await Future<void>.delayed(Duration.zero);
    await controller.scanAndUpdateDBVideoRes();
    expect(controller.loads, 1);
    controller.stopQualityScan();
    controller.probe!.complete('1920x1080');
    await scan;
    expect(controller.saved, isEmpty);
    expect(controller.missingQualityCount.value, 2);
    expect(controller.qualityScanRunning.value, isFalse);
    controller.probe = null;
    controller.failFirst = true;
    await controller.scanAndUpdateDBVideoRes();
    expect(controller.saved, ['two']);
    expect(controller.qualityScanSkipped.value, 1);
    expect(controller.missingQualityCount.value, 1);
    controller.failFirst = false;
    await controller.scanAndUpdateDBVideoRes();
    expect(controller.saved, ['two', 'one']);
    expect(controller.missingQualityCount.value, 0);
    controller.onClose();
  });

  testWidgets('Resolution progress stays usable in a narrow empty library', (tester) async {
    Get.testMode = true;
    final controller = Get.put<PageToolsController>(_Tools());
    addTearDown(Get.reset);
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.missingQualityCount.value = 2;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: const PageToolsView().buildResolutionScan())));
    expect(find.text('Scan (2)'), findsOneWidget);
    controller.qualityScanRunning.value = true;
    controller.qualityScanTotal.value = 2;
    controller.qualityScanChecked.value = 1;
    controller.qualityScanUpdated.value = 1;
    await tester.pump();
    expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, .5);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Stopping…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.qualityScanRunning.value = false;
    controller.missingQualityCount.value = 0;
    await tester.pump();
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    controller.qualityScanStatus.value = 'Scan failed. Saved results are kept. Please retry.';
    await tester.pump();
    expect(find.byTooltip(controller.qualityScanStatus.value), findsOneWidget);
    expect(find.text('Scan (0)'), findsOneWidget);
  });
}
