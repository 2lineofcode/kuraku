import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/modules/home/page_settings/app_update_dialog.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:kuraku/app/utils/app_updater.dart';
import 'package:toastification/toastification.dart';

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  Future<AppRelease?> Function() fetch = () async => null;
  int checks = 0;
  int dialogs = 0;

  @override
  Future<AppRelease?> fetchAppUpdate() { checks++; return fetch(); }
  @override
  Future<void> showAppUpdate({bool automatic = false}) async { dialogs++; }
}

void main() {
  late _Settings controller;
  final release = AppRelease(version: '1.0.3', notes: 'Fixes',
    releaseUrl: Uri.parse('https://github.com/2lineofcode/kuraku/releases/tag/v1.0.3'));

  setUp(() {
    Get.testMode = true;
    AppUpdater.latestRelease = null;
    Get.put<AppSettingService>(AppSettingService()..pref = _Preferences());
    controller = _Settings();
  });
  tearDown(() {
    if (!controller.isClosed) controller.onDelete();
    Get.reset();
  });

  test('manual check prevents duplicate requests and keeps an available update', () async {
    final pending = Completer<AppRelease?>();
    controller.fetch = () => pending.future;
    expect(controller.checks, 0);
    final check = controller.checkForAppUpdate();
    expect(controller.appUpdateChecking.value, isTrue);
    await controller.checkForAppUpdate();
    expect(controller.checks, 1);
    pending.complete(release);
    await check;
    expect(controller.appUpdateChecking.value, isFalse);
    expect(controller.availableAppUpdate.value, same(release));
    expect(controller.appUpdateStatus.value, 'Update available: 1.0.3');
    expect(controller.appUpdateError.value, isFalse);
    expect(controller.dialogs, 1);
  });

  test('Settings can read the startup result without initializing its controller', () {
    AppUpdater.latestRelease = release;
    var created = false;
    Get.lazyPut<PageSettingsController>(() { created = true; return _Settings(); });
    expect(Get.isPrepared<PageSettingsController>(), isTrue);
    expect(created, isFalse);
    final settings = _Settings();
    expect(settings.availableAppUpdate.value, same(release));
    expect(created, isFalse);
    settings.onDelete();
  });

  test('startup offers a known update without fetching it again or repeating the dialog', () async {
    await controller.offerStartupAppUpdate(release);
    expect(controller.availableAppUpdate.value, same(release));
    expect(controller.appUpdateStatus.value, 'Update available: 1.0.3');
    expect(controller.checks, 0);
    expect(controller.dialogs, 1);
    await controller.offerStartupAppUpdate(release);
    expect(controller.dialogs, 1);
  });

  test('startup does not repeat an update already offered by a manual check', () async {
    controller.fetch = () async => release;
    await controller.checkForAppUpdate();
    await controller.offerStartupAppUpdate(AppRelease(version: release.version, notes: release.notes, releaseUrl: release.releaseUrl));
    expect(controller.dialogs, 1);
  });

  testWidgets('startup preserves an existing dialog and keeps the update in Settings', (tester) async {
    final settings = PageSettingsController();
    addTearDown(() => settings.onDelete());
    await tester.pumpWidget(ToastificationWrapper(child: GetMaterialApp(home: const Scaffold())));
    unawaited(Get.dialog<void>(const AlertDialog(content: Text('Database setup'))));
    await tester.pumpAndSettle();
    await settings.offerStartupAppUpdate(release);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Database setup'), findsOneWidget);
    expect(find.text('KuraKu 1.0.3 is available. Open Settings to view the update.'), findsOneWidget);
    expect(settings.availableAppUpdate.value, same(release));
    expect(find.byType(AppUpdateDialog), findsNothing);
    toastification.dismissAll(delayForAnimation: false);
    Get.back<void>();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('failed check exposes a useful error and retry clears stale state', () async {
    controller.availableAppUpdate.value = release;
    controller.fetch = () async => throw const AppUpdateException('The update check timed out. Please try again.');
    await controller.checkForAppUpdate();
    expect(controller.availableAppUpdate.value, isNull);
    expect(controller.appUpdateError.value, isTrue);
    expect(controller.appUpdateStatus.value, 'The update check timed out. Please try again.');
    expect(controller.appUpdateChecking.value, isFalse);
    controller.fetch = () async => null;
    await controller.checkForAppUpdate();
    expect(controller.appUpdateError.value, isFalse);
    expect(controller.appUpdateStatus.value, 'You’re up to date.');
    expect(controller.dialogs, 0);
  });

  test('an unexpected error stays readable and does not leave checking stuck', () async {
    controller.fetch = () async => throw StateError('internal detail');
    await controller.checkForAppUpdate();
    expect(controller.appUpdateStatus.value, 'Could not check for updates. Please try again.');
    expect(controller.appUpdateChecking.value, isFalse);
    expect(controller.appUpdateError.value, isTrue);
  });

  test('disposing the controller during a check does not open a late dialog', () async {
    final pending = Completer<AppRelease?>();
    controller.fetch = () => pending.future;
    final check = controller.checkForAppUpdate();
    controller.onDelete();
    pending.complete(release);
    await check;
    expect(controller.availableAppUpdate.value, isNull);
    expect(controller.dialogs, 0);
  });
}
