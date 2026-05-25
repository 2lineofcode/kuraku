import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:uicons_pro/uicons_pro.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../../core/app_pref.dart';
import '../../core/app_setting.dart';
import '../../core/const.dart';
import '../../data/database/db_activity.dart';
import '../../data/database/db_collection.dart';
import '../../data/database/db_gamification.dart';
import '../../data/database/db_profile.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/activity_entity.dart';
import '../../data/models/collection_entity.dart';
import '../../data/models/library_entity.dart';
import '../../data/models/profile_entity.dart';
import '../../data/models/videos_entity.dart';
import '../../routes/app_pages.dart';
import '../../utils/helper.dart';
import '../player/player_multi_view.dart';
import 'home_panel/home_panel_library.dart';
import 'page_download/page_download_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';
import 'page_tools/page_tools_controller.dart';

class HomeController extends GetxController with StateMixin {
  final menus = <Map<String, dynamic>>[
    {'icon': UIconsPro.regularRounded.comet, 'name': kMenuHome},
    {'icon': UIconsPro.regularRounded.magnifying_glass_wave, 'name': kMenuSearch},
    {'icon': UIconsPro.regularRounded.book_alt, 'name': kMenuExplore},
    {'icon': UIconsPro.regularRounded.display_arrow_down, 'name': kMenuDownload},
    {'icon': UIconsPro.regularRounded.customization, 'name': kMenuTools},
    {'icon': UIconsPro.regularRounded.operating_system_upgrade, 'name': kMenuSetting},
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

  bool addToCart(Videos video) {
    final key = _cartIdentity(video);
    final isAlreadyExists = cart.any((item) => _cartIdentity(item) == key);
    if (isAlreadyExists) return false;

    cart.add(video);
    return true;
  }

  // profile
  final profile = Profile().obs;
  final streakDays = 0.obs;
  final achievementCount = 0.obs;
  final latestAchievementTitles = <String>[].obs;
  final achievementProgress = <AchievementProgress>[].obs;

  // playlist
  final playlist = <Collection>[].obs;

  

  @override
  Future<void> onInit() async {
    super.onInit();
    fnTopNavSearch.addListener(_onTopNavSearchFocusChanged);
    
    change(200, status: RxStatus.loading());
    AppLog.logI('root home ==> onInit called');

    cart.value = AppPref.getAppCart();
    deduplicateCart();
    ever<List<Videos>>(cart, (value) => AppPref.setAppCart(value));

    profile.value = await DBProfile.getProfile() ?? Profile();

    totalVideo.value = await DBVideos.getCount();
    await _syncGamification();
    profile.value = await DBProfile.getProfile() ?? Profile();

    await updateFooterSummary();

    sideMenuWidth.value = AppPref.getAppHideSideMenu() ? 65 : 180;

    await DBActivity.getCountRelapseToday();
    isDangerMode.value = await DBActivity.getCountRelapseToday() >= AppPref.getAppMaxColi();

    await getAllPlaylist();
    await HomePanelLibrary.startAutoRescanWatcher();
    unawaited(HomePanelLibrary.runStartupReconcile());

    change(200, status: RxStatus.success());
  }

  @override
  void onClose() {
    HomePanelLibrary.stopAutoRescanWatcher();
    fnTopNavSearch.removeListener(_onTopNavSearchFocusChanged);
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
    super.onClose();
  }

  Future<void> onRefreshAllContent({bool preserveInputState = false}) async {
    try {
      final sw = Stopwatch()..start();
      footerText.value = preserveInputState ? 'Refreshing (background)...' : 'Refreshing...';

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

      await DBActivity.getCountRelapseToday();
      isDangerMode.value = await DBActivity.getCountRelapseToday() >= AppPref.getAppMaxColi();

      totalVideo.value = await DBVideos.getCount();
      await _syncGamification();
      profile.value = await DBProfile.getProfile() ?? Profile();
      await updateFooterSummary();

      AppLog.logS('${preserveInputState ? 'Refresh Background Content' : 'Refresh All Content'} Take Time: ${sw.elapsedMilliseconds} ms');
      change(200, status: RxStatus.success());
    } catch (e) {
      ExAlert.adaptive(
        title: Text('Ups'),
        content: Text('${e.toString()}'),
        actions: [
          CupertinoDialogAction(
            child: Text('Refresh', style: TextStyle(color: Vx.red500, fontSize: 13)),
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
    currentMenuSelected.value = menu;
  }

  Future<void> updateFooterSummary() async {
    totalVideo.value = await DBVideos.getCount();

    final storage = await _readStorageUsage();
    if (storage == null || storage['total'] == 0) {
      footerText.value = 'Idle | Total Video: ${totalVideo.value}';
      footerStorageText.value = '';
      footerStorageUsedPct.value = 0;
      return;
    }

    final total = storage['total'] ?? 0;
    final free = storage['free'] ?? 0;
    final usedPct = total > 0 ? ((total - free) / total) * 100 : 0;
    footerText.value = 'Idle | Total Video: ${totalVideo.value}';
    footerStorageText.value = ' | Avaiable: ${free.toFileSizeFormat()} (${usedPct.toStringAsFixed(1)}%)';
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
        final search = Get.find<PageSearchController>();
        search.tecSearch.text = query;
        search.filter.reset();
        search.videos.value = localVideos;
        search.allVideos.value = localVideos;
        search.isFresh.value = false;
        search.isSearchMode.value = true;
        currentMenuSelected.value = kMenuSearch;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (search.scrollGridController.hasClients) {
            search.scrollGridController.jumpTo(0);
          }
          search.fnSearch.requestFocus();
        });
        return;
      }

      final download = Get.find<PageDownloadController>();
      download.filter.reset();
      download.tecSearch.text = query;
      download.currentPage.value = 1;
      currentMenuSelected.value = kMenuDownload;
      await download.onSearch(query);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (download.scrollController.hasClients) {
          download.scrollController.jumpTo(0);
        }
        download.fnSearch.requestFocus();
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
  void onDropEnter(DropEvent event) => isDropHovering.value = true;
  void onDropLeave(DropEvent event) => isDropHovering.value = false;
  void onDropEnded(DropEvent event) => isDropHovering.value = false;

  Future<void> onDropEvent(PerformDropEvent event) async {
    isDropHovering.value = false;
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
    } else if (videoPaths.length > 1) {
      unawaited(_openDroppedVideos(videoPaths));
    } else if (videoPaths.length == 1) {
      unawaited(_openDroppedVideo(videoPaths.first));
    } else if (folderPaths.isEmpty && (hasUnsupportedFile || imagePaths.isNotEmpty)) {
      unawaited(HelperToast.warn('File not supported'));
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
      await HelperToast.warn('File not found');
      return;
    }

    await Get.toNamed(Routes.IMG_VIEWER, arguments: {
      'images': images,
      'title': images.length == 1 ? images.first.getLastPath() : 'Image Viewer',
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

  Future<void> _openDroppedVideo(String path) async {
    final video = await _createDroppedVideo(path);
    if (video == null) return;

    await HelperOpener.openVideoFile(video);
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

    await Get.to(() => const PlayerMultiView(), arguments: videos);
  }

  Future<Videos?> _createDroppedVideo(String path) async {
    final decodedPath = _normalizeRawDropPath(path);
    final file = File(decodedPath);
    if (!file.existsSync()) {
      await HelperToast.warn('File not found');
      return null;
    }

    final fileName = decodedPath.getLastPath();
    final cleanTitle = fileName.contains('.') ? fileName.split('.').first : fileName;

    return Videos(
      id: UuidV4().generate(),
      videoPath: decodedPath,
      videoCode: decodedPath.getVideoCode(),
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
  String _watchTimeFormat(int totalSeconds) {
    if (totalSeconds <= 0) return '0 seconds';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    // final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours hours, $minutes minutes';
    }

    if (minutes > 0) {
      return '$minutes minutes';
    }

    return '0 minutes';
  }

  Future<void> onOpenProfile() async {
    final tfName = TextEditingController(text: profile.value.name);
    final fnName = FocusNode();
    
    // profile 
    profile.value = await DBProfile.getProfile() ?? Profile();
    await _syncGamification();

    // relapse
    final relapse = <Activity>[].obs;
    final countWeek = 0.obs;
    final countMonth = 0.obs;
    final countAll = 0.obs;

    relapse.value = await DBActivity.getAllRelapse();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfMonth = DateTime(today.year, today.month, 1);

    var weekTotal = 0;
    var monthTotal = 0;
    var allTotal = 0;

    for (final item in relapse) {
      final rawDate = item.content;
      if (rawDate.isNullOrEmpty) continue;
      final date = rawDate!.toDateEx(format: kYMd);
      final times = item.times ?? 1;

      allTotal += times;
      if (!date.isBefore(startOfWeek)) {
        weekTotal += times;
      }
      if (!date.isBefore(startOfMonth)) {
        monthTotal += times;
      }
    }

    countWeek.value = weekTotal;
    countMonth.value = monthTotal;
    countAll.value = allTotal;

    var isGamificationExpanded = false;

    ExAlert.adaptive(
      title: Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'ⵌ Edit Profile',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size(24, 24),
              child: Icon(CupertinoIcons.xmark, size: 14),
              onPressed: () => Get.back(),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 230,
        child: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CupertinoTextField(
                    controller: tfName,
                    focusNode: fnName,
                    placeholder: 'Your Name',
                    placeholderStyle: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                    prefix: Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(UIconsPro.regularRounded.user, size: 14),
                    ),
                    style: TextStyle(fontSize: 13, color: CupertinoColors.white),
                    onSubmitted: (value) async => await _editProfile(value),
                  ),
                ),

                _profileLine('First Open App: ${profile.value.createdAt?.reformatDate(from: kFull, to: kMdY)}'),
                _profileLine('Total Relapse: ${countAll.value} Times'),
                _profileLine('Watch Time: ${_watchTimeFormat(profile.value.totalWatchDuration ?? 0)}'),
                _profileAccordionHeader(
                  isExpanded: isGamificationExpanded,
                  onTap: () => setState(() => isGamificationExpanded = !isGamificationExpanded),
                ),
                if (isGamificationExpanded) ...[
                  _profileLine('Current Streak: ${streakDays.value} Days'),
                  _profileLine('Achievements: ${achievementCount.value} Unlocked'),
                  _profileLine('Collection Badge: ${(profile.value.badgeForCollection ?? '').isEmpty ? '-' : profile.value.badgeForCollection}'),
                  _profileLine('Watch Badge: ${(profile.value.badgeForWatchDuration ?? '').isEmpty ? '-' : profile.value.badgeForWatchDuration}'),
                  _profileInfoBlock(
                    'Latest Achievement',
                    latestAchievementTitles.isEmpty ? '-' : latestAchievementTitles.join(', '),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 8),
                    child: _profileProgressRow(
                      'Collection',
                      HelperBadge.getCollectionProgress(totalVideo.value),
                      unit: ' vids',
                    ),
                  ),
                  _profileProgressRow(
                    'Watch Time',
                    HelperBadge.getWatchDurationProgress(profile.value.totalWatchDuration ?? 0),
                    unit: 'h',
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Achievements', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            Get.back();
            await onOpenAchievementCenter();
          },
        ),
        CupertinoDialogAction(
          child: Text('Save', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            await _editProfile(tfName.text);
          },
        ),
      ],
    );
  }

  Future<void> _editProfile(String newName) async {
    final _newProfile = profile.value;
    _newProfile.name = newName;
    await DBProfile.update(_newProfile);
    profile.value = await DBProfile.getProfile() ?? Profile();
    await HelperToast.success('Saved');
    Get.back();
  }

  Future<void> _syncGamification() async {
    final summary = await DBGamification.syncAndGetSummary();
    streakDays.value = summary.streakDays;
    achievementCount.value = summary.achievementCount;
    latestAchievementTitles.value = summary.latestAchievements.map((e) => e.title).toList();
    achievementProgress.value = await DBGamification.getAchievementProgress();
  }

  Widget _profileProgressRow(String label, BadgeProgress progress, {String unit = ''}) {
    final statusText = progress.isMaxLevel
        ? 'Max Level'
        : '${progress.currentValue}/${progress.targetValue}$unit to ${progress.nextTitle}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Text('$label Progress', style: TextStyle(fontSize: 10, color: CupertinoColors.systemGrey)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 10),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      _simpleProgressBar(
        progress.percent,
        color: progress.isMaxLevel ? CupertinoColors.systemGreen : CupertinoColors.systemYellow,
      ),
      ],
    );
  }

  Widget _profileLine(String text, {int maxLines = 1}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Text(
        '• $text',
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _profileAccordionHeader({
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: 4, bottom: isExpanded ? 8 : 0),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size(0, 28),
        onPressed: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Gamification',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CupertinoColors.systemPurple),
              ),
            ),
            Text(
              '${achievementCount.value} unlocked',
              style: TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
            ),
            SizedBox(width: 6),
            Icon(
              isExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
              size: 13,
              color: CupertinoColors.systemGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileInfoBlock(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: CupertinoColors.systemGrey)),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _simpleProgressBar(int value, {Color? color, double width = 230, double height = 6}) {
    final percent = value.clamp(0, 100);
    final filledWidth = width * percent / 100;
    final emptyWidth = width - filledWidth;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Container(width: filledWidth, height: height, color: color ?? CupertinoColors.systemYellow),
            Container(width: emptyWidth, height: height, color: CupertinoColors.systemGrey4),
          ],
        ),
      ),
    );
  }

  Widget _achievementProgressBar(int value, {Color? color}) {
    final percent = value.clamp(0, 100);
    return Row(
      children: [
        if (percent > 0) Expanded(flex: percent, child: Container(height: 5, color: color ?? CupertinoColors.systemYellow)),
        if (percent < 100) Expanded(flex: 100 - percent, child: Container(height: 5, color: CupertinoColors.systemGrey4)),
      ],
    );
  }

  Future<void> onOpenAchievementCenter() async {
    await _syncGamification();

    ExAlert.adaptive(
      title: Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Achievements',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size(24, 24),
              child: Icon(CupertinoIcons.xmark, size: 14),
              onPressed: () => Get.back(),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Obx(
          () => Column(
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      '${achievementCount.value}/${achievementProgress.length} Unlocked',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Spacer(),
                    Text(
                      'Streak: ${streakDays.value} Days',
                      style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: achievementProgress.length,
                  separatorBuilder: (context, index) => Container(height: .5, color: CupertinoColors.systemGrey5),
                  itemBuilder: (context, index) {
                    final item = achievementProgress[index];
                    final color = item.isUnlocked ? CupertinoColors.systemGreen : CupertinoColors.systemYellow;
                    final meta = item.isUnlocked
                        ? 'Unlocked ${item.unlockedAt.reformatDate(to: 'yy/MM/dd HH:mm')}'
                        : '${item.currentValue}/${item.targetValue}';

                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              item.isUnlocked ? UIconsPro.solidRounded.badge_check : UIconsPro.regularRounded.lock,
                              size: 16,
                              color: color,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Text(item.group, style: TextStyle(fontSize: 10, color: color)),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    item.description,
                                    style: TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
                                  ),
                                ),
                                SizedBox(
                                  height: 5,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _achievementProgressBar(item.percent, color: color),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(meta, style: TextStyle(fontSize: 10, color: CupertinoColors.systemGrey)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Close', style: TextStyle(fontSize: 13)),
          onPressed: () => Get.back(),
        ),
      ],
    );
  }



  // ────────────────────────────────────────────────────────────────
  // ⵌ playlist
  // ────────────────────────────────────────────────────────────────
  Future<void> getAllPlaylist() async {
    playlist.clear();
    playlist.value = await DBCollection.getAllPlaylist();
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
