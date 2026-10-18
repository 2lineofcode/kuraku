import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ex_kit/ex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_setting.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/_init_db.dart';
import '../../../data/database/app_backup.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/app_updater.dart';
import '../../../utils/helper.dart';
import '../../../utils/local_semantic_worker.dart';
import '../../../utils/r18_updater.dart';
import '../../../utils/semantic_search_service.dart';
import '../../../utils/watch_session_tracker.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_log.dart';
import '../page_chat/page_chat_controller.dart';
import '../page_explore/page_explore_controller.dart';
import '../page_sqleditor/page_sqleditor_controller.dart';
import 'app_update_dialog.dart';

class PageSettingsController extends GetxController {
  final appSetting = Get.find<AppSettingService>();
  final dbR18Version = 0.obs;
  final backupBusy = false.obs;
  final restorePending = false.obs;
  final appVersion = '-'.obs;
  final appUpdateChecking = false.obs;
  final appUpdateStatus = ''.obs;
  final appUpdateError = false.obs;
  final availableAppUpdate = Rxn<AppRelease>(AppUpdater.latestRelease);

  final totalLibrary = 0.obs;
  final totalVideos = 0.obs;
  final totalAlbums = 0.obs;
  final totalImages = 0.obs;
  final totalFilesize = Rx<num>(0);
  final lastRelapse = ''.obs;
  final r18TotalVideo = 0.obs;

  // ** config
  final tecDefaultPlayer = '${AppPref.getDefaultPlayer()}'.obs;
  final tecDefaultSearchEngine = '${AppPref.getDefaultSearchEngine()}'.obs;
  final tecAppMaxColi = TextEditingController(text: AppPref.getAppMaxColi().toString());
  final tecPlayerSeekShort = TextEditingController(text: AppPref.getPlayerSeekShort().toString());
  final tecPlayerSeekMid = TextEditingController(text: AppPref.getPlayerSeekMid().toString());
  final tecPlayerSeekLong = TextEditingController(text: AppPref.getPlayerSeekLong().toString());
  final semanticEmbeddingCount = 0.obs;
  final semanticMissingCount = 0.obs;
  final semanticBusy = false.obs;
  final semanticStatus = ''.obs;
  final semanticStatusIsRoutine = false.obs;
  final semanticReady = false.obs;
  final semanticProgress = (-1.0).obs;
  final semanticSkipped = 0.obs;
  final semanticInstalling = false.obs;
  bool _semanticStopped = false;

  // **
  final appMiniMode = false.obs;
  final appTheme = AppPref.getAppTheme().obs;
  final tecAppAccent = TextEditingController(text: AppPref.getAppAccent()?.toRadixString(16).padLeft(8, '0').replaceFirst(RegExp(r'^ff'), '').toUpperCase() ?? '');
  final appAccentError = ''.obs;
  final appLanguage = AppPref.getAppLanguage().obs;
  final appPinEnabled = AppPref.getAppPinEnabled().obs;


  // ** storage
  final storageList = <StorageUsage>[].obs;
  final isLoadingStorage = false.obs;

  // ** app_log
  final appLogMode = false.obs;
  final appLogLevelSelected = 'ALL'.obs;
  final appLogKeyword = ''.obs;
  final appLogData = HomePanelAppLog.appLogRuntime;
  final tecAppLogFilter = TextEditingController();

  @override
  Future<void> onInit() async {
    super.onInit();
    await refreshAppVersion();
    await onRefresh();
  }

  Future<void> refreshAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion.value = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (e) {
      AppLog.logE('Could not read app version: $e');
    }
  }

  Future<AppRelease?> fetchAppUpdate() => AppUpdater.checkInstalled();

  Future<void> offerStartupAppUpdate(AppRelease release) async {
    if (isClosed || availableAppUpdate.value?.version == release.version) return;
    availableAppUpdate.value = release;
    appUpdateError.value = false;
    appUpdateStatus.value = 'Update available: @{version}'.trNamed({'version': release.version});
    await showAppUpdate(automatic: true);
  }

  Future<void> checkForAppUpdate() async {
    if (appUpdateChecking.value) return;
    appUpdateChecking.value = true;
    appUpdateError.value = false;
    appUpdateStatus.value = '';
    availableAppUpdate.value = null;
    try {
      final release = await fetchAppUpdate();
      if (isClosed) return;
      availableAppUpdate.value = release;
      appUpdateStatus.value = release == null
        ? 'You’re up to date.'.tr
        : 'Update available: @{version}'.trNamed({'version': release.version});
    } catch (e) {
      if (isClosed) return;
      AppLog.logW('App update check failed: $e');
      appUpdateError.value = true;
      appUpdateStatus.value = (e is AppUpdateException ? e.message : 'Could not check for updates. Please try again.').tr;
    } finally {
      appUpdateChecking.value = false;
    }
    if (!isClosed && availableAppUpdate.value != null) await showAppUpdate();
  }

  Future<void> showAppUpdate({bool automatic = false}) async {
    final release = availableAppUpdate.value;
    if (release == null) return;
    await AppUpdateDialog.show(
      release: release,
      installedVersion: appVersion.value,
      automatic: automatic,
    );
  }

  Future<void> setLanguage(String code) async {
    if (!AppTranslations.languages.containsKey(code)) return;
    try {
      await AppPref.setAppLanguage(code);
      appLanguage.value = code;
      if (Get.locale != Locale(code)) await Get.updateLocale(Locale(code));
    } catch (e) {
      AppLog.logE('Could not save language: $e');
      await HelperToast.error('Could not save language. Please retry.'.tr);
    }
  }

  Future<void> setTheme(AppTheme value) async {
    try {
      await AppPref.setAppTheme(value);
      appTheme.value = value;
      appSetting.refreshTheme();
    } catch (e) {
      AppLog.logE('Could not save theme: $e');
      await HelperToast.error('Could not save appearance. Please retry.'.tr);
    }
  }

  Future<void> setAccent({bool reset = false}) async {
    final hex = reset ? '' : tecAppAccent.text.trim().replaceFirst(RegExp(r'^#'), '');
    if (hex.isNotEmpty && !RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      appAccentError.value = 'Use RRGGBB or AARRGGBB HEX'.tr;
      return;
    }
    try {
      await AppPref.setAppAccent(hex.isEmpty ? null : colorFromHex(hex)!.toARGB32());
      tecAppAccent.text = hex.toUpperCase();
      appAccentError.value = '';
      Get.rootController.darkTheme = AppStyle.theme(Brightness.dark);
      Get.changeTheme(AppStyle.theme(Brightness.light));
    } catch (e) {
      AppLog.logE('Could not save accent color: $e');
      appAccentError.value = 'Could not save appearance. Please retry.'.tr;
    }
  }

  Future<void> refreshLibraryStats() async {
    final libraries = await DBLibrary.getAll();
    if (isClosed) return;
    totalLibrary.value = libraries.length;
    totalAlbums.value = libraries.where((library) => library.images?.isNotEmpty ?? false).length;
    totalImages.value = libraries.fold<int>(0, (count, library) => count + (library.images?.length ?? 0));
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();
    final r18db = Get.find<DBService>().dbR18;
    dbR18Version.value = r18db == null ? 0 : await r18db.getVersion();
    await refreshLibraryStats();
    totalVideos.value = await DBVideos.getCount();
    totalFilesize.value = await DBVideos.getTotalFileSizeAllVideo() ?? 0;
    await refreshSemanticStatus();
    r18TotalVideo.value = await DBR18.getCountAllVideos();

    final current = Get.find<HomeController>().sideMenuWidth.value;
    if (current == 65) {
      appMiniMode.value = true;
    } else {
      appMiniMode.value = false;
    }

    await refreshRelapse();

    AppLog.logI('page settings ==> onInit called: ${sw.elapsedMilliseconds} ms');
  }

  Future<void> refreshRelapse() async {
    final latest = await DBActivity.getLatestRelapseTransaction();
    lastRelapse.value = latest?.createdAt?.reformatDate(to: 'MMM, d y HH:mm') ?? '-';
  }

  Future<void> saveRelapseLimit() async {
    final value = int.tryParse(tecAppMaxColi.text);
    if (value == null || value < 0) {
      tecAppMaxColi.text = AppPref.getAppMaxColi().toString();
      await HelperToast.error('Enter a valid daily limit. Zero blocks playback.'.tr);
      return;
    }
    try {
      await AppPref.setAppMaxColi(value);
      final count = await DBActivity.getCountRelapseToday();
      Get.find<HomeController>().isDangerMode.value = count >= value;
    } catch (_) {
      await HelperToast.error('Could not save daily limit. Please retry.'.tr);
    }
  }

  @override
  void onClose() {
    if (SemanticSearchService.indexing) SemanticSearchService.cancelIndex();
    if (semanticInstalling.value) LocalSemanticWorker.cancelSetup();
    tecAppMaxColi.dispose();
    tecAppAccent.dispose();
    tecPlayerSeekShort.dispose();
    tecPlayerSeekMid.dispose();
    tecPlayerSeekLong.dispose();
    tecAppLogFilter.dispose();
    super.onClose();
  }

  @override
  Future<void> onReady() async {
    super.onReady();
    await onRefreshStorage();
  }

  Future<void> onRefreshStorage() async {
    isLoadingStorage.value = true;
    try {
      storageList.value = await _scanStorage();
    } catch (e) {
      AppLog.logE('Failed to read storage: $e');
      await HelperToast.error('Failed to read storage: @{e}'.trNamed({'e': '$e'}));
    } finally {
      isLoadingStorage.value = false;
    }
  }

  Future<void> refreshSemanticStatus() async {
    semanticReady.value = await LocalSemanticWorker.isReady();
    if (!semanticReady.value) {
      semanticEmbeddingCount.value = 0;
      semanticMissingCount.value = totalVideos.value;
      return;
    }
    if (SemanticSearchService.playbackActive) return;
    try {
      final status = await SemanticSearchService.indexStatus();
      semanticEmbeddingCount.value = status['indexed'] as int;
      semanticMissingCount.value = status['pending'] as int;
    } catch (e) {
      semanticStatusIsRoutine.value = false;
      semanticStatus.value = e.toString();
      AppLog.logW('Visual Search: status refresh failed: $e');
    }
  }

  Future<void> setupSemanticSearch() async {
    AppLog.logI('Visual Search: setup requested');
    if (semanticBusy.value) {
      AppLog.logW('Visual Search: setup ignored because another operation is running');
      return;
    }
    semanticStatusIsRoutine.value = false;
    if (SemanticSearchService.playbackActive) {
      semanticStatus.value = 'Close the player before setup.'.tr;
      AppLog.logW('Visual Search: setup blocked because a player is open');
      return;
    }
    semanticBusy.value = true;
    semanticInstalling.value = true;
    semanticStatus.value = 'Preparing Visual Search setup...'.tr;
    semanticProgress.value = -1;
    try {
      await LocalSemanticWorker.setup((message) {
        if (isClosed) return;
        semanticStatus.value = message;
        final percent = RegExp(r'(\d+)%').firstMatch(message);
        semanticProgress.value = percent == null ? -1 : int.parse(percent[1]!) / 100;
      });
      if (isClosed) return;
      semanticStatusIsRoutine.value = true;
      semanticStatus.value = 'Ready. Index thumbnails to enable visual matches.'.tr;
      AppLog.logI('Visual Search: setup completed');
      await refreshSemanticStatus();
    } catch (e) {
      semanticStatusIsRoutine.value = false;
      semanticStatus.value = e.toString();
      AppLog.logE('Visual Search: setup failed or stopped: $e');
    } finally {
      if (!isClosed) semanticReady.value = await LocalSemanticWorker.isReady();
      semanticInstalling.value = false;
      semanticBusy.value = false;
    }
  }

  void stopSemanticIndex() {
    AppLog.logI('Visual Search: stop requested');
    _semanticStopped = true;
    semanticStatusIsRoutine.value = false;
    semanticStatus.value = 'Stopping… Completed work will be kept.'.tr;
    if (semanticInstalling.value) {
      LocalSemanticWorker.cancelSetup();
    } else {
      SemanticSearchService.cancelIndex();
    }
  }

  Future<void> generateMissingEmbeddings() => _runSemanticIndex(false);
  Future<void> reindexAllEmbeddings() => _runSemanticIndex(true);

  Future<void> _runSemanticIndex(bool force) async {
    AppLog.logI('Visual Search: indexing requested (rebuild=$force)');
    if (semanticBusy.value) {
      AppLog.logW('Visual Search: indexing ignored because another operation is running');
      return;
    }
    semanticStatusIsRoutine.value = false;
    if (SemanticSearchService.playbackActive) {
      semanticStatus.value = 'Close the player to start indexing.'.tr;
      AppLog.logW('Visual Search: indexing blocked because a player is open');
      return;
    }
    semanticBusy.value = true;
    _semanticStopped = false;
    semanticStatus.value = 'Checking thumbnails...'.tr;
    semanticProgress.value = -1;
    semanticSkipped.value = 0;
    try {
      Future<void> progress(SemanticIndexProgress value) async {
        if (isClosed) return;
        semanticSkipped.value = value.skipped;
        semanticProgress.value = value.total == 0 ? -1 : value.current / value.total;
        semanticStatus.value = value.paused
            ? 'Paused while a player is open. Progress is saved.'.tr
            : '@{current} / @{total} checked · @{indexed} indexed · @{skipped} skipped'.trNamed({'current': '${value.current}', 'total': '${value.total}', 'indexed': '${value.indexed}', 'skipped': '${value.skipped}'});
      }
      final result = force
          ? await SemanticSearchService.reindexAll(onProgress: progress)
          : await SemanticSearchService.reindexMissing(onProgress: progress);
      semanticStatusIsRoutine.value = !result.cancelled && result.skipped == 0;
      final details = result.skipped > 0 ? ' @{message} Retry after unavailable files are restored.'.trNamed({'message': result.message}) : '';
      semanticStatus.value = '@{state} · @{indexed} indexed · @{skipped} skipped.@{details}'.trNamed({
        'state': result.cancelled ? 'Stopped'.tr : 'Finished'.tr,
        'indexed': '${result.indexed}', 'skipped': '${result.skipped}', 'details': details,
      });
      AppLog.logI('Visual Search: ${semanticStatus.value}');
      await refreshSemanticStatus();
    } catch (e) {
      AppLog.logE('Visual Search: indexing failed or stopped: $e');
      semanticStatusIsRoutine.value = false;
      semanticStatus.value = _semanticStopped ? 'Stopped. Progress saved.'.tr : 'Index failed: @{e}'.trNamed({'e': '$e'});
    } finally {
      semanticBusy.value = false;
    }
  }

  Future<void> onOpenAppLog() async {
    appLogMode.value = true;
    appLogLevelSelected.value = 'ALL';
    appLogKeyword.value = '';
    tecAppLogFilter.clear();
    await Future.delayed(100.milliseconds);
  }

  List<AppLogRuntime> get filteredAppLogs {
    final selected = appLogLevelSelected.value.toUpperCase();
    final keyword = appLogKeyword.value.trim().toLowerCase();

    return appLogData.where((item) {
      final level = normalizeLogLevel(item.type);
      final passLevel = selected == 'ALL' || level == selected;
      if (!passLevel) return false;
      if (keyword.isEmpty) return true;

      final createdAt = (item.createdAt ?? '').toLowerCase();
      final content = (item.content ?? '').toLowerCase();
      final type = (item.type ?? '').toLowerCase();
      return createdAt.contains(keyword) || content.contains(keyword) || type.contains(keyword);
    }).toList();
  }

  String normalizeLogLevel(String? rawLevel) {
    final upper = (rawLevel ?? '').toUpperCase();
    if (upper == 'WARNING') return 'WARN';
    return upper;
  }

  void clearAppLog() {
    HomePanelAppLog.clear();
  }

  Future<void> exportBackup() async {
    if (backupBusy.value) return;
    backupBusy.value = true;
    try {
      final chat = Get.isRegistered<PageChatController>() && !Get.isPrepared<PageChatController>() ? Get.find<PageChatController>() : null;
      if (chat != null && !await chat.flushDraft()) return;
      if (Get.isRegistered<PageSqleditorController>() && !Get.isPrepared<PageSqleditorController>()) {
        final sql = Get.find<PageSqleditorController>();
        await sql.saveTabs();
        if (sql.saveError.value.isNotEmpty) throw StateError(sql.saveError.value);
      }
      await WatchSessionTracker.flushAll();
      final backup = await AppBackup.capture(Get.find<DBService>().dbMain, appSetting.pref);
      await backup.validate();
      final path = await FilePicker.saveFile(
        bytes: Uint8List.fromList(utf8.encode(backup.encode())),
        mimeType: 'application/json',
        dialogTitle: 'Export Backup'.tr,
        fileName: 'kuraku-${DateTime.now().toIso8601String().split('T').first}.kuraku-backup.json',
        type: FileType.custom, allowedExtensions: ['json'],
      );
      if (path == null) return;
      await HelperToast.success('Backup saved. Keep this file private; it contains your history and paths.'.tr);
    } catch (e) {
      AppLog.logE('Backup export failed: $e');
      await HelperToast.error('Backup failed: @{error}'.trNamed({'error': '$e'}));
    } finally {
      backupBusy.value = false;
    }
  }

  Future<void> restoreBackup() async {
    if (backupBusy.value || restorePending.value) return;
    backupBusy.value = true;
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      final path = files.isEmpty ? null : files.single.path;
      if (path == null) return;
      final backup = await AppBackup.read(File(path));
      await backup.validate();
      await WatchSessionTracker.flushAll();
      final current = await AppBackup.capture(Get.find<DBService>().dbMain, appSetting.pref);
      final confirmed = await Get.dialog<bool>(AppDialog(
        title: Text('Restore Preview'.tr),
        content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Backup created: @{date}'.trNamed({'date': backup.createdAt})),
          const SizedBox(height: 12),
          Text('Current → Backup'.tr),
          for (final entry in {
            'Libraries': 'library', 'Video metadata': 'videos', 'Playlists': 'playlist',
            'Playlist items': 'playlist_item', 'Watch sessions': 'watch_session',
            'Profile': 'profile', 'Achievements': 'achievement_unlock', 'Relapse history': 'relapse_event',
            'Search history': 'historical', 'Todo': 'todo', 'Download history': 'download_log',
            'File identities': 'video_file_identity', 'Chats': 'chat_conversation', 'Chat messages': 'chat_message',
            'Title translations': 'chat_translation',
          }.entries)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text('@{label}: @{current} → @{backup}'.trNamed({
                'label': entry.key.tr, 'current': '${current.count(entry.value)}', 'backup': '${backup.count(entry.value)}',
              }))),
          const SizedBox(height: 6),
          Text('@{label}: @{current} → @{backup}'.trNamed({
            'label': 'Favorites'.tr, 'current': '${current.favorites}', 'backup': '${backup.favorites}',
          })),
          Text('@{label}: @{current} → @{backup}'.trNamed({
            'label': 'Settings'.tr, 'current': '${current.settingsCount}', 'backup': '${backup.settingsCount}',
          })),
          const SizedBox(height: 12),
          Text('On next startup, included records and settings will be replaced, including empty lists. Video/image files, R18, embedding caches, and your app PIN are excluded. Saved paths stay as saved in the backup. Download history does not restart downloads.'.tr),
          const SizedBox(height: 8),
          Text('A recovery backup will be saved in @{path} before overwriting. Close and reopen the app after confirming.'.trNamed({'path': appSetting.appPath})),
        ]),
        actions: [
          AppButton(onPressed: () => Get.back(result: false), variant: AppButtonVariant.outlined, label: 'Cancel'.tr),
          AppButton(onPressed: () => Get.back(result: true), label: 'Restore on next startup'.tr),
        ],
      )) ?? false;
      if (!confirmed) return;
      await backup.write(File(p.join(appSetting.appPath, 'pending-restore.json')));
      restorePending.value = true;
      await HelperToast.success('Restore prepared. Close and reopen the app to apply it.'.tr);
    } catch (e) {
      AppLog.logE('Backup restore failed: $e');
      await HelperToast.error('Restore failed: @{error}'.trNamed({'error': '$e'}));
    } finally {
      backupBusy.value = false;
    }
  }

  Future<void> onResetAll() async {
    await _openDialogConfirm(
      onYes: () async {
        Get.back();
        final chat = Get.isRegistered<PageChatController>() && !Get.isPrepared<PageChatController>() ? Get.find<PageChatController>() : null;
        if (chat != null) await chat.stopResponse();
        if (chat != null && !await chat.flushDraft()) return;
        await Get.find<DBService>().deleteAllData();
        if (chat != null) await chat.reload();
        await Get.find<HomeController>().onRefreshAllContent();
      },
    );
  }

  Future<void> updateR18DB() async {
    if (R18Updater.busy.value) return;
    final home = Get.find<HomeController>();
    int? version;
    try {
      version = await R18Updater.update(
        onStatus: (message) => home.footerText.value = message,
        confirm: (version, local) async => await Get.dialog<bool>(AppConfirmDialog(
          title: Text('Update R18 DB'.tr),
          content: Text((local ? 'Local R18 version @{version} is available. Import it?' : 'R18 version @{version} is available. Download and install?').trNamed({'version': '$version'})),
          actions: [
            AppDialogAction(onPressed: () => Get.back(result: false), child: Text('Cancel'.tr)),
            AppDialogAction(onPressed: () => Get.back(result: true), child: Text('Update'.tr)),
          ],
        )) ?? false,
      );
    } catch (e) {
      await HelperToast.error('${R18Updater.status.value}\n$e');
      return;
    }
    if (version == null) {
      if (R18Updater.status.value.isEmpty) home.footerText.value = home.idleFooterText;
      return;
    }
    dbR18Version.value = version;
    try {
      r18TotalVideo.value = await DBR18.getCountAllVideos();
      await Get.find<PageExploreController>().onRefresh();
    } catch (e) {
      AppLog.logW('R18 updated, but catalog refresh failed: $e');
    }
    home.footerText.value = R18Updater.status.value;
    await HelperToast.success('R18 updated. Ready to use.'.tr);
  }

  Future<void> _openDialogConfirm({
    void Function()? onYes,
    String? title,
    String? message,
  }) async {
    AppConfirmDialog.show(
      title: Text(title ?? 'Are you sure?'.tr, style: TextStyle(fontSize: 14)),
      content: message != null ? Text(message, style: TextStyle(fontSize: 12)).pOnly(top: 8) : null,
      actions: [
        AppDialogAction(
          onPressed: onYes,
          child: Text('Yes'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
        ),
        AppDialogAction(
          child: Text('No'.tr, style: TextStyle(fontSize: 13)),
          onPressed: () {
            Get.back();
          },
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Storage helpers
  // ────────────────────────────────────────────────────────────────
  Future<List<StorageUsage>> _scanStorage() async {
    final List<StorageUsage> result = [];

    final primary = await _readUsage(
      appSetting.appPath,
      label: Platform.isMacOS
          ? 'Macintosh HD'
          : Platform.isWindows && appSetting.appPath.length >= 2
              ? appSetting.appPath.substring(0, 2)
              : 'System Drive'.tr,
      isExternal: false,
    );
    if (primary != null) {
      result.add(primary);
    }

    final externalMounts = await _discoverExternalMounts();
    for (final mount in externalMounts) {
      final info = await _readUsage(
        mount,
        label: _labelFromPath(mount),
        isExternal: true,
      );
      if (info != null) {
        result.add(info);
      }
    }

    return result;
  }

  Future<StorageUsage?> _readUsage(
    String path, {
    required String label,
    required bool isExternal,
  }) async {
    try {
      if (Platform.isWindows) {
        final usage = await _readUsageWindows(path);
        if (usage == null) return null;
        return StorageUsage(
          label: label,
          path: path,
          totalBytes: usage['total'] ?? 0,
          freeBytes: usage['free'] ?? 0,
          isExternal: isExternal,
        );
      } else {
        final usage = await _readUsagePosix(path);
        if (usage == null) return null;
        return StorageUsage(
          label: label,
          path: path,
          totalBytes: usage['total'] ?? 0,
          freeBytes: usage['free'] ?? 0,
          isExternal: isExternal,
        );
      }
    } catch (e) {
      AppLog.logD('Storage usage read failed for $path: $e');
      return null;
    }
  }

  Future<Map<String, int>?> _readUsagePosix(String path) async {
    final result = await Process.run('df', ['-k', path]);
    if (result.exitCode != 0) return null;
    final lines = result.stdout.toString().trim().split('\n');
    if (lines.length < 2) return null;
    final parts = lines[1].split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length < 4) return null;

    final totalKb = int.tryParse(parts[1]);
    final availableKb = int.tryParse(parts[3]);
    if (totalKb == null || availableKb == null) return null;

    return {
      'total': totalKb * 1024,
      'free': availableKb * 1024,
    };
  }

  Future<Map<String, int>?> _readUsageWindows(String path) async => HelperMisc.windowsStorageUsage(path);

  Future<List<String>> _discoverExternalMounts() async {
    final mounts = <String>[];

    if (Platform.isMacOS) {
      final dir = Directory('/Volumes');
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is! Directory) continue;
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          if (name == 'Macintosh HD' || name == 'Macintosh HD - Data') continue;
          mounts.add(entity.path);
        }
      }
    } else if (Platform.isLinux) {
      mounts.addAll(HelperMisc.linuxExternalMounts(await File('/proc/self/mountinfo').readAsString()));
    } else if (Platform.isWindows) {
      for (var codeUnit = 'D'.codeUnitAt(0); codeUnit <= 'Z'.codeUnitAt(0); codeUnit++) {
        final letter = String.fromCharCode(codeUnit);
        final drive = '$letter:\\\\';
        if (Directory(drive).existsSync()) {
          mounts.add(drive);
        }
      }
    }

    return mounts;
  }

  String _labelFromPath(String path) {
    if (Platform.isWindows) {
      return path.substring(0, 2);
    }
    final base = p.basename(path);
    return base.isNotEmpty ? base : path;
  }
}

class StorageUsage {
  StorageUsage({
    required this.label,
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
    required this.isExternal,
  });

  final String label;
  final String path;
  final int totalBytes;
  final int freeBytes;
  final bool isExternal;

  double get usedPct => totalBytes > 0 ? ((totalBytes - freeBytes) / totalBytes) * 100 : 0;
  double get freePct => totalBytes > 0 ? (freeBytes / totalBytes) * 100 : 0;
}
