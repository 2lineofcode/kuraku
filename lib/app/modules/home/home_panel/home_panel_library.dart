import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;
import 'package:uicons_pro/uicons_pro.dart';
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

    final library = await DBLibrary.getAll();

    if (Overlayment.count > 0) { await Overlayment.dismissLast(); return; }

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverSlideAnimation(beginAlignment: Alignment.centerRight, reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        child: VStack([
          HStack(
            [
              Icon(UIconsPro.regularRounded.multiple_alt, size: 18).pOnly(right: 12, left: 8),
              'Library'.tr.text.bold.make(),
              Spacer(),
              AppIconButton(
                icon: Icon(UIconsPro.regularRounded.refresh, size: 13),
                tooltip: 'Rescan All Folders'.tr,
                onPressed: () {
                  Overlayment.dismissLast();
                  doRescanAllVideoFromLibrary(library, recoverVideoCodes: true);
                },
              ),
              AppIconButton(
                icon: Icon(UIconsPro.regularRounded.edit, size: 13),
                tooltip: 'Repair Metadata from R18'.tr,
                onPressed: () async {
                  await Overlayment.dismissLast();
                  await _repairAllMetadata(library);
                },
              ),
              AppIconButton(
                icon: Icon(UIconsPro.regularRounded.plus, size: 13),
                tooltip: 'Add New Library'.tr,
                onPressed: () {
                  Overlayment.dismissLast();
                  showDialogAddorEditLibrary();
                },
              ),
            ],
          ),
          Divider(),
          library.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.mug_hot_alt),
                  title: 'No Data'.tr,
                  message: 'No Library Found, Please Add New Library by Click Button `+`'.tr,
                ).expand()
              : ListView.separated(
                  itemCount: library.length,
                  separatorBuilder: (context, index) => Divider(),
                  itemBuilder: (context, index) {
                    final item = library[index];
                    return HStack([
                      HStack([
                        AppIconButton(
                          onPressed: () => HelperOpener.openFolder(item.rootFolder ?? ''),
                          icon: Icon(UIconsPro.regularRounded.folder, size: 14),
                          tooltip: 'Open Folder `@{alias}`'.trNamed({'alias': '${item.alias}'}),
                        ).pOnly(right: 8),
                        VStack([
                          '${item.alias}'.text.ellipsis.make().pOnly(right: 8),
                          '${item.rootFolder!.getLastSegments()}'.text.size(10).minFontSize(10).neutral500.ellipsis.make(),
                        ]).expand(),
                      ]).expand(),

                      Container(
                        decoration: ExDecorator.box(borderRadius: 90, fillColor: AppColor.selected, borderColor: AppColor.selected),
                        child: ' ${item.totalVideo} '.text.size(11).minFontSize(11).make(),
                      ),
                      AppIconButton(
                        icon: Icon(UIconsPro.regularRounded.refresh, size: 12),
                        tooltip: 'Rescan Folder `@{alias}`'.trNamed({'alias': '${item.alias}'}),
                        onPressed: () async => {
                          await Overlayment.dismissLast(),
                          _doRescanVideoFromLibrary(item, fromAutoWatcher: false),
                        },
                      ),
                    ]).onInkTap(() async {
                      await Overlayment.dismissLast();
                      await showDialogAddorEditLibrary(library: item);
                    });
                  },
                ).expand(),

          Container(
            width: double.infinity,
            decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4, fillColor: AppColor.container),
            child: HStack([
              'Total Folder: @{getCount}'.trNamed({'getCount': '${await DBLibrary.getCount()}'}).text.size(12).make(),
              Spacer(),
              'Total Video: @{getCount}'.trNamed({'getCount': '${await DBVideos.getCount()}'}).text.size(12).make(),
            ]).p12(),
          ).pSymmetric(v: 12),

        ]).p8(),
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
          AppIconButton(tooltip: 'Close'.tr, icon: const Icon(Icons.close), onPressed: Get.back),
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
              prefix: Icon(UIconsPro.regularRounded.folder, size: 13).pOnly(left: 8),
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
              prefix: Icon(UIconsPro.regularRounded.tags, size: 14).pOnly(left: 8),
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
        await DBLibrary.add(library);
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
    await DBLibrary.add(librarySelected);
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

    if (library.videos == null || library.videos!.isEmpty) return;

    if (showLoading) {
      _controller.footerText.value = '◎ Scanning and processing videos...'.tr;
      _controller.change(200, status: RxStatus.loading());
    }

    final videos = library.videos!;
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

    if (videosToAdd.isNotEmpty) {
      _controller.footerText.value = '◎ Committing @{length} Videos'.trNamed({'length': '${videosToAdd.length}'});
      await DBVideos.addBulk(videosToAdd);
    } else {
      _controller.footerText.value = '◎ No new videos to add.'.tr;
    }

    sw.stop();
    AppLog.logD('Time taken: ${sw.elapsedMilliseconds}ms');
    if (showFinishToast) {
      await HelperToast.success('Finish • @{elapsedMilliseconds}ms | @{length} Videos Added'.trNamed({'elapsedMilliseconds': '${sw.elapsedMilliseconds}', 'length': '${videosToAdd.length}'}));
    }

    if (refreshAfter) {
      await _controller.onRefreshAllContent();
    }
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
    await DBVideos.deleteByRootPath(library.rootFolder ?? '');
    await DBLibrary.delete(library);
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
      final oldVideos = Set<String>.from(oldData.videos ?? const <String>[]);
      final newVideos = Set<String>.from(newData.videos ?? const <String>[]);

      pathToAdd.addAll(newVideos.difference(oldVideos));
      pathToDelete.addAll(oldVideos.difference(newVideos));

      // Update library
      oldData.totalVideo = newData.totalVideo;
      oldData.videos = newData.videos;
      await DBLibrary.update(oldData);

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

      if (moves.isNotEmpty) {
        final moved = await DBVideos.moveVideoPaths(moves);
        AppLog.logD('[RescanSingle] ${library.alias} | moved=$moved');
      }

      if (remainingAdds.isNotEmpty) {
        final libraryWithNewVideos = Library(videos: remainingAdds, rootFolder: oldData.rootFolder);
        await _doAddorEditVideoFromLibrary(
          libraryWithNewVideos,
          refreshAfter: false,
          showFinishToast: false,
          showLoading: false,
        );
        await HelperToast.info('@{alias} | Added @{length} videos'.trNamed({'alias': '${library.alias}', 'length': '${remainingAdds.length}'}));
      }

      if (remainingDeletes.isNotEmpty) {
        await DBVideos.deleteByVideoPaths(remainingDeletes);
        await HelperToast.warn('@{alias} | Deleted @{length} videos'.trNamed({'alias': '${library.alias}', 'length': '${remainingDeletes.length}'}));
      }

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

      // 1) Build oldMap from current library objects (assumed DB state)
      final Map<String, List<String>> oldMap = {};
      for (final lib in libraries) {
        oldMap[lib.rootFolder ?? ''] = List<String>.from(lib.videos ?? []);
      }

      // 2) Scan all roots and build newMap
      final Map<String, List<String>> newMap = {};
      final Map<String, int> newTotal = {};

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

      // 5) Apply moves: batch update DB paths.
      final movedUpdatedRows = await DBVideos.moveVideoPaths(moves);

      // 6) For remaining adds, group by root and call doAddorEditVideoFromLibrary per root
      final Map<String, List<String>> addsByRoot = {};
      for (final a in remainingAdds) {
        final root = a['root']!;
        addsByRoot.putIfAbsent(root, () => []).add(a['path']!);
      }
      for (final entry in addsByRoot.entries) {
        final root = entry.key;
        final list = entry.value;
        final libToAdd = Library(videos: list, rootFolder: root);
        await _doAddorEditVideoFromLibrary(
          libToAdd,
          refreshAfter: false,
          showFinishToast: false,
          showLoading: false,
        );
      }

      // 7) Apply remaining deletes (those not used in moves)
      // delCandidates list still contains leftovers; delete them
      final delPaths = List<String>.from(
        List<Map<String, String>>.from(delCandidates).map((d) => d['path'] ?? '').where((p) => p.isNotEmpty),
      );
      await DBVideos.deleteByVideoPaths(delPaths);

      var recovered = 0;
      // 8) Update each library metadata in DB to reflect scanned state
      for (final lib in scannedLibraries) {
        final root = lib.rootFolder ?? '';
        lib.totalVideo = newTotal[root] ?? lib.totalVideo;
        lib.videos = newMap[root] ?? [];
        await DBLibrary.update(lib);
        if (recoverVideoCodes) recovered += await DBVideos.recoverMissingVideoCodes(root);
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
