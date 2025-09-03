import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
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

mixin HomeLibrary {
  static final _homeController = Get.find<HomeController>();

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
                tooltip: 'Rescan All Video',
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
                      VStack([
                        HStack([
                          '${item.alias}'.text.ellipsis.make().pOnly(right: 8),
                          Container(
                            decoration: ExDecorator.box(borderRadius: 90, fillColor: AppColor.container),
                            child: ' ${item.totalVideo} '.text.size(9).minFontSize(9).make(),
                          ),
                        ]),
                        '${HelperMisc.getLastSegments(item.rootFolder!)}'.text.size(10).minFontSize(10).neutral500.make(),
                      ]).expand(),
                      IconButton(
                        onPressed: () async => {
                          await Overlayment.dismissLast(),
                          doRescanVideoFromLibrary(item),
                        },
                        icon: Icon(UIconsPro.regularRounded.back_up, size: 14),
                        tooltip: 'Rescan Folder `${item.alias}`',
                      ),
                      IconButton(
                        onPressed: () => HelperOpener.openFolder(item.rootFolder ?? ''),
                        icon: Icon(UIconsPro.regularRounded.folder_camera, size: 14),
                        tooltip: 'Open Folder `${item.alias}`',
                      ),
                    ]).onInkTap(() async {
                      await Overlayment.dismissLast();
                      await openDialogAddorEditLibrary(library: item);
                    });
                  },
                ).expand(),
          Divider().pSymmetric(v: 4),
          HStack([
            Spacer(),
            VStack([
              'Total Folder: ${await DBLibrary.getCount()}'.text.size(12).make(),
              'Total Video: ${await DBVideos.getCount()}'.text.size(12).make(),
            ]),
          ]).pOnly(bottom: 8),
        ]).p8(),
      ),
    );
  }

  static Future<void> openDialogAddorEditLibrary({Library? library, bool isFromDrop = false}) async {
    final tfAlias = TextEditingController(text: library?.alias);
    final tfRootPath = TextEditingController(text: library?.rootFolder);
    final librarySelected = Library().obs;
    final isClicked = false.obs;
    final totalVideo = 0.obs;

    ExAlert.adaptive(
      isDismissible: false,
      icon: 'aa'.text.make(),
      title: HStack(
        [
          Text(
            library != null ? 'ⵌ ${library.alias}' : 'ⵌ Add to Library',
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.left,
          ),
          Spacer(),
          ExCloseButton(),
        ],
      ).pOnly(bottom: 16),
      content: VStack(
        [
          CupertinoTextField(
            readOnly: true,
            controller: tfRootPath,
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
              }
            },
          ).pOnly(bottom: 16),
          CupertinoTextField(
            controller: tfAlias,
            placeholder: 'Alias',
            placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
            prefix: Icon(UIconsPro.regularRounded.tags, size: 14).pOnly(left: 8),
            style: TextStyle(fontSize: 13, color: Vx.white),
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

        //
        CupertinoDialogAction(
          child: Text('Submit', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            // edit mode
            if (library != null) {
              library.alias = tfAlias.text;
              library.rootFolder = tfRootPath.text;

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

            // add mode
            librarySelected.value.alias = tfAlias.text;
            await DBLibrary.add(librarySelected.value);
            Get.back();
            await doAddorEditVideoFromLibrary(librarySelected.value);
          },
        ),
      ],
    );
  }

  // ** MAIN PROCESS
  static Future<void> doAddorEditVideoFromLibrary(Library library) async {
    if (library.videos == null || library.videos!.isEmpty) {
      return;
    }

    for (int index = 0; index < library.videos!.length; index++) {
      final video = library.videos![index];
      _homeController.footerText.value = '◎ ${index + 1} of ${library.videos!.length}';

      _homeController.change(200, status: RxStatus.loading());
      _homeController.loadingText.value = 'Progress: ${index + 1} of ${library.videos!.length} (${((index + 1) * 100 / library.videos!.length).toInt()}%)';

      final videoCode = HelperMisc.getVideoCode(HelperMisc.getLastPath(video));

      if (videoCode != '') {
        final dataVideo = await DBR18.getVideo(videoCode);
        final dataCategory = await DBR18.getCategory(videoCode);
        final dataActress = await DBR18.getActress(videoCode);
        final dataDirector = await DBR18.getDirector(videoCode);

        if (dataVideo == null) {
          final newVideo = Videos();
          newVideo.rootPath = library.rootFolder ?? '';
          newVideo.videoPath = video;
          newVideo.title = video.getFileName().noExt();
          await DBVideos.add(newVideo);
          continue;
        }

        final newVideo = Videos.fromJson(dataVideo);
        newVideo.rootPath = library.rootFolder ?? '';
        newVideo.videoPath = video;
        newVideo.category = dataCategory.map((e) => VideoCategory.fromJson(e)).toList();
        newVideo.actress = dataActress.map((e) => VideoActress.fromJson(e)).toList();
        newVideo.durationFormated = HelperMisc.durationFormatDB(newVideo.duration ?? 0);
        newVideo.releaseDateFormated = newVideo.releaseDate?.reformatDate(from: kYMd, to: kMdY);
        newVideo.director = dataDirector?['name_romaji'] ?? '';
        newVideo.fanArt = '${dataVideo['fan_art']}';
        newVideo.poster = '${dataVideo['poster']}';

        if (dataVideo['sslast'] != null) {
          final ss = <String>[];
          final n = dataVideo['sslast'].toString().split('-').last;
          for (var i = 0; i < int.parse(n); i++) {
            final filename = '${dataVideo['ssfirst']}';

            if (!filename.contains('jp-')) {
              final part = filename.allBefore('-');
              final prefix = '${part}jp-${i + 1}';
              ss.add(prefix);
            } else {
              final part = filename.removeLast(1);
              final prefix = '$part${i + 1}';
              ss.add(prefix);
            }
          }
          newVideo.screenshot = ss;

          await DBVideos.add(newVideo);
          _homeController.footerText.value = '◎ Inserting: $videoCode';
        }
      }

      // else
      else {
        final newVideo = Videos();
        newVideo.rootPath = library.rootFolder ?? '';
        newVideo.videoPath = video;
        newVideo.title = video.getFileName().noExt();
        await DBVideos.add(newVideo);
        _homeController.footerText.value = '◎ Inserting non metadata: $videoCode';
      }
    }

    _homeController.footerText.value = '◎ Commit ${library.videos!.length} Videos';
    await 100.milliseconds.delay();
    await _homeController.onRefreshAllContent();
  }

  static Future<void> doDeleteVideoFromLibrary(Library library) async {
    await DBVideos.deleteByRootPath(library.rootFolder ?? '');
    await DBLibrary.delete(library);
    await _homeController.onRefreshAllContent();
  }

  static Future<void> doRescanVideoFromLibrary(Library library) async {
    try {
      final oldData = library;
      final newData = await HelperFilePicker.scanFolderAndSubFolder(library.rootFolder ?? '');

      final pathToAdd = <String>[];
      final pathToDelete = <String>[];

      for (final newVideo in newData!.videos ?? []) {
        if (oldData.videos == null || !oldData.videos!.contains(newVideo)) {
          pathToAdd.add(newVideo);
        }
      }

      for (final oldVideo in oldData.videos ?? []) {
        if (newData.videos == null || !newData.videos!.contains(oldVideo)) {
          pathToDelete.add(oldVideo);
        }
      }

      // update library
      oldData.totalVideo = newData.totalVideo;
      oldData.videos = newData.videos;
      await DBLibrary.update(oldData);

      if (pathToAdd.isNotEmpty) {
        await doAddorEditVideoFromLibrary(oldData);
        await HelperToast.info('${library.alias} | Added ${pathToAdd.length} videos');
      }

      if (pathToDelete.isNotEmpty) {
        for (var i = 0; i < pathToDelete.length; i++) {
          await DBVideos.deleteByVideoPath(pathToDelete[i]);
        }
        await HelperToast.info('${library.alias} | Deleted ${pathToDelete.length} videos');
        await Get.find<HomeController>().onRefreshAllContent();
      }
    } catch (e) {
      // await HelperToast.error(e.toString());
    }
  }

  static Future<void> doRescanAllVideoFromLibrary(List<Library> libraries) async {
    if (libraries.isEmpty) return;
    _homeController.footerText.value = '◎ Rescanning...';
    for (final library in libraries) {
      await doRescanVideoFromLibrary(library);
    }
    _homeController.footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
  }
}
