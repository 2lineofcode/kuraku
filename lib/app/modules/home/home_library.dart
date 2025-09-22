import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

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
      content: VStack(
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
    if (library.videos == null || library.videos!.isEmpty) {
      return;
    }

    for (int index = 0; index < library.videos!.length; index++) {
      final videoPath = library.videos![index];
      _home.footerText.value = '◎ ${index + 1} of ${library.videos!.length}';

      _home.change(200, status: RxStatus.loading());
      _home.loadingText.value = 'Progress: ${index + 1} of ${library.videos!.length} (${((index + 1) * 100 / library.videos!.length).toInt()}%)';

      final videoCode = videoPath.getFileName().getVideoCode();

      if (videoCode != '') {
        final dataVideo = await DBR18.getVideo(videoCode);
        final dataCategory = await DBR18.getCategory(videoCode);
        final dataActress = await DBR18.getActress(videoCode);
        final dataDirector = await DBR18.getDirector(videoCode);

        if (dataVideo == null) {
          final newVideo = Videos();
          newVideo.rootPath = library.rootFolder ?? '';
          newVideo.videoPath = videoPath;
          newVideo.title = videoPath.getFileName().noExt();

          final file = File(videoPath);
          if (file.existsSync()) newVideo.filesize = file.lengthSync();

          await DBVideos.add(newVideo);
          continue;
        }

        final newVideo = Videos.fromJson(dataVideo);
        newVideo.rootPath = library.rootFolder ?? '';
        newVideo.videoPath = videoPath;
        newVideo.category = dataCategory.map((e) => VideoCategory.fromJson(e)).toList();
        newVideo.actress = dataActress.map((e) => VideoActress.fromJson(e)).toList();
        newVideo.durationFormated = HelperMisc.durationFormatDB(newVideo.duration ?? 0);
        newVideo.releaseDateFormated = newVideo.releaseDate?.reformatDate(from: kYMd, to: kMdY);
        newVideo.director = dataDirector?['name_romaji'] ?? '';
        newVideo.fanArt = '${dataVideo['fan_art']}';
        newVideo.poster = '${dataVideo['poster']}';

        // Logic for screenshot
        if (dataVideo['sslast'] != null) {
          final screenshots = <String>[];
          final total = int.parse(dataVideo['sslast'].toString().split('-').last);
          final filename = dataVideo['ssfirst'].toString();
          final base = filename.contains('jp-') ? filename.removeLast(1) : '${filename.allBefore('-')}jp-';

          for (var i = 1; i <= total; i++) {
            screenshots.add('$base$i');
          }
          newVideo.screenshot = screenshots;
        }

        final file = File(videoPath);
        if (file.existsSync()) newVideo.filesize = file.lengthSync();

        await DBVideos.add(newVideo);
        _home.footerText.value = '◎ Inserting: $videoCode';
      }

      // else => no video_code (non-jav)
      else {
        final newVideo = Videos();
        newVideo.rootPath = library.rootFolder ?? '';
        newVideo.videoPath = videoPath;
        newVideo.title = videoPath.getFileName().noExt();

        final file = File(videoPath);
        if (file.existsSync()) newVideo.filesize = file.lengthSync();

        await DBVideos.add(newVideo);
        _home.footerText.value = '◎ Inserting non metadata: $videoCode';
      }
    }

    _home.footerText.value = '◎ Commit ${library.videos!.length} Videos';
    await 10.milliseconds.delay();
    await _home.onRefreshAllContent();
  }

  /// Deletes all videos associated with a specific library.
  static Future<void> doDeleteVideoFromLibrary(Library library) async {
    await DBVideos.deleteByRootPath(library.rootFolder ?? '');
    await DBLibrary.delete(library);
    await _home.onRefreshAllContent();
  }

  /// Rescans a single library to find new or deleted videos.
  /// Updates the library record and performs add/delete operations on videos.
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
        await HelperToast.info('${library.alias} | Deleted ${pathToDelete.length} videos');
        await _home.onRefreshAllContent();
      }
    } catch (e) {
      AppLog.logE(e);
      // await HelperToast.error(e.toString());
    }
  }

  /// Rescans all existing libraries.
  static Future<void> doRescanAllVideoFromLibrary(List<Library> libraries) async {
    if (libraries.isEmpty) return;
    _home.footerText.value = '◎ Rescanning...';
    for (final library in libraries) {
      await doRescanVideoFromLibrary(library);
    }
    _home.footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
  }
}
