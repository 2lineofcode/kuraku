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
import '../../../data/database/library_health_check.dart';
import '../../../data/database/library_reconciler.dart';
import '../../../data/database/library_relocation.dart';
import '../../../data/models/library_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../routes/app_pages.dart';
import '../../../utils/helper_file_picker.dart';
import '../../../utils/helper_media.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_surfaces.dart';
import '../home_controller.dart';
import 'home_panel_library_health.dart';
import 'home_panel_library_relocation.dart';

/// A mixin for managing library-related functionalities in the home screen.
mixin HomePanelLibrary {
  static HomeController get _controller => Get.find<HomeController>();
  static final Map<String, StreamSubscription<FileSystemEvent>> _libraryWatchSubs = {};
  static Timer? _libraryWatchDebounce;
  static Future<void> _libraryScanQueue = Future.value();
  static int _libraryScansPending = 0;
  static int _watchRetries = 0;
  static bool _watchersEnabled = false;
  static const Duration _watchDebounce = Duration(seconds: 3);
  static bool _repairInProgress = false;
  static int _imageAlbumOpen = 0;
  static bool fileDragInProgress = false;
  static bool get canStartFileDrag => !fileDragInProgress && _libraryScansPending == 0;

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
    final isDirectoryEvent = event.isDirectory || Directory(path).existsSync();
    if (isDirectoryEvent) return false;

    return !HelperFilePicker.isSupportedVideoPath(path) && !HelperFilePicker.isSupportedImagePath(path);
  }

  static Future<void> startAutoRescanWatcher() async {
    _watchersEnabled = true;
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
    _watchersEnabled = false;
    for (final sub in _libraryWatchSubs.values) {
      await sub.cancel();
    }
    _libraryWatchSubs.clear();
    _libraryWatchDebounce?.cancel();
    _libraryWatchDebounce = null;
  }

  static Future<void> _syncLibraryWatchers(List<Library> libraries) async {
    if (!_watchersEnabled) return;
    final roots = libraries.map((e) => (e.rootFolder ?? '').trim()).where((e) => e.isNotEmpty).toSet();

    final toRemove = _libraryWatchSubs.keys.where((root) => !roots.contains(root)).toList();
    for (final root in toRemove) {
      await _libraryWatchSubs[root]?.cancel();
      _libraryWatchSubs.remove(root);
    }

    for (final root in roots) {
      if (!_watchersEnabled) return;
      if (_libraryWatchSubs.containsKey(root)) continue;
      final dir = Directory(root);
      if (!dir.existsSync()) continue;

      try {
        final sub = dir.watch(recursive: true).listen((event) {
          if (_shouldIgnoreWatchEvent(event)) return;
          _scheduleAutoRescan();
        }, onError: (e) {
          AppLog.logW('[LibraryWatcher] Watch error for $root: $e');
        });

        _libraryWatchSubs[root] = sub;
      } catch (e) {
        AppLog.logW('[LibraryWatcher] Failed to watch $root: $e');
      }
    }
  }

  static void _scheduleAutoRescan({bool retry = false}) {
    if (!_watchersEnabled) return;
    if (!retry) _watchRetries = 0;
    if (retry && ++_watchRetries > 3) return;
    _libraryWatchDebounce?.cancel();
    _libraryWatchDebounce = Timer(_watchDebounce, _runAutoRescan);
  }

  static Future<void> _runAutoRescan() async {
    if (!_watchersEnabled) return;
    if (fileDragInProgress || _libraryScansPending > 0) {
      _libraryWatchDebounce = Timer(_watchDebounce, _runAutoRescan);
      return;
    }
    try {
      await doRescanAllVideoFromLibrary(await DBLibrary.getAll(), showSummaryToast: false);
    } catch (e) {
      AppLog.logW('[LibraryWatcher] Auto rescan failed: $e');
    }
  }

  /// Displays the library menu as an overlay panel.
  /// This menu shows a list of libraries, allows adding new ones,
  /// and rescanning existing ones.
  static Future<void> open() async {

    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }

    final libraries = await DBLibrary.getAll();
    bool isImageAlbum(Library item) => (item.images?.isNotEmpty ?? false) && (item.totalVideo ?? 0) == 0;
    final videoLibraries = libraries.where((item) => !isImageAlbum(item)).toList();
    final library = [...videoLibraries, ...libraries.where(isImageAlbum)];
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
              AppIconButton(
                tooltip: 'Add New Library'.tr,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
                onPressed: addLibrary,
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
                tooltip: 'Rescan All Folders'.tr,
                onPressed: library.isEmpty ? null : () => confirmAction(
                  'Rescan All Folders'.tr, () => doRescanAllVideoFromLibrary(library, recoverVideoCodes: true),
                ),
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: AppStyle.iconSize),
                tooltip: 'Repair Metadata from R18'.tr,
                onPressed: library.isEmpty ? null : () => confirmAction(
                  'Repair Metadata from R18'.tr, () => _repairAllMetadata(library),
                ),
              ),
              const SizedBox(width: 8),
              AppIconButton(
                tooltip: 'Library Health Check'.tr,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02, size: AppStyle.iconSize),
                onPressed: library.isEmpty ? null : () async {
                  await Overlayment.dismissLast();
                  if (Get.context == null) return;
                  final check = LibraryHealthCheck.run();
                  await showDialog<void>(context: Get.context!,
                    builder: (_) => LibraryHealthDialog(check: check));
                },
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
                      final imageCount = item.images?.length ?? 0;
                      final imageOnly = isImageAlbum(item);
                      final unavailable = imageCount > 0 && !Directory(path).existsSync();
                      final alias = item.alias?.trim().isNotEmpty == true ? item.alias! : p.basename(path);
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (index == 0 || index == videoLibraries.length) ...[
                          if (index > 0) Divider(height: 16, color: AppColor.border),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text((imageOnly ? 'Images' : 'Videos').tr,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColor.muted)),
                          ),
                        ],
                        AppPanel(
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
                                  if (imageOnly) {
                                    await openImageAlbum(item);
                                  } else {
                                    await showDialogAddorEditLibrary(library: item);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(alias, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (!imageOnly) ...[
                                      if (imageCount > 0) Text(
                                        unavailable ? 'Unavailable'.tr : 'Images: @{count}'.trNamed({'count': '$imageCount'}),
                                        style: TextStyle(fontSize: 11, color: AppColor.muted)),
                                      const SizedBox(height: 4),
                                      Tooltip(message: path, child: Text(path.isEmpty ? '<Select Path>'.tr : path.getLastSegments(),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: AppColor.muted))),
                                    ],
                                  ]),
                                ),
                              ),
                            )),
                            if (!imageOnly) Tooltip(
                              message: 'Total Video: @{value}'.trNamed({'value': '${item.totalVideo ?? 0}'}),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(color: AppColor.selected, borderRadius: BorderRadius.circular(AppStyle.radius)),
                                child: Text('${item.totalVideo ?? 0}', style: const TextStyle(fontSize: 11)),
                              ),
                            ),
                            if (imageCount > 0) AppIconButton(
                              icon: HugeIcon(icon: imageOnly ? HugeIcons.strokeRoundedEdit01 : HugeIcons.strokeRoundedImage01, size: AppStyle.iconSize),
                              tooltip: (imageOnly ? 'Edit album' : 'Open image album').tr,
                              onPressed: () async {
                                await Overlayment.dismissLast();
                                if (imageOnly) {
                                  await showDialogAddorEditLibrary(library: item);
                                } else {
                                  await openImageAlbum(item);
                                }
                              },
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
                        ),
                      ]);
                    },
                  )),
            const SizedBox(height: 12),
            AppPanel(
              bordered: true,
              padding: const EdgeInsets.all(8),
              child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
                Text('Total Folder: @{getCount}'.trNamed({'getCount': '${library.length}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
                Text('Total Video: @{getCount}'.trNamed({'getCount': '$totalVideos'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
                if (library.any((item) => item.images?.isNotEmpty ?? false))
                  Text('Images: @{count}'.trNamed({'count': '${library.fold<int>(0, (count, item) => count + (item.images?.length ?? 0))}'}),
                    style: TextStyle(fontSize: 11, color: AppColor.muted)),
              ]),
            ),
          ]).p(AppStyle.panelPadding);
        }),
      ),
    );
  }

  static Future<void> openImageAlbum(Library library) async {
    final request = ++_imageAlbumOpen;
    final route = Get.currentRoute;
    bool cancelled() => request != _imageAlbumOpen || Get.currentRoute != route;
    try {
      final available = await Directory(library.rootFolder ?? '').exists();
      if (cancelled()) return;
      if (!available) {
        await HelperToast.warn('Album folder is unavailable. Reconnect the drive and try again.'.tr);
        return;
      }
      final images = await HelperFilePicker.existingImages(library.images ?? <String>[], cancelled: cancelled);
      if (cancelled()) return;
      if (images.isEmpty) {
        await HelperToast.warn('No image found'.tr);
        return;
      }
      await Get.toNamed(Routes.IMG_VIEWER, arguments: {
        'images': images,
        'title': library.alias ?? p.basename(library.rootFolder ?? ''),
        'albumRoot': library.rootFolder,
      });
    } catch (e) {
      AppLog.logW('Could not open image album: $e');
      if (cancelled()) return;
      await HelperToast.warn('Could not open image album. Check folder permissions and try again.'.tr);
    }
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
    final totalImages = (isFromDrop ? library?.images?.length ?? 0 : 0).obs;

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
                      totalImages.value = path.images?.length ?? 0;
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
            Obx(() => totalImages.value != 0 ? Text('Images: @{count}'.trNamed({'count': '${totalImages.value}'})) : 0.heightBox),
            Obx(() => totalVideo.value != 0 ? Text('Total Video: @{value}'.trNamed({'value': '${totalVideo.value}'})) : 0.heightBox),
          ],
        ),
      ),
      actions: [
        if (library != null && !isFromDrop) ...[
          AppDialogAction(
            child: Text('Relocate Library'.tr),
            onPressed: () {
              Get.back();
              showDialog<void>(context: Get.context!, barrierDismissible: false,
                builder: (_) => LibraryRelocationDialog(library: library, onApply: relocateLibrary));
            },
          ),
          AppDialogAction(
            child: Text('Delete'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              try {
                await _doDeleteVideoFromLibrary(library);
                Get.back();
              } catch (e) {
                await HelperToast.error(e.toString());
              }
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
        await _controller.refreshVideoContent();
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

    final libraries = await DBLibrary.getAll();
    libraries.removeWhere((item) => item.rootFolder == library.rootFolder);
    await doRescanAllVideoFromLibrary([...libraries, library], showSummaryToast: false);

    sw.stop();
    AppLog.logD('Time taken: ${sw.elapsedMilliseconds}ms');
    if (showFinishToast) {
      await HelperToast.success('Library saved'.tr);
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
      newVideo.director = dataDirector?['director'] ?? '';
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
    await _queueLibraryChange(() => DBLibrary.deleteWithVideos(library));
    await startAutoRescanWatcher();
    await _controller.onRefreshAllContent();
  }

  static Future<void> _doRescanVideoFromLibrary(Library library, {bool fromAutoWatcher = true}) async {
    await doRescanAllVideoFromLibrary(await DBLibrary.getAll(),
      showSummaryToast: !fromAutoWatcher, preserveInputState: fromAutoWatcher, recoverVideoCodes: !fromAutoWatcher);
  }

  static Future<void> _queueLibraryChange(Future<void> Function() action) {
    _libraryScansPending++;
    final change = _libraryScanQueue.then((_) async {
      try {
        while (fileDragInProgress) { await Future<void>.delayed(const Duration(milliseconds: 250)); }
        await action();
      } finally {
        _libraryScansPending--;
      }
    });
    _libraryScanQueue = change.then<void>((_) {}, onError: (Object e) {
      AppLog.logE('[Library]: $e');
      _scheduleAutoRescan(retry: true);
    });
    return change;
  }

  static Future<void> relocateLibrary(LibraryRelocation preview) => _queueLibraryChange(() async {
    await preview.apply();
    // The relocation is already committed; a UI refresh failure must not report a rollback.
    try {
      await _syncLibraryWatchers(await DBLibrary.getAll());
      if (!Get.isRegistered<HomeController>() || _controller.isClosed) return;
      await _controller.updateFooterSummary();
      await _controller.refreshVideoContent();
    } catch (e) {
      AppLog.logE('[Library] Relocation refresh failed: $e');
    }
  });

  static Future<void> doRescanAllVideoFromLibrary(
    List<Library> libraries, {
    bool showSummaryToast = true,
    bool preserveInputState = true,
    bool recoverVideoCodes = false,
  }) {
    return _queueLibraryChange(() async {
        if (!Get.isRegistered<HomeController>() || _controller.isClosed) return;
        if (libraries.isEmpty) return;
        _controller.footerText.value = '◎ Rescanning...'.tr;
        final snapshots = <Library>[];
        for (final library in libraries) {
          final saved = (library.id ?? '').isEmpty ? null : await DBLibrary.getByID(library.id!);
          if (saved != null && saved.isEmpty) continue;
          final current = saved?.single ?? library;
          try {
            final scanned = await HelperFilePicker.scanFolderAndSubFolder(current.rootFolder ?? '');
            if (scanned == null) continue;
            snapshots.add(Library.fromJson(current.toJson())
              ..images = scanned.images..videos = scanned.videos..subFolder = scanned.subFolder..totalVideo = scanned.totalVideo);
          } catch (e) {
            AppLog.logW('[RescanAll] Could not access folder: ${library.rootFolder}. Skipping this library.');
          }
        }
        if (snapshots.isEmpty) return;
        final result = await LibraryReconciler.reconcile(snapshots, prepareVideos: _prepareVideos);
        if (!Get.isRegistered<HomeController>() || _controller.isClosed) return;
        var recovered = 0;
        if (recoverVideoCodes) {
          for (final library in snapshots) { recovered += await DBVideos.recoverMissingVideoCodes(library.rootFolder!); }
        }
        if (result.retry) _scheduleAutoRescan(retry: true);
        await _syncLibraryWatchers(await DBLibrary.getAll());
        await _controller.updateFooterSummary();
        if (showSummaryToast) {
          await HelperToast.info('Finish • @{added} added • @{missing} missing • @{moved} moved'.trNamed({
            'added': '${result.added}', 'missing': '${result.missing}', 'moved': '${result.moved}',
          }));
        }
        if (result.changed || recovered > 0) {
          await _controller.refreshVideoContent();
          if (!preserveInputState) await _controller.onRefreshAllContent();
        }
    });
  }

  static Future<void> _getVideoResolution(Videos video) async {
    if (!Platform.isLinux) {
      try {
        final medInfo = await VideoCompress.getMediaInfo(video.videoPath!);
        if ((medInfo.width ?? 0) > 0 && (medInfo.height ?? 0) > 0) {
          video.quality = '${medInfo.width}x${medInfo.height}';
          return;
        }
      } catch (e) {
        AppLog.logD('error, try (ffmpeg) way -> ${video.videoPath}');
      }
    }
    try {
      final session = await FFprobeKit.getMediaInformation(video.videoPath!);
      final stream = HelperMedia.videoStream(await HelperMedia.readInformation(session));
      if (stream != null) video.quality = '${stream.getWidth()}x${stream.getHeight()}';
    } catch (e) {
      AppLog.logW('Could not read video resolution [${video.videoPath}]: $e');
    }
  }

}
