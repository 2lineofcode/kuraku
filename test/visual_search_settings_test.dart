import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_view.dart';
import 'package:javit/app/utils/semantic_search_service.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  void writeInMemory(String key, dynamic value) { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> onRefreshStorage() async {}
}

void main() {
  testWidgets('Visual settings fit narrow windows and expose progress and cancellation', (tester) async {
    Get.testMode = true;
    Get.put<AppSettingService>(AppSettingService()..pref = _Preferences());
    final controller = Get.put<PageSettingsController>(_Settings());
    addTearDown(Get.reset);
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const fontPath = String.fromEnvironment('VISUAL_QA_FONT');
    if (fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('VisualQA');
        loader.addFont(File(fontPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      });
    }
    final boundary = GlobalKey();
    await tester.pumpWidget(GetMaterialApp(themeMode: AppPref.getAppTheme().resolve(), darkTheme: ThemeData.dark(), theme: ThemeData.light().copyWith(textTheme: ThemeData.light().textTheme.apply(fontFamily: fontPath.isEmpty ? null : 'VisualQA')), home: Scaffold(
      body: RepaintBoundary(key: boundary, child: SingleChildScrollView(
        child: const PageSettingsView().buildVisualSearchSettings(),
      )),
    )));
    expect(controller.appTheme.value, AppTheme.dark);
    expect(Get.isDarkMode, isTrue);
    await controller.setTheme(AppTheme.light);
    await tester.pumpAndSettle();
    expect(Get.isDarkMode, isFalse);
    expect(AppPref.getAppTheme(), AppTheme.light);
    final recreated = _Settings();
    expect(recreated.appTheme.value, AppTheme.light);
    recreated.onClose();
    await controller.setTheme(AppTheme.dark);
    await tester.pumpAndSettle();
    expect(Get.isDarkMode, isTrue);
    expect(find.text('Set up'), findsOneWidget);
    HomePanelAppLog.appLogRuntime.clear();
    SemanticSearchService.beginPlayback();
    try {
      await tester.tap(find.text('Set up'));
      await tester.pump();
      expect(find.text('Close the player before setup.'), findsOneWidget);
      expect(HomePanelAppLog.appLogRuntime.any((entry) => (entry.content ?? '').contains('setup blocked')), isTrue);
      expect(controller.semanticBusy.value, isFalse);
    } finally {
      SemanticSearchService.endPlayback();
    }
    await tester.tap(find.byTooltip('Visual Search options'));
    await tester.pumpAndSettle();
    expect(find.text('Repair setup'), findsOneWidget);
    await tester.tapAt(const Offset(310, 950));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    controller.semanticReady.value = true;
    controller.semanticBusy.value = true;
    controller.semanticProgress.value = .5;
    controller.semanticEmbeddingCount.value = 20;
    controller.semanticMissingCount.value = 20;
    controller.semanticStatus.value = '20 / 40 checked · 20 indexed · 0 skipped';
    await tester.pumpAndSettle();
    expect(find.text('20 indexed • 20 pending'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .5);
    expect(tester.widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>)).enabled, isFalse);
    expect(find.text('Stop'), findsOneWidget);
    expect(tester.takeException(), isNull);
    const screenshot = String.fromEnvironment('VISUAL_QA_PATH');
    if (screenshot.isNotEmpty) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Stopping… Completed work will be kept.'), findsOneWidget);
    controller.semanticBusy.value = false;
    controller.semanticMissingCount.value = 0;
    controller.semanticStatus.value = 'Finished · 20 indexed · 0 skipped.';
    await tester.pump();
    expect(find.text('20 indexed • 0 pending'), findsOneWidget);
    expect(find.text('Index'), findsOneWidget);
    expect(find.text(controller.semanticStatus.value), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.tap(find.byTooltip('Visual Search options'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh status'), findsOneWidget);
    expect(find.text('Rebuild frames & index'), findsOneWidget);
  });
}
