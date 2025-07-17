import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uuid/v4.dart';

import '../core/app_color.dart';
import '../data/database/db_library.dart';
import '../data/database/db_r18.dart';
import '../data/database/db_videos.dart';
import '../data/models/library_entity.dart';
import '../data/models/videos_entity.dart';
import '../modules/home/home_controller.dart';
import 'helper_file_picker.dart';
import 'helper_misc.dart';
import 'helper_opener.dart';
import 'helper_toast.dart';

mixin HelperLibrary {
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
              Icon(CupertinoIcons.collections, size: 18).pOnly(right: 12, left: 8),
              'Library'.text.bold.make(),
              Spacer(),
              IconButton(
                icon: Icon(CupertinoIcons.refresh, size: 18),
                onPressed: () {
                  Overlayment.dismissLast();
                  doRescanAllVideoFromLibrary(library);
                },
              ),
              IconButton(
                icon: Icon(CupertinoIcons.add, size: 18),
                onPressed: () {
                  Overlayment.dismissLast();
                  dialogAddorEditLibrary();
                },
              ),
            ],
          ),
          Divider(),
          library.isEmpty
              ? ExUiErrorOrEmpty(
                  illustration: Icon(CupertinoIcons.lab_flask_solid),
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
                          'ⵌ ${item.alias}'.text.ellipsis.make().pOnly(right: 8),
                          Container(
                            decoration: ExDecorator.box(borderRadius: 90, fillColor: AppColor.sideMenuPrimary),
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
                        icon: Icon(CupertinoIcons.refresh, size: 16),
                        tooltip: 'Rescan Folder `${item.alias}`',
                      ),
                      IconButton(
                        onPressed: () => HelperOpener.openFolder(item.rootFolder ?? ''),
                        icon: Icon(CupertinoIcons.folder, size: 16),
                        tooltip: 'Open Folder `${item.alias}`',
                      ),
                    ]).onInkTap(() async {
                      await Overlayment.dismissLast();
                      dialogAddorEditLibrary(library: item);
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

  static void dialogAddorEditLibrary({Library? library, bool isFromDrop = false}) {
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
            prefix: Icon(CupertinoIcons.folder, size: 16, color: AppColor.textReverse).pOnly(left: 8),
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
            prefix: Icon(CupertinoIcons.number_square, size: 16, color: AppColor.textReverse).pOnly(left: 8),
            style: TextStyle(fontSize: 13, color: AppColor.textReverse),
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
      _homeController.footerSum.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
      return;
    }

    for (int index = 0; index < library.videos!.length; index++) {
      final video = library.videos![index];
      _homeController.footerSum.value = '◎ ${index + 1} of ${library.videos!.length}';
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
          newVideo.id = UuidV4().generate();
          newVideo.title = video.getFileName().noExt();
          await DBVideos.add(newVideo);
          continue;
        }

        final newVideo = Videos.fromJson(dataVideo);
        newVideo.rootPath = library.rootFolder ?? '';
        newVideo.videoPath = video;
        newVideo.category = dataCategory.map((e) => VideoCategory.fromJson(e)).toList();
        newVideo.actress = dataActress.map((e) => VideoActress.fromJson(e)).toList();
        newVideo.durationFormated = HelperMisc.durationFormat0(newVideo.duration ?? 0);
        newVideo.releaseDateFormated = newVideo.releaseDate?.reformatDate(from: 'yyyy-MM-dd', to: 'MMM dd, yyyy');
        newVideo.director = dataDirector?['name_romaji'] ?? '';
        newVideo.fanArt = '${dataVideo['fan_art'].toString().removeLast(2)}pl';
        newVideo.poster = '${dataVideo['poster'].toString().removeLast(2)}ps';

        if (dataVideo['sslast'] != null) {
          final ss = <String>[];
          final n = dataVideo['sslast'].toString().split('-').last;
          for (var i = 0; i < int.parse(n); i++) {
            final filename = '${dataVideo['ssfirst']}'.removeLast(2);
            ss.add('${filename}jp-${i + 1}');
          }
          newVideo.screenshot = ss;

          await DBVideos.add(newVideo);
          _homeController.footerSum.value = '◎ Inserting: $videoCode';
        }
      }

      // else
      else {
        final newVideo = Videos();
        newVideo.rootPath = library.rootFolder ?? '';
        newVideo.videoPath = video;
        newVideo.id = UuidV4().generate();
        newVideo.title = video.getFileName().noExt();
        await DBVideos.add(newVideo);
        _homeController.footerSum.value = '◎ Inserting non metadata: $videoCode';
      }
    }

    _homeController.footerSum.value = '◎ Commit ${library.videos!.length} Videos';
    await 300.milliseconds.delay();
    _homeController.footerSum.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
  }

  static Future<void> doDeleteVideoFromLibrary(Library library) async {
    await DBVideos.deleteByRootPath(library.rootFolder ?? '');
    await DBLibrary.delete(library);
    _homeController.footerSum.value = '${await DBVideos.getCount()} Videos';
  }

  static Future<void> doRescanVideoFromLibrary(Library library) async {
    _homeController.footerSum.value = '◎ Rescanning...';
    await DBVideos.deleteByRootPath(library.rootFolder ?? '');
    _homeController.footerSum.value = '◎ Deleting...';

    await HelperFilePicker.scanFolderAndSubFolder(library.rootFolder ?? '').then((newLibrary) async {
      if (newLibrary == null) return;
      newLibrary.id = library.id;
      newLibrary.alias = newLibrary.rootFolder?.getLastPath();
      await DBLibrary.update(newLibrary);
      await doAddorEditVideoFromLibrary(newLibrary);
    }).catchError((e) {
      HelperToast.error('Could not access folder ${library.rootFolder}', duration: 3.seconds);
    });
  }

  static Future<void> doRescanAllVideoFromLibrary(List<Library> libraries) async {
    if (libraries.isEmpty) return;

    _homeController.footerSum.value = '◎ Rescanning...';
    final tempListLibrary = libraries;

    for (int index = 0; index < libraries.length; index++) {
      final library = libraries[index];

      await DBVideos.deleteByRootPath(library.rootFolder ?? '');
      _homeController.footerSum.value = '◎ Deleting...';
    }

    for (int index = 0; index < tempListLibrary.length; index++) {
      final library = tempListLibrary[index];
      await HelperFilePicker.scanFolderAndSubFolder(library.rootFolder ?? '').then((newLibrary) async {
        if (newLibrary != null) {
          newLibrary.alias = newLibrary.rootFolder?.getLastPath();
          newLibrary.id = library.id;
          await DBLibrary.update(newLibrary);
          await doAddorEditVideoFromLibrary(newLibrary);
        }
      }).catchError((e) {
        HelperToast.error('Could not access folder ${library.rootFolder}', duration: 3.seconds);
      });
    }
  }
}
