import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../../core/app_pref.dart';
import '../../core/app_setting.dart';
import '../../core/app_translations.dart';
import '../../data/database/db_activity.dart';
import '../../data/database/db_gamification.dart';
import '../../data/database/db_playlist.dart';
import '../../data/database/db_profile.dart';
import '../../data/database/db_videos.dart';
import '../../data/database/db_watch_session.dart';
import '../../data/models/library_entity.dart';
import '../../data/models/playlist_entity.dart';
import '../../data/models/profile_entity.dart';
import '../../data/models/videos_entity.dart';
import '../../routes/app_pages.dart';
import '../../utils/helper.dart';
import '../player/player_multi_view.dart';
import '../widgets/widget_surfaces.dart';
import 'home_panel/home_panel_library.dart';
import 'home_panel/home_panel_playlist.dart';
import 'page_chat/page_chat_controller.dart';
import 'page_download/page_download_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_profile/page_profile_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';
import 'page_tools/page_tools_controller.dart';

class HomeController extends GetxController with StateMixin {
  final menus = <Map<String, dynamic>>[
    {'icon': HugeIcons.strokeRoundedHouseWifi, 'name': kMenuHome},
    {'icon': HugeIcons.strokeRoundedSearch01, 'name': kMenuSearch},
    {'icon': HugeIcons.strokeRoundedBookOpen02, 'name': kMenuExplore},
    {'icon': HugeIcons.strokeRoundedDownload01, 'name': kMenuDownload},
    {'icon': HugeIcons.strokeRoundedLassoTool02, 'name': kMenuTools},
    {'icon': HugeIcons.strokeRoundedSettings01, 'name': kMenuSetting},
  ];
  final currentMenuSelected = kMenuHome.obs;
  final tecTopNavSearch = TextEditingController();
  final fnTopNavSearch = FocusNode();
  final isTopNavSearchExpanded = false.obs;
  final isTopNavSearching = false.obs;
  final topNavSearchRevision = 0.obs;

  final loadingText = '...'.obs;
  final totalVideo = 0.obs;
  final footerText = ''.obs;
  final footerStorageText = ''.obs;
  final footerStorageUsedPct = 0.0.obs;
  final sideMenuWidth = 180.0.obs;

  // library
  final library = <Library>[].obs;
  final isDangerMode = false.obs;
  final isDropHovering = false.obs;

  // cart
  final cart = <Videos>[].obs;
  Worker? _videoWorker;
  Worker? _gamificationWorker;
  Future<void>? _profileRefresh;
  bool _profileNeedsRefresh = false;
  bool _hasLoadedGamification = false;

  String _cartIdentity(Videos video) {
    final videoPath = (video.videoPath ?? '').trim().toLowerCase();
    if (videoPath.isNotEmpty) return 'path:$videoPath';

    final id = (video.id ?? '').trim().toLowerCase();
    if (id.isNotEmpty) return 'id:$id';

    final videoCode = (video.videoCode ?? '').trim().toLowerCase();
    if (videoCode.isNotEmpty) return 'code:$videoCode';

    final title = (video.title ?? '').trim().toLowerCase();
    return 'title:$title';
  }

  void deduplicateCart() {
    final seen = <String>{};
    final unique = <Videos>[];

    for (final item in cart) {
      final key = _cartIdentity(item);
      if (seen.add(key)) unique.add(item);
    }

    if (unique.length != cart.length) {
      cart.value = unique;
    }
  }

  bool isInCart(Videos video) {
    final key = _cartIdentity(video);
    return cart.any((item) => _cartIdentity(item) == key);
  }

  bool addToCart(Videos video) {
    if (isInCart(video)) return false;

    cart.add(video);
    return true;
  }

  // profile
  final profile = Profile().obs;
  final gamification = Rxn<GamificationSummary>();
  final streakDays = 0.obs;
  final achievementCount = 0.obs;
  final latestAchievementTitles = <String>[].obs;
  final achievementProgress = <AchievementProgress>[].obs;

  // playlist
  final playlist = <Playlist>[].obs;



  @override
  Future<void> onInit() async {
    super.onInit();
    fnTopNavSearch.addListener(_onTopNavSearchFocusChanged);

    change(200, status: RxStatus.loading());
    AppLog.logI('root home ==> onInit called');

    cart.value = AppPref.getAppCart();
    deduplicateCart();
    ever<List<Videos>>(cart, (value) => AppPref.setAppCart(value));
    _videoWorker = ever(DBVideos.revision, (_) => unawaited(refreshVideoContent()));
    _gamificationWorker = everAll([DBVideos.revision, DBPlaylist.revision, DBWatchSession.revision], (_) {
      unawaited(refreshProfile().catchError((Object e) => AppLog.logW('Refreshing gamification failed: $e')));
    });

    sideMenuWidth.value = AppPref.getAppHideSideMenu() ? 65 : 180;
    change(200, status: RxStatus.success());
  }

  @override
  void onReady() {
    super.onReady();
    unawaited(_loadStartupDetails());
  }

  Future<void> _loadStartupDetails() async {
    Future<void> load(String name, Future<void> Function() action) async {
      try {
        await action();
      } catch (e, stackTrace) {
        AppLog.logE('Startup $name failed: $e\n$stackTrace');
      }
    }

    await Future.wait([
      load('profile', refreshProfile),
      load('storage', updateFooterSummary),
      load('playlist', getAllPlaylist),
      load('activity', () async {
        final relapseToday = await DBActivity.getCountRelapseToday();
        isDangerMode.value = relapseToday >= AppPref.getAppMaxColi();
      }),
    ]);
    if (isClosed) return;
    await load('library watcher', HomePanelLibrary.startAutoRescanWatcher);
    if (isClosed) return;
    await load('library reconcile', HomePanelLibrary.runStartupReconcile);
  }

  @override
  void onClose() {
    _videoWorker?.dispose();
    _gamificationWorker?.dispose();
    HomePanelLibrary.stopAutoRescanWatcher();
    fnTopNavSearch.removeListener(_onTopNavSearchFocusChanged);
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
    super.onClose();
  }

  Future<void> refreshVideoContent() async {
    try {
      final refreshedCart = await Future.wait(cart.toList().map((video) async {
        if ((video.id ?? '').isNotEmpty) {
          final saved = await DBVideos.getAll(where: 'id = ?', whereArgs: [video.id], limit: 1);
          if (saved.isNotEmpty) return saved.single;
        }
        if ((video.videoPath ?? '').isEmpty) return video;
        return DBVideos.getByVideoPath(video.videoPath!);
      }));
      if (isClosed) return;
      cart.assignAll(refreshedCart.whereType<Videos>());
      await Future.wait([
        if (Get.isRegistered<PageHomeController>() && !Get.isPrepared<PageHomeController>())
          Get.find<PageHomeController>().onRefresh(),
        if (Get.isRegistered<PageSearchController>() && !Get.isPrepared<PageSearchController>())
          Get.find<PageSearchController>().onRefresh(),
        if (Get.isRegistered<PageExploreController>() && !Get.isPrepared<PageExploreController>())
          Get.find<PageExploreController>().onRefresh(),
        if (Get.isRegistered<PageToolsController>() && !Get.isPrepared<PageToolsController>()) ...[
          Get.find<PageToolsController>().refreshDeletedItemsMenu(),
          Get.find<PageToolsController>().getTopLargeFileSize(mode: Get.find<PageToolsController>().topLargeFilterMode.value),
          Get.find<PageToolsController>().getDuplicateVideos(),
          Get.find<PageToolsController>().checkIsHasDataNotScanned(),
        ],
        if (Get.isRegistered<PageSettingsController>() && !Get.isPrepared<PageSettingsController>())
          Get.find<PageSettingsController>().refreshLibraryStats(),
        getAllPlaylist(),
        HomePanelPlaylist.refreshVideoContent(),
        updateFooterSummary(),
      ]);
    } catch (e) {
      AppLog.logE('Refreshing video content failed: $e');
    }
  }

  Future<void> onRefreshAllContent({bool preserveInputState = false}) async {
    try {
      final sw = Stopwatch()..start();
      footerText.value = preserveInputState ? 'Refreshing (background)...'.tr : 'Refreshing...'.tr;

      if (!preserveInputState) {
        await Get.find<PageHomeController>().onRefresh();
        await Get.find<PageSearchController>().onRefresh();
        await Get.find<PageExploreController>().onRefresh();
        await Get.find<PageDownloadController>().onRefresh();
        await Get.find<PageToolsController>().onRefresh();
        await Get.find<PageSettingsController>().onRefresh();
      } else {
        // Keep inputs in other pages intact, but still update Home lists (e.g. New Added)
        await Get.find<PageHomeController>().onRefresh();
      }

      final relapseToday = await DBActivity.getCountRelapseToday();
      isDangerMode.value = relapseToday >= AppPref.getAppMaxColi();

      await refreshProfile();
      await updateFooterSummary();

      AppLog.logS('${preserveInputState ? 'Refresh Background Content'.tr : 'Refresh All Content'.tr} Take Time: ${sw.elapsedMilliseconds} ms');
      change(200, status: RxStatus.success());
    } catch (e) {
      AppLog.logE('Refresh all content failed: $e');
      AppConfirmDialog.show(
        title: Text('Ups'.tr),
        content: Text('${e.toString()}'),
        actions: [
          AppDialogAction(
            child: Text('Refresh'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              await onRefreshAllContent();
              Get.back();
            },
          ),
        ],
      );
    }
  }

  Future<void> onMenuChange(String menu) async {
    if (currentMenuSelected.value == kMenuChat && Get.isRegistered<PageChatController>() && !Get.isPrepared<PageChatController>()) {
      if (!await Get.find<PageChatController>().flushDraft()) return;
    }
    currentMenuSelected.value = menu;
  }

  String get idleFooterText => 'Idle | Total Video: @{value}'.trNamed({'value': '${totalVideo.value}'});

  Future<void> updateFooterSummary() async {
    totalVideo.value = await DBVideos.getCount();

    final storage = await _readStorageUsage();
    if (storage == null || storage['total'] == 0) {
      footerText.value = idleFooterText;
      footerStorageText.value = '';
      footerStorageUsedPct.value = 0;
      return;
    }

    final total = storage['total'] ?? 0;
    final free = storage['free'] ?? 0;
    final usedPct = total > 0 ? ((total - free) / total) * 100 : 0;
    footerText.value = idleFooterText;
    footerStorageText.value = ' | Avaiable: @{toFileSizeFormat} (@{toStringAsFixed}%)'.trNamed({'toFileSizeFormat': '${free.toFileSizeFormat()}', 'toStringAsFixed': '${usedPct.toStringAsFixed(1)}'});
    footerStorageUsedPct.value = usedPct.toDouble();
  }

  Future<Map<String, int>?> _readStorageUsage() async {
    try {
      final path = Get.find<AppSettingService>().appPath;
      if (Platform.isWindows) return await _readStorageUsageWindows(path);
      return await _readStorageUsagePosix(path);
    } catch (e) {
      AppLog.logD('Footer storage read failed: $e');
      return null;
    }
  }

  Future<Map<String, int>?> _readStorageUsagePosix(String path) async {
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

  Future<Map<String, int>?> _readStorageUsageWindows(String path) async {
    final drive = path.length >= 2 ? path.substring(0, 2) : path;
    final result = await Process.run('fsutil', ['volume', 'diskfree', drive]);
    if (result.exitCode != 0) return null;

    final freeMatch = RegExp(r'Total # of avail free bytes\s*:\s*(\d+)').firstMatch(result.stdout.toString());
    final totalMatch = RegExp(r'Total # of bytes\s*:\s*(\d+)').firstMatch(result.stdout.toString());
    if (freeMatch == null || totalMatch == null) return null;

    return {
      'free': int.tryParse(freeMatch.group(1) ?? '') ?? 0,
      'total': int.tryParse(totalMatch.group(1) ?? '') ?? 0,
    };
  }

  Future<void> onTopNavSearchSubmitted(String input) async {
    final query = input.trim();
    if (query.isEmpty) {
      isTopNavSearchExpanded.value = false;
      topNavSearchRevision.value++;
      return;
    }
    if (isTopNavSearching.isTrue) return;

    isTopNavSearching.value = true;
    try {
      final localVideos = await DBVideos.search(query);
      if (localVideos.isNotEmpty) {
        final search = Get.find<PageSearchController>().activeTab;
        search.showResults(query, localVideos);
        await onMenuChange(kMenuSearch);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (search.isClosed || !identical(Get.find<PageSearchController>().activeTab, search)) return;
          if (search.scrollGridController.hasClients) {
            search.scrollGridController.jumpTo(0);
          }
        });
        return;
      }

      final download = Get.find<PageDownloadController>().activeTab;
      download.filter.reset();
      download.tecSearch.text = query;
      download.currentPage.value = 1;
      await onMenuChange(kMenuDownload);
      await download.onSearch(query);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (download.isClosed || !identical(Get.find<PageDownloadController>().activeTab, download)) return;
        if (download.scrollController.hasClients) {
          download.scrollController.jumpTo(0);
        }
      });
    } finally {
      isTopNavSearching.value = false;
      tecTopNavSearch.clear();
      isTopNavSearchExpanded.value = false;
      topNavSearchRevision.value++;
    }
  }

  void clearTopNavSearch() {
    tecTopNavSearch.clear();
    isTopNavSearchExpanded.value = false;
    topNavSearchRevision.value++;
  }

  void focusTopNavSearch() {
    isTopNavSearchExpanded.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fnTopNavSearch.requestFocus();
      tecTopNavSearch.selection = TextSelection(
        baseOffset: 0,
        extentOffset: tecTopNavSearch.text.length,
      );
    });
  }

  void onTopNavSearchChanged(String input) {
    if (input.isEmpty && isTopNavSearching.isFalse) {
      isTopNavSearchExpanded.value = false;
    }
    topNavSearchRevision.value++;
  }

  void _onTopNavSearchFocusChanged() {
    if (fnTopNavSearch.hasFocus || tecTopNavSearch.text.isNotEmpty || isTopNavSearching.isTrue) return;
    isTopNavSearchExpanded.value = false;
    topNavSearchRevision.value++;
  }

  Future<void> onOpenSettingsAppLog() async {
    await onMenuChange(kMenuSetting);
    await Get.find<PageSettingsController>().onOpenAppLog();
  }


  // ──────────────────────────────────────────────────────────────
  // onDropEvent
  // ──────────────────────────────────────────────────────────────
  void onDropEnter(DropEvent event) => isDropHovering.value = !HomePanelLibrary.fileDragInProgress;
  void onDropLeave(DropEvent event) => isDropHovering.value = false;
  void onDropEnded(DropEvent event) => isDropHovering.value = false;

  Future<void> onDropEvent(PerformDropEvent event) async {
    isDropHovering.value = false;
    if (HomePanelLibrary.fileDragInProgress) return;
    final droppedPaths = <String>[];
    final readTasks = <Future<void>>[];

    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;

      final completer = Completer<void>();
      readTasks.add(completer.future);

      reader.getValue<Uri>(Formats.fileUri, (data) {
        if (data != null) {
          droppedPaths.add(_normalizeDropPath(data));
        }
        completer.complete();
      });
    }

    await Future.wait(readTasks);
    if (droppedPaths.isEmpty) return;

    final folderPaths = <String>[];
    final folderImagePaths = <String>[];
    final folderLibraryPaths = <String>[];
    final videoPaths = <String>[];
    final imagePaths = <String>[];
    var hasUnsupportedFile = false;

    for (final path in droppedPaths) {
      final isFolder = await FileSystemEntity.isDirectory(path);
      if (isFolder) {
        folderPaths.add(path);
        continue;
      }

      if (path.toLowerCase().endsWith('.mp4')) {
        videoPaths.add(path);
      } else if (_isImagePath(path)) {
        imagePaths.add(path);
      } else {
        hasUnsupportedFile = true;
      }
    }

    if (folderPaths.isNotEmpty) {
      for (final folderPath in folderPaths) {
        final folderImages = await _collectFolderImagesIfOnlyImages(folderPath);
        if (folderImages.isNotEmpty) {
          folderImagePaths.addAll(folderImages);
        } else {
          folderLibraryPaths.add(folderPath);
        }
      }
    }

    if (folderImagePaths.isNotEmpty) {
      unawaited(_openDroppedImages(folderImagePaths));
    }

    if (folderLibraryPaths.isNotEmpty) {
      unawaited(_openDroppedFolders(folderLibraryPaths));
    }

    if (imagePaths.isNotEmpty && folderPaths.isEmpty && videoPaths.isEmpty && !hasUnsupportedFile) {
      unawaited(_openDroppedImages(imagePaths));
    } else if (videoPaths.isNotEmpty) {
      unawaited(_openDroppedVideos(videoPaths));
    } else if (folderPaths.isEmpty && (hasUnsupportedFile || imagePaths.isNotEmpty)) {
      unawaited(HelperToast.warn('File not supported'.tr));
    }
  }

  bool _isImagePath(String path) {
    if (!path.contains('.')) return false;

    final ext = path.toLowerCase().split('.').last;
    return {
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif',
      'tiff', 'tif', 'svg', 'avif', 'apng', 'ico', 'raw', 'arw',
      'cr2', 'nef', 'orf', 'sr2'
    }.contains(ext);
  }

  String _normalizeDropPath(Uri uri) {
    try {
      return uri.toFilePath();
    } catch (_) {
      return Uri.decodeFull(uri.path);
    }
  }

  String _normalizeRawDropPath(String rawPath) {
    final value = rawPath.trim();
    final uri = Uri.tryParse(value);
    if (uri == null) return value;

    if (uri.scheme == 'file') {
      try {
        return Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: uri.path,
        ).toFilePath();
      } catch (_) {
        return Uri.decodeFull(uri.path);
      }
    }

    return value;
  }

  Future<List<String>> _collectFolderImagesIfOnlyImages(String folderPath) async {
    try {
      final folder = Directory(folderPath);
      if (!await folder.exists()) return [];

      final files = <String>[];
      await for (final entity in folder.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;

        final fileName = entity.path.getLastPath().toLowerCase();
        if (_isIgnoredSystemFile(fileName)) continue;

        files.add(entity.path);
        if (_isImagePath(entity.path) == false) {
          return [];
        }
      }

      if (files.isEmpty) return [];
      files.sort();
      return files;
    } catch (e) {
      AppLog.logW('Drop image folder scan failed: $e');
      return [];
    }
  }

  bool _isIgnoredSystemFile(String fileName) {
    return fileName.startsWith('.') ||
        fileName == 'thumbs.db' ||
        fileName == 'desktop.ini';
  }

  Future<void> _openDroppedImages(List<String> paths) async {
    final images = <String>[];
    for (final path in paths) {
      final decodedPath = _normalizeRawDropPath(path);
      final file = File(decodedPath);
      if (file.existsSync()) images.add(decodedPath);
    }

    if (images.isEmpty) {
      await HelperToast.warn('File not found'.tr);
      return;
    }

    await Get.toNamed(Routes.IMG_VIEWER, arguments: {
      'images': images,
      'title': images.length == 1 ? images.first.getLastPath() : 'Image Viewer'.tr,
    });
  }

  Future<void> _openDroppedFolders(List<String> paths) async {
    for (final path in paths) {
      final normalizedPath = path.endsWith(Platform.pathSeparator) ? path.substring(0, path.length - 1) : path;
      final newLibrary = await HelperFilePicker.scanFolderAndSubFolder(normalizedPath);
      newLibrary?.alias = newLibrary.rootFolder?.getLastPath();

      await HomePanelLibrary.showDialogAddorEditLibrary(library: newLibrary, isFromDrop: true);
    }
  }

  Future<void> _openDroppedVideos(List<String> paths) async {
    final videos = <Videos>[];
    for (final path in paths) {
      final video = await _createDroppedVideo(path);
      if (video != null) {
        videos.add(video);
      }
    }

    if (videos.isEmpty) return;
    if (videos.length == 1) {
      await HelperOpener.openVideoFile(videos.first);
      return;
    }

    AppConfirmDialog.show(
      isDismissible: false,
      title: Text('Open Videos'.tr),
      content: Text('Choose how to play your videos.'.tr),
      actions: [
        AppDialogAction(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Single Player'.tr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              SizedBox(height: 4),
              Text('Play one at a time in a playlist.'.tr, style: TextStyle(fontSize: 11, color: Vx.gray300), textAlign: TextAlign.center),
            ],
          ),
          onPressed: () async {
            Get.back();
            await HelperOpener.openVideoFile(videos.first, playlist: videos);
          },
        ),
        AppDialogAction(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Multi Player'.tr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              SizedBox(height: 4),
              Text('Play videos side by side at the same time.'.tr, style: TextStyle(fontSize: 11, color: Vx.gray300), textAlign: TextAlign.center),
            ],
          ),
          onPressed: () async {
            Get.back();
            await Get.to(() => const PlayerMultiView(), arguments: videos);
          },
        ),
        AppDialogAction(
          child: Text('Cancel'.tr, style: TextStyle(fontSize: 13)),
          onPressed: () => Get.back(),
        ),
      ],
    );
  }

  Future<Videos?> _createDroppedVideo(String path) async {
    final decodedPath = _normalizeRawDropPath(path);
    final file = File(decodedPath);
    if (!file.existsSync()) {
      await HelperToast.warn('File not found'.tr);
      return null;
    }

    final fileName = decodedPath.getLastPath();
    final cleanTitle = fileName.contains('.') ? fileName.split('.').first : fileName;

    return Videos(
      id: UuidV4().generate(),
      videoPath: decodedPath,
      videoCode: decodedPath.getFileName().getVideoCode(),
      title: cleanTitle,
      viewCount: 0,
      filesize: await file.length(),
      createdAt: DateTime.now().toStringEx(),
      updatedAt: DateTime.now().toStringEx(),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ profile
  // ────────────────────────────────────────────────────────────────
  Future<void> onOpenProfile() async {
    await onMenuChange(kMenuProfile);
    await Get.find<PageProfileController>().onRefresh();
  }

  Future<void> refreshProfile() {
    _profileNeedsRefresh = true;
    return _profileRefresh ??= _loadProfile().whenComplete(() => _profileRefresh = null);
  }

  Future<void> _loadProfile() async {
    do {
      _profileNeedsRefresh = false;
      final summary = await DBGamification.syncAndGetSummary();
      final updatedProfile = await DBProfile.getProfile() ?? Profile();
      if (isClosed) return;
      final previous = gamification.value;
      profile.value = updatedProfile;
      gamification.value = summary;
      totalVideo.value = summary.stats['videos']!;
      streakDays.value = summary.streakDays;
      achievementCount.value = summary.achievementCount;
      latestAchievementTitles.value = summary.latestAchievements.map((e) => e.title).toList();
      achievementProgress.value = summary.progress;
      if (_hasLoadedGamification && summary.newAchievementTitles.isNotEmpty && Get.context != null) {
        final titles = summary.newAchievementTitles.take(3).map((title) => title.tr).join(' · ');
        final more = summary.newAchievementTitles.length - 3;
        final message = 'Milestones unlocked: @{titles} · +@{xp} XP'.trNamed({
          'titles': more > 0 ? '$titles · ${'@{count} more'.trNamed({'count': '$more'})}' : titles,
          'xp': '${summary.progress.where((item) => summary.newAchievementTitles.contains(item.title)).fold<int>(0, (xp, item) => xp + item.xp)}',
        });
        unawaited(HelperToast.success(summary.level > (previous?.level ?? 1)
          ? '$message\n${'Level @{level}'.trNamed({'level': '${summary.level}'})} · ${summary.rank.tr}' : message,
          duration: const Duration(seconds: 4), addToAppLog: false));
      }
      _hasLoadedGamification = true;
    } while (_profileNeedsRefresh);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ playlist
  // ────────────────────────────────────────────────────────────────
  Future<void> getAllPlaylist() async {
    playlist.clear();
    playlist.value = await DBPlaylist.getAllPlaylist();
  }

}

// ────────────────────────────────────────────────────────────────
// # menu const
// ────────────────────────────────────────────────────────────────
const kMenuHome = 'Home';
const kMenuSearch = 'Search';
const kMenuExplore = 'Explore';
const kMenuDownload = 'Download';
const kMenuTools = 'Tools';
const kMenuSetting = 'Settings';
const kMenuSqlEditor = 'SQL Editor';
const kMenuChat = 'Chat with AI';

const kMenuProfile = 'Profile';
