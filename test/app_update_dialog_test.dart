import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/modules/home/page_settings/app_update_dialog.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/utils/app_updater.dart';

void main() {
  final releaseUrl = Uri.parse('https://github.com/example/kuraku/releases/tag/v1.0.3');
  final downloadUrl = Uri.parse('https://github.com/example/kuraku/releases/download/v1.0.3/kuraku.zip');

  tearDown(Get.reset);

  Future<void> show(WidgetTester tester, {required Future<bool> Function(Uri) openLink, bool download = true, String notes = 'Fixed playback.'}) async {
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('en'),
      translations: AppTranslations(),
      home: Scaffold(body: AppUpdateDialog(
        release: AppRelease(version: '1.0.3', notes: notes, releaseUrl: releaseUrl,
          downloadUrl: download ? downloadUrl : null, assetName: download ? 'kuraku.zip' : null),
        installedVersion: '1.0.2+20261018.94',
        openLink: openLink,
      )),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the matching asset and handles browser failure without closing', (tester) async {
    final pending = Completer<bool>();
    final opened = <Uri>[];
    await show(tester, openLink: (url) { opened.add(url); return pending.future; });

    expect(find.text('Installed: 1.0.2+20261018.94'), findsOneWidget);
    expect(find.text('Fixed playback.'), findsOneWidget);
    await tester.tap(find.text('Download update'));
    await tester.pump();
    await tester.tap(find.text('View release'));
    expect(opened, [downloadUrl]);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Could not open your browser. Try again or copy this link:'), findsOneWidget);
    expect(find.text(releaseUrl.toString()), findsOneWidget);
    expect(find.byType(AppUpdateDialog), findsOneWidget);

    await tester.tap(find.text('View release'));
    await tester.pumpAndSettle();
    expect(opened, [downloadUrl, releaseUrl]);
  });

  testWidgets('uses release-page fallback and handles browser exceptions', (tester) async {
    await show(tester, download: false, notes: '', openLink: (_) async { throw StateError('browser missing'); });
    expect(find.text('Download update'), findsNothing);
    expect(find.text('No release notes were provided.'), findsOneWidget);
    await tester.tap(find.text('View release'));
    await tester.pumpAndSettle();
    expect(find.text(releaseUrl.toString()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long notes scroll and actions fit a narrow window', (tester) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, notes: List.filled(100, 'A release note.').join('\n'), openLink: (_) async => true);
    expect(find.text('Download update').hitTestable(), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated show calls open one update dialog and allow reopening after close', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    final release = AppRelease(version: '1.0.3', notes: '', releaseUrl: releaseUrl);
    final first = AppUpdateDialog.show(release: release, installedVersion: '1.0.2');
    await AppUpdateDialog.show(release: release, installedVersion: '1.0.2', automatic: true);
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Close'));
    await tester.pumpAndSettle();
    await first;
    final reopened = AppUpdateDialog.show(release: release, installedVersion: '1.0.2');
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Close'));
    await tester.pumpAndSettle();
    await reopened;
  });

  testWidgets('browser failure remains visible after scrolling a long changelog', (tester) async {
    await show(tester, notes: List.filled(100, 'A release note.').join('\n'), openLink: (_) async => false);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open your browser. Try again or copy this link:').hitTestable(), findsOneWidget);
  });
}
