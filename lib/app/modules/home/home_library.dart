import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart' as p;
import 'package:uicons_pro/uicons_pro.dart';
import 'package:video_compress/video_compress.dart';

import '../../core/app_color.dart';
import '../../core/app_logging.dart';
import '../../core/const.dart';
import '../../data/database/db_library.dart';
import '../../data/database/db_r18.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/library_entity.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper_file_picker.dart';
import '../../utils/helper_misc.dart';
import '../../utils/helper_opener.dart';
import '../../utils/helper_toast.dart';
import 'home_controller.dart';

/// A mixin for managing library-related functionalities in the home screen.
mixin HomeLibrary {
  static final _home = Get.find<HomeController>();

  /// Displays the library menu as an overlay panel.
  /// This menu shows a list of libraries, allows adding new ones,
  /// and rescanning existing ones.
  static Future<void> openMenuLibrary(List<Library> library) async {
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerRight,
        width: 300,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.centerRight,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        child: VStack([
          HStack(
            [
              Icon(UIconsPro.regularRounded.multiple_alt, size: 18).pOnly(right: 12, left: 8),
              'Library'.text.bold.make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.refresh, size: 13),
                tooltip: 'Rescan All Folders',
                onPressed: () {
                  Overlayment.dismissLast();
                  doRescanAllVideoFromLibrary(library);
                },
              ),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.plus, size: 13),
                tooltip: 'Add New Library',
                onPressed: () {
                  Overlayment.dismissLast();
                  openDialogAddorEditLibrary();
                },
              ),
            ],
          ),
          Divider(),
          library.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(UIconsPro.regularRounded.mug_hot_alt),
                  title: 'No Data',
                  message: 'No Library Found, Please Add New Library by Click Button `+`',
                ).expand()
              : ListView.separated(
                  itemCount: library.length,
                  separatorBuilder: (context, index) => Divider(),
                  itemBuilder: (context, index) {
                    final item = library[index];
                    return HStack([
                      HStack([
                        IconButton(
                          onPressed: () => HelperOpener.openFolder(item.rootFolder ?? ''),
                          icon: Icon(UIconsPro.regularRounded.folder, size: 14),
                          tooltip: 'Open Folder `${item.alias}`',
                        ).pOnly(right: 8),
                        VStack([
                          '${item.alias}'.text.ellipsis.make().pOnly(right: 8),
                          '${item.rootFolder!.getLastSegments()}'.text.size(10).minFontSize(10).neutral500.make(),
                        ]),
                      ]).expand(),

                      Container(
                        decoration: ExDecorator.box(borderRadius: 90, fillColor: AppColor.selected, borderColor: AppColor.selected),
                        child: ' ${item.totalVideo} '.text.size(11).minFontSize(11).make(),
                      ),
                      IconButton(
                        icon: Icon(UIconsPro.regularRounded.refresh, size: 12),
                        tooltip: 'Rescan Folder `${item.alias}`',
                        onPressed: () async => {
                          await Overlayment.dismissLast(),
                          doRescanVideoFromLibrary(item),
                        },
                      ),
                    ]).onInkTap(() async {
                      await Overlayment.dismissLast();
                      await openDialogAddorEditLibrary(library: item);
                    });
                  },
                ).expand(),

          Container(
            width: double.infinity,
            decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
            child: HStack([
              'Total Folder: ${await DBLibrary.getCount()}'.text.size(12).make(),
              Spacer(),
              'Total Video: ${await DBVideos.getCount()}'.text.size(12).make(),
            ]).p12(),
          ).pSymmetric(v: 12),
          
        ]).p8(),
      ),
    );
  }

  /// Opens a dialog to add or edit a library.
  /// This dialog handles input for the library's alias and root path.
  static Future<void> openDialogAddorEditLibrary({Library? library, bool isFromDrop = false}) async {
    final tfAlias = TextEditingController(text: library?.alias);
    final tfRootPath = TextEditingController(text: library?.rootFolder);
    final fnRootPath = FocusNode();
    final fnAlias = FocusNode();
    final librarySelected = Library().obs;
    final isClicked = false.obs;
    final totalVideo = 0.obs;

    if (isFromDrop) fnAlias.requestFocus();

    ExAlert.adaptive(
      isDismissible: false,
      title: HStack(
        [
          Text(
            library != null ? 'ⵌ Edit `${library.alias}`' : 'ⵌ New',
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
          ).expand(),
          ExCloseButton(),
        ],
      ).pOnly(bottom: 16),
      content: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 90),
        child: VStack(
          [
            CupertinoTextField(
              readOnly: true,
              controller: tfRootPath,
              focusNode: fnRootPath,
              placeholder: '<Select Path>',
              placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
              prefix: Icon(UIconsPro.regularRounded.folder, size: 13).pOnly(left: 8),
              style: TextStyle(fontSize: 13, color: Vx.neutral500),
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
            CupertinoTextField(
              controller: tfAlias,
              focusNode: fnAlias,
              placeholder: 'Alias',
              placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
              prefix: Icon(UIconsPro.regularRounded.tags, size: 14).pOnly(left: 8),
              style: TextStyle(fontSize: 13, color: Vx.white),
              onSubmitted: (value) async {
                await onSubmit(
                  alias: tfAlias.text,
                  rootPath: tfRootPath.text,
                  library: library,
                  isFromDrop: isFromDrop,
                  librarySelected: librarySelected.value,
                );
              },
            ).pOnly(bottom: 16),
            Obx(() => totalVideo.value != 0 ? Text('Total Video: ${totalVideo.value}') : 0.heightBox),
          ],
        ),
      ),
      actions: [
        if (library != null && !isFromDrop) ...[
          CupertinoDialogAction(
            child: Text('Delete', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () {
              DBLibrary.delete(library);
              doDeleteVideoFromLibrary(library);
              Get.back();
            },
          ),
        ],

        CupertinoDialogAction(
          child: Text('Submit', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            await onSubmit(
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
  static Future<void> onSubmit({
    required String alias,
    required String rootPath,
    required Library? library,
    required bool isFromDrop,
    required Library librarySelected,
  }) async {
    // Validate fields
    if (alias.isEmpty || rootPath.isEmpty) {
      await HelperToast.error('Please fill all field');
      return;
    }

    // Edit mode
    if (library != null) {
      library.alias = alias;
      library.rootFolder = rootPath;

      if (isFromDrop) {
        Get.back();
        await DBLibrary.add(library);
        await doAddorEditVideoFromLibrary(library);
      } else {
        Get.back();
        await DBLibrary.update(library);
      }
      return;
    }

    // Add mode
    librarySelected.alias = alias;
    await DBLibrary.add(librarySelected);
    Get.back();
    await doAddorEditVideoFromLibrary(librarySelected);
  }


  // ────────────────────────────────────────────────────────────────
  // ** MAIN PROCESSES
  /// Processes and adds/edits videos from a specific library.
  /// Scans for video files and updates the database with metadata if available.
  // ────────────────────────────────────────────────────────────────
  static Future<void> doAddorEditVideoFromLibrary(Library library) async {
    AppLog.logD('Start processing library: ${library.alias}');
    final sw = Stopwatch();
    sw.start();

    if (library.videos == null || library.videos!.isEmpty) return;

    _home.footerText.value = '◎ Scanning and processing videos...';
    _home.change(200, status: RxStatus.loading());

    final videos = library.videos!;
    final totalVideos = videos.length;
    final videosToAdd = <Videos>[];

    final processedCounter = 0.obs;

    // Process videos in parallel
    final List<Future<void>> processingFutures = videos.map((videoPath) async {
      final processedVideo = await _processVideo(videoPath, library.rootFolder);
      if (processedVideo != null) videosToAdd.add(processedVideo);
      
      // Update progress
      processedCounter.value++;
      _home.loadingText.value = 'Progress: ${processedCounter.value} of $totalVideos (${(processedCounter.value * 100 / totalVideos).toInt()}%)';
    }).toList();

    // Wait for all processing to complete
    await Future.wait(processingFutures);

    if (videosToAdd.isNotEmpty) {
      _home.footerText.value = '◎ Committing ${videosToAdd.length} Videos';
      await DBVideos.addBulk(videosToAdd);
    } else {
      _home.footerText.value = '◎ No new videos to add.';
    }

    sw.stop();
    AppLog.logD('Time taken: ${sw.elapsedMilliseconds}ms');
    await HelperToast.success('Finish • ${sw.elapsedMilliseconds}ms | ${videosToAdd.length} Videos Added');


    await _home.onRefreshAllContent();
  }

  // ** PROCESS VIDEO
  static Future<Videos?> _processVideo(String videoPath, String? rootFolder) async {
    final videoCode = videoPath.getFileName().getVideoCode();

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
        final newVideo = Videos();
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
      newVideo.releaseDateFormated = newVideo.releaseDate?.reformatDate(from: kYMd, to: kMdY);
      newVideo.director = dataDirector?['name_romaji'] ?? '';
      newVideo.fanArt = '${dataVideo['fan_art']}';
      newVideo.poster = '${dataVideo['poster']}';

      // logic for screenshot
      if (dataVideo['sslast'] != null) {
        final screenshots = <String>[];
        final total = int.parse(dataVideo['sslast'].toString().split('-').last);
        final filename = dataVideo['ssfirst'].toString();
        final base = filename.contains('jp-') ? filename.removeLast(1) : '${filename.allBefore('-')}jp-';

        for (var i = 1; i <= total; i++) screenshots.add('$base$i');
        newVideo.screenshot = screenshots;
      }

      final file = File(videoPath);
      if (file.existsSync()) newVideo.filesize = file.lengthSync();
      if (!HelperMisc.isExternalDrive(newVideo.videoPath)) await _getVideoResolution(newVideo);

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
  static Future<void> doDeleteVideoFromLibrary(Library library) async {
    await DBVideos.deleteByRootPath(library.rootFolder ?? '');
    await DBLibrary.delete(library);
    await _home.onRefreshAllContent();
  }

  // ────────────────────────────────────────────────────────────────
  // Rescan Single library
  // workflow:
  // - Scan folder (library.rootFolder) selected
  // - compare old data with new data
  // - collect (add, delete, update)
  // - update library
  // ────────────────────────────────────────────────────────────────
  static Future<void> doRescanVideoFromLibrary(Library library) async {
    try {
      final oldData = library;
      final newData = await HelperFilePicker.scanFolderAndSubFolder(library.rootFolder ?? '');

      if (newData == null) return;

      final pathToAdd = <String>[];
      final pathToDelete = <String>[];

      for (final newVideo in newData.videos ?? []) {
        if (oldData.videos == null || !oldData.videos!.contains(newVideo)) {
          pathToAdd.add(newVideo);
        }
      }

      for (final oldVideo in oldData.videos ?? []) {
        if (!newData.videos!.contains(oldVideo)) {
          pathToDelete.add(oldVideo);
        }
      }

      // Update library
      oldData.totalVideo = newData.totalVideo;
      oldData.videos = newData.videos;
      await DBLibrary.update(oldData);

      if (pathToAdd.isNotEmpty) {
        // Need to create a new library object with only the new videos
        final libraryWithNewVideos = Library(videos: pathToAdd, rootFolder: oldData.rootFolder);
        await doAddorEditVideoFromLibrary(libraryWithNewVideos);
        await HelperToast.info('${library.alias} | Added ${pathToAdd.length} videos');
      }

      if (pathToDelete.isNotEmpty) {
        for (var i = 0; i < pathToDelete.length; i++) {
          await DBVideos.deleteByVideoPath(pathToDelete[i]);
        }
        await HelperToast.warn('${library.alias} | Deleted ${pathToDelete.length} videos');
        await _home.onRefreshAllContent();
      }
    } catch (e) {
      AppLog.logE(e);
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Rescan All libraries (detect cross-library moves by basename)
  // ────────────────────────────────────────────────────────────────
  static Future<void> doRescanAllVideoFromLibrary(List<Library> libraries) async {
    try {
      if (libraries.isEmpty) return;

      _home.footerText.value = '◎ Rescanning...';

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

      // 5) Apply moves: update DB path immediately
      for (final m in moves) {
        final updVideo = await DBVideos.getByVideoPath(m['oldPath']!);
        updVideo?.videoPath = m['newPath'];
        updVideo?.rootPath = p.dirname(m['newPath']!);
        await DBVideos.update(updVideo!);
      }

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
        await doAddorEditVideoFromLibrary(libToAdd);
      }

      // 7) Apply remaining deletes (those not used in moves)
      // delCandidates list still contains leftovers; delete them
      for (final d in List<Map<String, String>>.from(delCandidates)) {
        final delPath = d['path']!;
        await DBVideos.deleteByVideoPath(delPath);
      }

      // 8) Update each library metadata in DB to reflect scanned state
      for (final lib in scannedLibraries) {
        final root = lib.rootFolder ?? '';
        lib.totalVideo = newTotal[root] ?? lib.totalVideo;
        lib.videos = newMap[root] ?? [];
        await DBLibrary.update(lib);
      }

      // 9) Summary log
      AppLog.logD('[RescanAll] Finished | Adds=${remainingAdds.length}, Deletes=${delCandidates.length}, Moves=${moves.length}');
      for (final mv in moves) {
        AppLog.logD('[RescanAll] Move ${mv['oldPath']} -> ${mv['newPath']}');
      }

      _home.footerText.value = 'Idle | Total Video: ${await DBVideos.getCount()}';

      if (remainingAdds.isNotEmpty || delCandidates.isNotEmpty || moves.isNotEmpty) {
        await HelperToast.info('Finish • ${remainingAdds.length} added • ${delCandidates.length} deleted • ${moves.length} moved');
        await _home.onRefreshAllContent();
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
        final stream = medInfo.getMediaInformation()?.getStreams().first;
        video.quality = '${stream?.getWidth()}x${stream?.getHeight()}';
      });
    }
  }
}
