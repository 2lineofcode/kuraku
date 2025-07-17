import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uuid/v4.dart';

import '../core/app_color.dart';
import '../models/library_entity.dart';
import '../models/videos_entity.dart';
import '../modules/home/home_controller.dart';
import '../repository/local/db_library.dart';
import '../repository/local/db_r18.dart';
import '../repository/local/db_videos.dart';
import 'helper_file_picker.dart';
import 'helper_misc.dart';
import 'helper_opener.dart';

mixin HelperOverlay {
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
                  // processReloadAllVideoDB(library);
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
          ListView.separated(
            itemCount: library.length,
            separatorBuilder: (context, index) => Divider(),
            itemBuilder: (context, index) {
              final item = library[index];
              return HStack([
                VStack([
                  'ⵌ ${item.alias}'.text.ellipsis.make(),
                  '${HelperMisc.getLastSegments(item.rootFolder!)}'.text.size(10).minFontSize(10).neutral500.make(),
                ]).expand(),
                IconButton(
                  onPressed: () => HelperOpener.openFolder(item.rootFolder ?? ''),
                  icon: Icon(CupertinoIcons.folder, size: 18),
                ),
                Container(
                  decoration: ExDecorator.box(borderRadius: 90, fillColor: Vx.red500, borderColor: Vx.red500),
                  child: ' ${item.totalVideo} '.text.size(11).minFontSize(11).make(),
                )
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

  static void dialogAddorEditLibrary({Library? library}) {
    final tfAlias = TextEditingController(text: library?.alias);
    final tfRootPath = TextEditingController(text: library?.rootFolder);
    final librarySelected = Library().obs;
    final isClicked = false.obs;
    final totalVideo = 0.obs;

    ExAlert.adaptive(
      title: Text(
        library != null ? 'ⵌ ${library.alias}' : 'ⵌ Add to Library',
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.left,
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
        if (library != null) ...[
          CupertinoDialogAction(
            child: Text('Delete', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () {
              DBLibrary.delete(library);
              processDeleteVideoDB(library);
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
              await DBLibrary.update(library);
              Get.back();
              return;
            }

            // add mode
            await DBLibrary.add(librarySelected.value);
            Get.back();
            await processAddorEditVideoToDB(librarySelected.value);
          },
        ),
      ],
    );
  }

  // ** MAIN PROCESS
  static Future<void> processAddorEditVideoToDB(Library library) async {
    if (library.videos == null || library.videos!.isEmpty) {
      _homeController.footerSum.value = 'Iddle';
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
        newVideo.durationFormated = HelperMisc.durationFormat(newVideo.duration ?? 0);
        newVideo.releaseDateFormated = newVideo.releaseDate?.reformatDate(from: 'yyyy-MM-dd', to: 'MMM dd, yyyy');
        newVideo.director = dataDirector?['name_romaji'] ?? '';

        if (dataVideo['sslast'] != null) {
          final ss = <String>[];
          final n = dataVideo['sslast'].toString().split('-').last;
          for (var i = 0; i < int.parse(n); i++) {
            final filename = '${dataVideo['ssfirst']}'.removeLast(1);
            ss.add('$filename${i + 1}.jpg');
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
    await 1.seconds.delay();
    _homeController.footerSum.value = 'Iddle';
  }

  static Future<void> processDeleteVideoDB(Library library) async {
    await DBVideos.deleteByRootPath(library.rootFolder ?? '');
    await DBLibrary.delete(library);
    _homeController.footerSum.value = '${await DBVideos.getCount()} Videos';
  }

  // static Future<void> processReloadAllVideoDB(List<Library> libraries) async {
  //   // @step: delete all video
  //   homeController.footerSum.value = '◎ Delete All Video';
  //   await 1.seconds.delay();
  //   await DBVideo.deleteAllVideos();
  //   homeController.footerSum.value = '◎ Re scan all video from library';
  //   await 1.seconds.delay();
  //   // @step: re scan all video from library
  //   for (var i = 0; i < libraries.length; i++) {
  //     final library = libraries[i];
  //     await processAddorEditVideoToDB(library);
  //   }
  //   homeController.footerSum.value = '${await DBVideo.countAllVideo()} Videos';
  // }
}
