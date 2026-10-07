import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;
import 'package:video_compress/video_compress.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_translations.dart';
import '../../../core/const.dart';
import '../../../data/database/_init_db.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/library_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_file_picker.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
import '../home_controller.dart';

/// A mixin for managing library-related functionalities in the home screen.
mixin HomePanelLibrary {
  static final _controller = Get.find<HomeController>();
  static final Map<String, StreamSubscription<FileSystemEvent>> _libraryWatchSubs = {};
  static final Map<String, Timer> _libraryWatchDebounce = {};
  static final Set<String> _libraryRescanInProgress = {};
  static const Duration _watchDebounce = Duration(seconds: 3);
  static bool _repairInProgress = false;
  static bool fileDragInProgress = false;
  static bool get canStartFileDrag => !fileDragInProgress && _libraryRescanInProgress.isEmpty;

  static bool _isSupportedVideoPath(String path) {
    final pth = path.toLowerCase();
    return pth.endsWith('.mp4')
        || pth.endsWith('.mkv')
        || pth.endsWith('.avi')
        || pth.endsWith('.mov')
        || pth.endsWith('.wmv')
        || pth.endsWith('.flv')
        || pth.endsWith('.webm')
        || pth.endsWith('.m4v');
  }

  static bool _shouldIgnoreWatchEvent(FileSystemEvent event) {
    final path = event.path;
    if (path.isEmpty) return true;

    final lower = path.toLowerCase();
    if (lower.contains('/.ds_store') || lower.contains('/.tras') || lower.contains('/@eaDir'.toLowerCase())) {
      return true;
    }

    if (lower.endsWith('.part') || lower.endsWith('.tmp') || lower.endsWith('.crdownload')) {
      return true;
    }

    // Folder move/rename events may not carry video extension.
    // Keep watcher responsive by allowing directory events to trigger rescan.
    final isDirectoryEvent = Directory(path).existsSync();
    if (isDirectoryEvent) return false;

    return !_isSupportedVideoPath(path);
  }

  static Future<void> startAutoRescanWatcher() async {
    final libraries = await DBLibrary.getAll();
    await _syncLibraryWatchers(libraries);
  }

  static Future<void> runStartupReconcile() async {
    final libraries = await DBLibrary.getAll();
    if (libraries.isEmpty) return;

    await doRescanAllVideoFromLibrary(
      libraries,
      showSummaryToast: false,
      preserveInputState: true,
    );
  }

  static Future<void> stopAutoRescanWatcher() async {
    for (final sub in _libraryWatchSubs.values) {
      await sub.cancel();
    }
    _libraryWatchSubs.clear();
    for (final t in _libraryWatchDebounce.values) {
      t.cancel();
    }
    _libraryWatchDebounce.clear();
    _libraryRescanInProgress.clear();
  }

  static Future<void> _syncLibraryWatchers(List<Library> libraries) async {
    final roots = libraries.map((e) => (e.rootFolder ?? '').trim()).where((e) => e.isNotEmpty).toSet();

    final toRemove = _libraryWatchSubs.keys.where((root) => !roots.contains(root)).toList();
    for (final root in toRemove) {
      await _libraryWatchSubs[root]?.cancel();
      _libraryWatchSubs.remove(root);
      _libraryWatchDebounce.remove(root)?.cancel();
    }

    for (final root in roots) {
      if (_libraryWatchSubs.containsKey(root)) continue;
      final dir = Directory(root);
      if (!dir.existsSync()) continue;

      try {
        final sub = dir.watch(recursive: true).listen((event) {
          if (_shouldIgnoreWatchEvent(event)) return;
          _libraryWatchDebounce[root]?.cancel();
          _libraryWatchDebounce[root] = Timer(_watchDebounce, () async {
            await _runAutoRescanForRoot(root);
          });
        }, onError: (e) {
          AppLog.logW('[LibraryWatcher] Watch error for $root: $e');
        });

        _libraryWatchSubs[root] = sub;
      } catch (e) {
        AppLog.logW('[LibraryWatcher] Failed to watch $root: $e');
      }
    }
  }

  static Future<void> _runAutoRescanForRoot(String root) async {
    if (fileDragInProgress) {
      _libraryWatchDebounce[root] = Timer(_watchDebounce, () => _runAutoRescanForRoot(root));
      return;
    }
    if (_libraryRescanInProgress.contains(root)) return;
    _libraryRescanInProgress.add(root);
    try {
      final libraries = await DBLibrary.getAll();
      final library = libraries.firstWhereOrNull((e) => (e.rootFolder ?? '').trim() == root);
      if (library == null) return;

      AppLog.logD('[LibraryWatcher] Auto rescan triggered for: ${library.alias ?? root}');
      await _doRescanVideoFromLibrary(library, fromAutoWatcher: true);
    } catch (e) {
      AppLog.logW('[LibraryWatcher] Auto rescan failed for $root: $e');
    } finally {
      _libraryRescanInProgress.remove(root);
    }
  }

  /// Displays the library menu as an overlay panel.
  /// This menu shows a list of libraries, allows adding new ones,
  /// and rescanning existing ones.
  static Future<void> open() async {

    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }

    final library = await DBLibrary.getAll();
    final totalVideos = await DBVideos.getCount();

    Future<void> addLibrary() async {
      await Overlayment.dismissLast();
      await showDialogAddorEditLibrary();
    }

    Future<void> confirmAction(String title, Future<void> Function() action) async {
      await Overlayment.dismissLast();
      AppConfirmDialog.show(
        isDismissible: false,
        title: Text(title),
        content: Text('Are you sure?'.tr).pOnly(top: 8),
        actions: [
          AppDialogAction(child: Text('No'.tr), onPressed: () => Get.back()),
          AppDialogAction(child: Text('Yes'.tr), onPressed: () async {
            Get.back();
            await action();
          }),
        ],
      );
    }

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: math.min(340, MediaQuery.sizeOf(Get.context!).width),
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        child: Builder(builder: (context) {
          AppColor.dependOn(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const HugeIcon(icon: HugeIcons.strokeRoundedLayers01, size: AppStyle.iconSize),
              const SizedBox(width: 8),
              Expanded(child: Text('Library'.tr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              AppIconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize),
                tooltip: 'Close'.tr,
                onPressed: () => Overlayment.dismissLast(),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: AppButton(
                label: 'Add New Library'.tr,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
                variant: AppButtonVariant.tonal,
                onPressed: addLibrary,
              )),
              const SizedBox(width: 8),
              AppIconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
                tooltip: 'Rescan All Folders'.tr,
                onPressed: library.isEmpty ? null : () => confirmAction(
                  'Rescan All Folders'.tr, () => doRescanAllVideoFromLibrary(library, recoverVideoCodes: true),
                ),
              ),
              AppIconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: AppStyle.iconSize),
                tooltip: 'Repair Metadata from R18'.tr,
                onPressed: library.isEmpty ? null : () => confirmAction(
                  'Repair Metadata from R18'.tr, () => _repairAllMetadata(library),
                ),
              ),
            ]),
            Divider(height: 24, color: AppColor.border),
            Expanded(child: library.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedInbox, size: AppStyle.emptyIconSize, color: AppColor.muted),
                    const SizedBox(height: 12),
                    Text('No Data'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('No Library Found, Please Add New Library by Click Button `+`'.tr,
                      textAlign: TextAlign.center, style: TextStyle(fontSize: AppStyle.fontSize, color: AppColor.muted)),
                  ]))
                : ListView.separated(
                    itemCount: library.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = library[index];
                      final path = item.rootFolder ?? '';
                      final alias = item.alias?.trim().isNotEmpty == true ? item.alias! : p.basename(path);
                      return AppPanel(
                        bordered: true,
                        padding: const EdgeInsets.all(4),
                        child: Row(children: [
                          AppIconButton(
                            onPressed: path.isEmpty ? null : () => HelperOpener.openFolder(path),
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: AppStyle.iconSize),
                            tooltip: 'Open Folder `@{alias}`'.trNamed({'alias': alias}),
                          ),
                          const SizedBox(width: 4),
                          Expanded(child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppStyle.radius),
                              onTap: () async {
                                await Overlayment.dismissLast();
                                await showDialogAddorEditLibrary(library: item);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(alias, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Tooltip(message: path, child: Text(path.isEmpty ? '<Select Path>'.tr : path.getLastSegments(),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: AppColor.muted))),
                                ]),
                              ),
                            ),
                          )),
                          Tooltip(
                            message: 'Total Video: @{value}'.trNamed({'value': '${item.totalVideo ?? 0}'}),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(color: AppColor.selected, borderRadius: BorderRadius.circular(AppStyle.radius)),
                              child: Text('${item.totalVideo ?? 0}', style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                          AppIconButton(
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
                            tooltip: 'Rescan Folder `@{alias}`'.trNamed({'alias': alias}),
                            onPressed: path.isEmpty ? null : () async {
                              await Overlayment.dismissLast();
                              await _doRescanVideoFromLibrary(item, fromAutoWatcher: false);
                            },
                          ),
                        ]),
                      );
                    },
                  )),
            const SizedBox(height: 12),
            AppPanel(
              bordered: true,
              padding: const EdgeInsets.all(8),
              child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
                Text('Total Folder: @{getCount}'.trNamed({'getCount': '${library.length}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
                Text('Total Video: @{getCount}'.trNamed({'getCount': '$totalVideos'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
              ]),
            ),
          ]).p(AppStyle.panelPadding);
        }),
      ),
    );
  }

  /// Opens a dialog to add or edit a library.
  /// This dialog handles input for the library's alias and root path.
  static Future<void> showDialogAddorEditLibrary({Library? library, bool isFromDrop = false}) async {
    final tfAlias = TextEditingController(text: library?.alias);
    final tfRootPath = TextEditingController(text: library?.rootFolder);
    final fnRootPath = FocusNode();
    final fnAlias = FocusNode();
    final librarySelected = Library().obs;
    final isClicked = false.obs;
    final totalVideo = 0.obs;

    if (isFromDrop) fnAlias.requestFocus();

    AppConfirmDialog.show(
      isDismissible: false,
      title: HStack(
        [
          Text(
            library != null ? 'ⵌ Edit `@{alias}`'.trNamed({'alias': '${library.alias}'}) : 'ⵌ New'.tr,
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
          ).expand(),
          AppIconButton(tooltip: 'Close'.tr, icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize), onPressed: Get.back),
        ],
      ).pOnly(bottom: 16),
      content: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 90),
        child: VStack(
          [
            AppTextField(
              readOnly: true,
              controller: tfRootPath,
              focusNode: fnRootPath,
              placeholder: '<Select Path>'.tr,
              placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
              prefix: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: AppStyle.iconSize).pOnly(left: 8),
              style: TextStyle(color: Vx.neutral500),
              onTap: () async {
                if (isClicked.value) return;
                if (library == null) {
                  isClicked.value = true;
                  await HelperFilePicker.pickFolderSubFolder().then((path) {
                    if (path != null) {
                      librarySelected.value = path;
                      tfAlias.text = path.alias?.toTitleCase ?? '';
                      tfRootPath.text = path.rootFolder ?? '';
                      totalVideo.value = path.videos?.length ?? 0;
                    }
                    isClicked.value = false;
                  });

                  fnAlias.requestFocus();
                }
              },
            ).pOnly(bottom: 16),
            AppTextField(
              controller: tfAlias,
              focusNode: fnAlias,
              placeholder: 'Alias'.tr,
              placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
              prefix: HugeIcon(icon: HugeIcons.strokeRoundedTag01, size: AppStyle.iconSize).pOnly(left: 8),
              style: TextStyle(color: AppColor.text),
              onSubmitted: (value) async {
                await _onSubmit(
                  alias: tfAlias.text,
                  rootPath: tfRootPath.text,
                  library: library,
                  isFromDrop: isFromDrop,
                  librarySelected: librarySelected.value,
                );
              },
            ).pOnly(bottom: 16),
            Obx(() => totalVideo.value != 0 ? Text('Total Video: @{value}'.trNamed({'value': '${totalVideo.value}'})) : 0.heightBox),
          ],
        ),
      ),
      actions: [
        if (library != null && !isFromDrop) ...[
          AppDialogAction(
            child: Text('Delete'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () {
              DBLibrary.delete(library);
              _doDeleteVideoFromLibrary(library);
              Get.back();
            },
          ),
        ],

        AppDialogAction(
          child: Text('Submit'.tr, style: TextStyle(fontSize: 13)),
          onPressed: () async {
            await _onSubmit(
              alias: tfAlias.text,
              rootPath: tfRootPath.text,
              library: library,
              isFromDrop: isFromDrop,
              librarySelected: librarySelected.value,
            );
          },
        ),
      ],
    );
  }

  /// Handles the submission logic for adding or editing a library.
  /// Validates input and performs the appropriate database operations.
  static Future<void> _onSubmit({
    required String alias,
    required String rootPath,
    required Library? library,
    required bool isFromDrop,
    required Library librarySelected,
  }) async {
    // Validate fields
    if (alias.isEmpty || rootPath.isEmpty) {
      await HelperToast.error('Please fill all field'.tr);
      return;
    }

    // Edit mode
      if (library != null) {
        library.alias = alias;
        library.rootFolder = rootPath;

      if (isFromDrop) {
        Get.back();
        await _doAddorEditVideoFromLibrary(library);
      } else {
        Get.back();
        await DBLibrary.update(library);
        await startAutoRescanWatcher();
      }
      return;
    }

    // Add mode
    librarySelected.alias = alias;
    Get.back();
    await _doAddorEditVideoFromLibrary(librarySelected);
    await startAutoRescanWatcher();
  }


  // ────────────────────────────────────────────────────────────────
  // ** MAIN PROCESSES
  /// Processes and adds/edits videos from a specific library.
  /// Scans for video files and updates the database with metadata if available.
  // ────────────────────────────────────────────────────────────────
  static Future<void> _doAddorEditVideoFromLibrary(
    Library library, {
    bool refreshAfter = true,
    bool showFinishToast = true,
    bool showLoading = true,
  }) async {
    AppLog.logD('Start processing library: ${library.alias}');
    final sw = Stopwatch();
    sw.start();

    if (showLoading) {
      _controller.footerText.value = '◎ Scanning and processing videos...'.tr;
      _controller.change(200, status: RxStatus.loading());
    }

    final videosToAdd = await _prepareVideos(library);
    await DBLibrary.commitScan([library], additions: videosToAdd);

    sw.stop();
    AppLog.logD('Time taken: ${sw.elapsedMilliseconds}ms');
    if (showFinishToast) {
      await HelperToast.success('Finish • @{elapsedMilliseconds}ms | @{length} Videos Added'.trNamed({'elapsedMilliseconds': '${sw.elapsedMilliseconds}', 'length': '${videosToAdd.length}'}));
    }

    if (refreshAfter) {
      await _controller.onRefreshAllContent();
    }
  }

  static Future<List<Videos>> _prepareVideos(Library library) async {
    final videos = library.videos ?? const <String>[];
    final totalVideos = videos.length;
    final videosToAdd = <Videos>[];
    var processedCounter = 0;
    var cursor = 0;
    final workerCount = math.min(6, totalVideos);

    final workers = List.generate(workerCount, (_) async {
      while (true) {
        if (cursor >= totalVideos) break;
        final currentIndex = cursor;
        cursor++;

        final videoPath = videos[currentIndex];
        final processedVideo = await processVideo(videoPath, library.rootFolder);
        if (processedVideo != null) {
          videosToAdd.add(processedVideo);
        }

        processedCounter++;
        if (processedCounter % 1 == 0 || processedCounter == totalVideos) {
          _controller.loadingText.value = 'Progress: @{processedCounter} of @{totalVideos} (@{toInt}%)'.trNamed({'processedCounter': '$processedCounter', 'totalVideos': '$totalVideos', 'toInt': '${(processedCounter * 100 / totalVideos).toInt()}'});
        }
      }
    });
    await Future.wait(workers);

    return videosToAdd;
  }

  static Future<void> _repairAllMetadata(List<Library> libraries) async {
    if (_repairInProgress) return;
    if (Get.find<DBService>().dbR18 == null) {
      await HelperToast.warn('R18 database is unavailable. Download it from Settings first.'.tr);
      return;
    }
    _repairInProgress = true;
    var updated = 0;
    var skipped = 0;
    var failed = 0;
    try {
      final roots = libraries.map((library) => library.rootFolder).toSet();
      final videos = (await DBVideos.getAll()).where((video) => roots.contains(video.rootPath)).toList();
      _controller.change(200, status: RxStatus.loading());
      for (var i = 0; i < videos.length; i++) {
        _controller.footerText.value = 'Repairing metadata from R18...'.tr;
        _controller.loadingText.value = 'Progress: @{i} of @{length}'.trNamed({'i': '${i + 1}', 'length': '${videos.length}'});
        try {
          if (await repairVideoMetadata(videos[i])) {
            updated++;
          } else {
            skipped++;
          }
        } catch (e) {
          failed++;
          AppLog.logE('[RepairMetadata] ${videos[i].videoPath}: $e');
        }
      }
      await _controller.onRefreshAllContent();
      await Get.forceAppUpdate();
      await HelperToast.info('Metadata • @{updated} updated • @{skipped} skipped • @{failed} failed'.trNamed({'updated': '$updated', 'skipped': '$skipped', 'failed': '$failed'}));
    } catch (e) {
      await HelperToast.error('Metadata repair failed: @{e}'.trNamed({'e': '$e'}));
    } finally {
      _repairInProgress = false;
      _controller.change(200, status: RxStatus.success());
      await _controller.updateFooterSummary();
    }
  }

  @visibleForTesting
  static Future<bool> repairVideoMetadata(Videos video) async {
    final code = HelperMisc.resolveVideoCode(videoCode: video.videoCode, videoPath: video.videoPath, title: video.title);
    if (code.isEmpty) return false;
    final metadata = await processVideo(video.videoPath ?? '', video.rootPath, code: code, metadataOnly: true);
    if (metadata == null) return false;
    return await DBVideos.updateMetadata(video, metadata) > 0;
  }

  // ** PROCESS VIDEO
  @visibleForTesting
  static Future<Videos?> processVideo(String videoPath, String? rootFolder, {String? code, bool metadataOnly = false}) async {
    final videoCode = code ?? videoPath.getFileName().getVideoCode();
    if (metadataOnly && videoCode.isEmpty) return null;

    // case: detect as JAV
    if (videoCode.isNotEmpty) {
      final results = await Future.wait([
        DBR18.getVideo(videoCode),
        DBR18.getCategory(videoCode),
        DBR18.getActress(videoCode),
        DBR18.getDirector(videoCode),
      ]);

      final dataVideo = results[0] as Map<String, dynamic>?;
      final dataCategory = results[1] as List<dynamic>;
      final dataActress = results[2] as List<dynamic>;
      final dataDirector = results[3] as Map<String, dynamic>?;

      // case: detect as JAV but no data in R18
      if (dataVideo == null) {
        if (metadataOnly) return null;
        final newVideo = Videos();
        newVideo.videoCode = videoCode;
        newVideo.rootPath = rootFolder ?? '';
        newVideo.videoPath = videoPath;
        newVideo.title = videoPath.getFileName().noExt();

        final file = File(videoPath);
        if (file.existsSync()) newVideo.filesize = file.lengthSync();
        if (!HelperMisc.isExternalDrive(newVideo.videoPath)) await _getVideoResolution(newVideo);

        return newVideo;
      }

      final newVideo = Videos.fromJson(dataVideo);
      newVideo.rootPath = rootFolder ?? '';
      newVideo.videoPath = videoPath;
      newVideo.category = dataCategory.map((e) => VideoCategory.fromJson(e)).toList();
      newVideo.actress = dataActress.map((e) => VideoActress.fromJson(e)).toList();
      newVideo.durationFormated = HelperMisc.durationFormatDB(newVideo.duration ?? 0);
      newVideo.releaseDateFormated = newVideo.releaseDate.isNotEmptyAndNotNull
          ? newVideo.releaseDate!.reformatDate(from: kYMd, to: kMdY) : '';
      newVideo.director = dataDirector?['name_romaji'] ?? '';
      newVideo.fanArt = dataVideo['fan_art'] ?? '';
      newVideo.poster = dataVideo['poster'] ?? '';

      // logic for screenshot
      if (dataVideo['sslast'] != null && dataVideo['ssfirst'] != null) {
        final screenshots = <String>[];
        final total = int.tryParse(dataVideo['sslast'].toString().split('-').last) ?? 0;
        final filename = dataVideo['ssfirst'].toString();
        final base = filename.contains('jp-') ? filename.removeLast(1) : '${filename.allBefore('-')}jp-';

        if (total > 0) {
          for (var i = 1; i <= total; i++) {
            screenshots.add('$base$i');
          }
          newVideo.screenshot = screenshots;
        }
      }

      if (!metadataOnly) {
        final file = File(videoPath);
        if (file.existsSync()) newVideo.filesize = file.lengthSync();
        if (!HelperMisc.isExternalDrive(newVideo.videoPath)) await _getVideoResolution(newVideo);
      }

      return newVideo;
    }

    // case: not detect as JAV
    else {
      final newVideo = Videos();
      newVideo.rootPath = rootFolder ?? '';
      newVideo.videoPath = videoPath;
      newVideo.title = videoPath.getFileName().noExt();

      final file = File(videoPath);
      if (file.existsSync()) newVideo.filesize = file.lengthSync();
      if (!HelperMisc.isExternalDrive(newVideo.videoPath)) await _getVideoResolution(newVideo);

      return newVideo;
    }
  }

  // ────────────────────────────────────────────────────────────────
  /// Deletes all videos associated with a specific library.
  // ────────────────────────────────────────────────────────────────
  static Future<void> _doDeleteVideoFromLibrary(Library library) async {
    await Get.find<DBService>().dbMain.transaction((txn) async {
      await txn.delete('videos', where: 'root_path = ?', whereArgs: [library.rootFolder]);
      await txn.delete('library', where: 'id = ?', whereArgs: [library.id]);
    });
    await startAutoRescanWatcher();
    await _controller.onRefreshAllContent();
  }

  // ────────────────────────────────────────────────────────────────
  // Rescan Single library
  // workflow:
  // - Scan folder (library.rootFolder) selected
  // - compare old data with new data
  // - collect (add, delete, update)
  // - update library
  // ────────────────────────────────────────────────────────────────
  static Future<void> _doRescanVideoFromLibrary(Library library, {bool fromAutoWatcher = true}) async {
    try {
      final oldData = library;
      final newData = await HelperFilePicker.scanFolderAndSubFolder(library.rootFolder ?? '');

      if (newData == null) return;

      final pathToAdd = <String>[];
      final pathToDelete = <String>[];
      final stored = await DBVideos.getAll(where: 'root_path = ?', whereArgs: [oldData.rootFolder]);
      final oldVideos = stored.map((video) => video.videoPath!).toSet();
      final newVideos = Set<String>.from(newData.videos ?? const <String>[]);

      pathToAdd.addAll(newVideos.difference(oldVideos));
      pathToDelete.addAll(oldVideos.difference(newVideos));

      final moves = <Map<String, String>>[];
      final remainingAdds = <String>[];
      final remainingDeletes = List<String>.from(pathToDelete);
      final delByName = <String, List<String>>{};

      for (final oldPath in pathToDelete) {
        final name = p.basename(oldPath);
        delByName.putIfAbsent(name, () => []).add(oldPath);
      }

      for (final newPath in pathToAdd) {
        final name = p.basename(newPath);
        final candidates = delByName[name];
        if (candidates != null && candidates.isNotEmpty) {
          final matchedOldPath = candidates.removeAt(0);
          moves.add({
            'oldRoot': oldData.rootFolder ?? '',
            'oldPath': matchedOldPath,
            'newRoot': oldData.rootFolder ?? '',
            'newPath': newPath,
          });
          remainingDeletes.remove(matchedOldPath);
        } else {
          remainingAdds.add(newPath);
        }
      }

      final additions = await _prepareVideos(Library(videos: remainingAdds, rootFolder: oldData.rootFolder));
      final snapshot = Library.fromJson(oldData.toJson())
        ..totalVideo = newData.totalVideo
        ..videos = newData.videos
        ..subFolder = newData.subFolder;
      await DBLibrary.commitScan([snapshot], additions: additions, moves: moves, deletedPaths: remainingDeletes);
      oldData.totalVideo = snapshot.totalVideo;
      oldData.videos = snapshot.videos;
      oldData.subFolder = snapshot.subFolder;
      oldData.updatedAt = snapshot.updatedAt;

      final recovered = fromAutoWatcher ? 0 : await DBVideos.recoverMissingVideoCodes(oldData.rootFolder ?? '');
      if (recovered > 0) await HelperToast.info('@{recovered} video codes recovered'.trNamed({'recovered': '$recovered'}));
      if (moves.isNotEmpty || remainingAdds.isNotEmpty || remainingDeletes.isNotEmpty || recovered > 0) {
        await _controller.onRefreshAllContent(preserveInputState: fromAutoWatcher);
      }
    } catch (e) {
      AppLog.logE(e);
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Rescan All libraries (detect cross-library moves by basename)
  // ────────────────────────────────────────────────────────────────
  static Future<void> doRescanAllVideoFromLibrary(
    List<Library> libraries, {
    bool showSummaryToast = true,
    bool preserveInputState = true,
    bool recoverVideoCodes = false,
  }) async {
    try {
      if (libraries.isEmpty) return;

      _controller.footerText.value = '◎ Rescanning...'.tr;

      // Compare scans against committed video rows so interrupted imports can retry.
      final Map<String, List<String>> oldMap = {};
      for (final lib in libraries) {
        final stored = await DBVideos.getAll(where: 'root_path = ?', whereArgs: [lib.rootFolder]);
        oldMap[lib.rootFolder ?? ''] = stored.map((video) => video.videoPath!).toList();
      }

      // 2) Scan all roots and build newMap
      final Map<String, List<String>> newMap = {};
      final Map<String, int> newTotal = {};
      final Map<String, List<String>?> newSubFolders = {};

      // We also need to track which libraries were successfully scanned.
      final List<Library> scannedLibraries = [];

      for (final lib in libraries) {
        final root = lib.rootFolder ?? '';

        try {
          final newData = await HelperFilePicker.scanFolderAndSubFolder(root);

          if (newData != null) {
            final newList = newData.videos ?? [];
            newMap[root] = List<String>.from(newList);
            newTotal[root] = (newData.totalVideo ?? 0).toInt();
            newSubFolders[root] = newData.subFolder;
            scannedLibraries.add(lib);
          }
        } catch (e) {
          AppLog.logW('[RescanAll] Could not access folder: $root. Skipping this library.');
        }
      }

      // 3) Build global candidate lists
      final List<Map<String, String>> addCandidates = []; // {root, path}
      final List<Map<String, String>> delCandidates = []; // {root, path}

      // adds: present in newMap[root] but not in oldMap[root]
      for (final root in newMap.keys) {
        final newList = newMap[root]!;
        final oldList = oldMap[root] ?? [];
        for (final nv in newList) {
          if (!oldList.contains(nv)) {
            addCandidates.add({'root': root, 'path': nv});
          }
        }
      }

      // deletes: present in oldMap[root] but not in newMap[root]
      for (final root in oldMap.keys) {
        final oldList = oldMap[root] ?? [];
        final newList = newMap[root] ?? [];

        // This is the key change: only process if the root was in newMap (i.e., successfully scanned)
        if (newMap.containsKey(root)) {
          for (final ov in oldList) {
            if (!newList.contains(ov)) {
              delCandidates.add({'root': root, 'path': ov});
            }
          }
        }
      }

      // 4) Match addCandidates <-> delCandidates by basename => moves
      final List<Map<String, String>> moves = []; // {oldRoot, oldPath, newRoot, newPath}

      // create index by basename for deletes for quick lookup
      final Map<String, List<Map<String, String>>> delByName = {};
      for (final del in delCandidates) {
        final name = p.basename(del['path']!);
        delByName.putIfAbsent(name, () => []).add(del);
      }

      final List<Map<String, String>> remainingAdds = [];
      for (final add in addCandidates) {
        final name = p.basename(add['path']!);
        final delsForName = delByName[name];
        if (delsForName != null && delsForName.isNotEmpty) {
          // match to first available delete for that basename
          final matchedDel = delsForName.removeAt(0);
          moves.add({
            'oldRoot': matchedDel['root']!,
            'oldPath': matchedDel['path']!,
            'newRoot': add['root']!,
            'newPath': add['path']!,
          });

          // also remove this del from delCandidates list (so it won't be deleted later)
          delCandidates.removeWhere((d) => d['path'] == matchedDel['path']);
        } else {
          remainingAdds.add(add);
        }
      }

      // Prepare metadata outside the transaction.
      final additions = <Videos>[];

      // Group pending additions by root.
      final Map<String, List<String>> addsByRoot = {};
      for (final a in remainingAdds) {
        final root = a['root']!;
        addsByRoot.putIfAbsent(root, () => []).add(a['path']!);
      }
      for (final entry in addsByRoot.entries) {
        final root = entry.key;
        final list = entry.value;
        final libToAdd = Library(videos: list, rootFolder: root);
        additions.addAll(await _prepareVideos(libToAdd));
      }

      // Commit moves, additions, deletions and snapshots together.
      final delPaths = List<String>.from(
        List<Map<String, String>>.from(delCandidates).map((d) => d['path'] ?? '').where((p) => p.isNotEmpty),
      );


      final snapshots = scannedLibraries.map((lib) => Library.fromJson(lib.toJson())
        ..totalVideo = newTotal[lib.rootFolder]
        ..videos = newMap[lib.rootFolder]
        ..subFolder = newSubFolders[lib.rootFolder]).toList();
      final movedUpdatedRows = await DBLibrary.commitScan(snapshots, additions: additions, moves: moves, deletedPaths: delPaths);
      var recovered = 0;
      for (var i = 0; i < scannedLibraries.length; i++) {
        final lib = scannedLibraries[i];
        lib.totalVideo = snapshots[i].totalVideo;
        lib.videos = snapshots[i].videos;
        lib.subFolder = snapshots[i].subFolder;
        lib.updatedAt = snapshots[i].updatedAt;
        if (recoverVideoCodes) recovered += await DBVideos.recoverMissingVideoCodes(lib.rootFolder!);
      }

      // 9) Summary log
      AppLog.logD('[RescanAll] Finished | Adds=${remainingAdds.length}, Deletes=${delCandidates.length}, Moves=${moves.length}, MoveUpdated=$movedUpdatedRows');
      for (final mv in moves) {
        AppLog.logD('[RescanAll] Move ${mv['oldPath']} -> ${mv['newPath']}');
      }

      await _controller.updateFooterSummary();

      if (remainingAdds.isNotEmpty || delCandidates.isNotEmpty || moves.isNotEmpty || recovered > 0) {
        if (showSummaryToast) {
          await HelperToast.info('Finish • @{length} added • @{length2} deleted • @{length3} moved • @{recovered} codes recovered'.trNamed({'length': '${remainingAdds.length}', 'length2': '${delCandidates.length}', 'length3': '${moves.length}', 'recovered': '$recovered'}));
        }
        await _controller.onRefreshAllContent(preserveInputState: preserveInputState);
      }
    } catch (e) {
      AppLog.logE('[RescanAll]: $e');
    }
  }

  static Future<void> _getVideoResolution(Videos video) async {
    try {
      final medInfo = await VideoCompress.getMediaInfo(video.videoPath!);
      if (medInfo.width == null) return;
      video.quality = '${medInfo.width}x${medInfo.height}';
    } catch (e) {
      AppLog.logD('error, try (ffmpeg) way -> ${video.videoPath}');
      await FFprobeKit.getMediaInformation(video.videoPath!).then((medInfo) {
        if (medInfo.getMediaInformation() == null) return;
        final streams = medInfo.getMediaInformation()?.getStreams();
        if (streams == null || streams.isEmpty) return;
        final stream = streams.firstWhere(
          (s) => s.getWidth() != null && s.getHeight() != null,
          orElse: () => streams.first,
        );
        if (stream.getWidth() != null && stream.getHeight() != null) {
          video.quality = '${stream.getWidth()}x${stream.getHeight()}';
        }
      });
    }
  }

}
