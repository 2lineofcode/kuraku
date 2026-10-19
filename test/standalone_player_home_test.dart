import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/standalone_player_history.dart';
import 'package:kuraku/app/modules/standalone_player/standalone_player_controller.dart';
import 'package:kuraku/app/modules/standalone_player/standalone_player_translations.dart';
import 'package:kuraku/app/modules/standalone_player/standalone_player_view.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Controller extends StandalonePlayerController {
  int picks = 0;
  StandaloneRecent? opened;
  @override
  Future<void> pickVideos() async { picks++; }
  @override
  Future<void> openRecent(StandaloneRecent item) async { opened = item; }
  @override
  Future<void> removeRecent([String? path]) async {
    if (path == null) { recentFiles.clear(); }
    else { recentFiles.removeWhere((item) => item.path == path); }
  }
}

void main() {
  testWidgets('standalone home opens, resumes and removes recent files in a compact layout', (tester) async {
    Get.testMode = true;
    PackageInfo.setMockInitialValues(appName: 'KuraKu', packageName: 'kuraku', version: '1.0.3', buildNumber: '101', buildSignature: '');
    final controller = _Controller()..onStart();
    const first = StandaloneRecent(path: '/Volumes/Movies/A long movie name (2026) 日本語.mp4', position: Duration(minutes: 8, seconds: 47));
    const second = StandaloneRecent(path: '/Movies/Second movie.mkv');
    controller.recentFiles.assignAll([first, second]);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(560, 450));
    await tester.pumpWidget(GetMaterialApp(
      translations: StandalonePlayerTranslations(), locale: const Locale('en'),
      theme: ThemeData.light(), darkTheme: ThemeData.dark(), themeMode: ThemeMode.dark,
      home: StandalonePlayerView(controller: controller),
    ));
    await tester.pumpAndSettle();
    expect(find.text('KuraKu'), findsOneWidget);
    expect(find.text('v1.0.3+101'), findsOneWidget);
    expect(find.text('08:47'), findsOneWidget);
    expect(find.text('Resume A long movie name (2026) 日本語.mp4'), findsOneWidget);
    await tester.tap(find.text('Open files'));
    expect(controller.picks, 1);
    await tester.tap(find.text('Resume A long movie name (2026) 日本語.mp4'));
    expect(controller.opened, same(first));
    await tester.binding.setSurfaceSize(const Size(360, 480));
    await tester.pumpAndSettle();
    expect(find.text('Open files').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Remove from recent').at(1));
    await tester.pumpAndSettle();
    expect(controller.recentFiles, [first]);
    await tester.tap(find.text('Clear recent'));
    await tester.pumpAndSettle();
    expect(controller.recentFiles, isEmpty);
    expect(find.text('Recent files'), findsNothing);
    expect(find.text('Drop videos here'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.onClose();
    Get.reset();
    Get.clearTranslations();
    Get.locale = null;
  });
}
