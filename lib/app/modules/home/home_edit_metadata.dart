import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_color.dart';
import '../../data/database/db_r18.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper.dart';
import '../widgets/widgets.dart';
import 'home_controller.dart';

mixin HomeEditVideoDetail {
  // ~
  static Future<void> onEditMetadata(Videos video) async {
    final tecTitle = TextEditingController(text: video.title ?? '');
    final tecFanArt = TextEditingController(text: video.fanArt ?? '');
    final tecReleaseDate = TextEditingController(text: video.releaseDate ?? '');
    final tecDuration = TextEditingController(text: video.duration.toString());
    final tecStudio = TextEditingController(text: video.studio ?? '');
    final tecLabel = TextEditingController(text: video.label ?? '');
    final tecDirector = TextEditingController(text: video.director ?? '');
    final tecSeries = TextEditingController(text: video.series ?? '');

    final actresses = video.actress ?? [];
    final categories = video.category ?? [];

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: 500,
        height: Get.height * 80 / 100,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.bottomCenter,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        child: Stack(
          children: [
            VStack(
              [
                'Edit Metadata ${video.videoCode.isNotEmptyAndNotNull ? '(${video.videoCode})' : ''}'.text.bold.white.make().pOnly(bottom: 16),
                HStack([
                  'Title'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecTitle,
                    placeholder: 'Title',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]),
                Divider().pSymmetric(v: 4),
                HStack([
                  'Cover URL'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecFanArt,
                    placeholder: 'Cover URL',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]),
                Divider().pSymmetric(v: 4),

                // ** actress
                HStack([
                  'Actress'.text.make(),
                  Spacer(),
                  IconButton(
                    icon: Icon(CupertinoIcons.add, size: 16),
                    onPressed: () => _openDialogAddActress(actresses),
                  ),
                ]),
                GetBuilder(
                  init: Get.find<HomeController>(),
                  builder: (controller) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...actresses.map(
                          (actress) => ZStack([
                            ExThumbnail(
                              imageUrl: '${actress.imageUrl?.genAvatarUrl()}',
                              width: 48,
                              height: 48,
                              fitUrl: BoxFit.cover,
                              withProxy: false,
                              iconSize: 24,
                            ).cornerRadius(90).tooltip(actress.nameRomaji ?? actress.nameKana!).pOnly(right: 8),

                            Icon(UIconsPro.regularRounded.cross, size: 8).pOnly(right: 8).onInkTap(() {
                              actresses.remove(actress);
                              controller.update();
                            }).positioned(right: 0),
                          ]).p8(),
                        )
                      ],
                    );
                  },
                ),
                Divider().pSymmetric(v: 4),

                // ** category
                HStack([
                  'Category'.text.make(),
                  Spacer(),
                  IconButton(
                    icon: Icon(CupertinoIcons.add, size: 16),
                    onPressed: () async => await _openDialogAddCategory(categories),
                  ),
                ]),
                GetBuilder(
                  init: Get.find<HomeController>(),
                  builder: (controller) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...categories.map(
                          (cat) => Container(
                            decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 90),
                            child: HStack([
                              '${cat.id ?? ''} ${cat.category ?? ''}'.text.minFontSize(11).size(11).make().pOnly(right: 12),
                              Icon(UIconsPro.regularRounded.cross, size: 8).pOnly(right: 8).onInkTap(() {
                                categories.remove(cat);
                                controller.update();
                              }),
                            ]).p8(),
                          ),
                        )
                      ],
                    );
                  },
                ),

                Divider().pSymmetric(v: 4),

                HStack([
                  'Release Date'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecReleaseDate,
                    placeholder: 'Release Date',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                  '${video.releaseDateFormated ?? ''}'.text.size(11).minFontSize(11).neutral500.make().pOnly(left: 8),
                ]).pSymmetric(v: 8),
                HStack([
                  'Duration'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecDuration,
                    placeholder: 'Duration',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                  '${video.durationFormated ?? ''}'.text.size(11).minFontSize(11).neutral500.make().pOnly(left: 8),
                ]).pSymmetric(v: 8),
                HStack([
                  'Studio'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecStudio,
                    placeholder: 'Studio',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]).pSymmetric(v: 8),
                HStack([
                  'Label'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecLabel,
                    placeholder: 'Label',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]).pSymmetric(v: 8),
                HStack([
                  'Director'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecDirector,
                    placeholder: 'Director',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]).pSymmetric(v: 8),
                HStack([
                  'Series'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecSeries,
                    placeholder: 'Series',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]).pSymmetric(v: 8),
                32.heightBox,
              ],
            ).p16().scrollVertical(),
            Container(
              width: double.infinity,
              color: AppColor.container,
              child: ExButtonElevated(
                label: 'Submit',
                backgroundColor: AppColor.selected,
                labelColor: Colors.white,
                onPressed: () {
                  final edited = video;
                  edited.title = tecTitle.text;
                  edited.fanArt = tecFanArt.text;
                  edited.releaseDate = tecReleaseDate.text;
                  edited.duration = tecDuration.text.toNum();
                  edited.studio = tecStudio.text;
                  edited.label = tecLabel.text;
                  edited.director = tecDirector.text;
                  edited.series = tecSeries.text;
                  edited.category = categories;
                  edited.actress = actresses;
                  _submit(edited);
                },
              ).p12().pSymmetric(h: 32),
            ).positioned(bottom: 0, left: 0, right: 0),
          ],
        ),
      ),
    );
  }

  static Future<void> _submit(Videos video) async {
    await DBVideos.update(video);
    await Overlayment.dismissLast();
    // ExAlert.adaptive(
    //   title: Text('Are you sure?', style: TextStyle(fontSize: 14)),
    //   content: Text('Are you sure you want to update this video?', style: TextStyle(fontSize: 12)).pOnly(top: 8),
    //   actions: [
    //     CupertinoDialogAction(
    //       onPressed: () async {
    //         await DBVideos.update(video);
    //         await Overlayment.dismissLast();
    //       },
    //       child: Text('Yes', style: TextStyle(color: Vx.red500, fontSize: 13)),
    //     ),
    //     CupertinoDialogAction(
    //       child: Text('No', style: TextStyle(fontSize: 13)),
    //       onPressed: () {
    //         Get.back();
    //       },
    //     ),
    //   ],
    // );
  }

  static Future<void> _openDialogAddCategory(List<VideoCategory> currentCategories) async {
    final tecCategory = TextEditingController();

    final categories = await DBR18.getAllCategories();
    final categoriesIds = <String>[].obs;
    final categoriesNames = <String>[].obs;

    for (var cat in categories) {
      categoriesIds.add('${cat['id']}');
      categoriesNames.add('${cat['name_en']}');
    }

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: 300,
        color: AppColor.container,
        height: 144,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.bottomCenter,
          reverseDurationMilliseconds: 10,
          durationMilliseconds: 10,
        ),
        child: VStack(
          [
            'Add Category'.text.bold.make().pOnly(bottom: 16),
            ExAutoComplate(
              controller: tecCategory,
              items: categoriesNames,
              placeHolder: 'Type something...',
              onSelected: (cat) => tecCategory.text = cat,
            ).pOnly(bottom: 12),
            ExButtonElevated(
              width: double.infinity,
              label: 'Submit',
              onPressed: () async {
                if (tecCategory.text.isEmpty) return;

                final id = categoriesIds[categoriesNames.indexOf(tecCategory.text)];
                final name = tecCategory.text;
                final newCat = VideoCategory(id: id.toNum(), category: name);
                currentCategories.add(newCat);
                Get.find<HomeController>().update();
                await Overlayment.dismissLast();
              },
            ),
          ],
        ).p12(),
      ),
    );
  }

  static Future<void> _openDialogAddActress(List<VideoActress> currentActresses) async {
    final tecActress = TextEditingController();

    final actresses = await DBR18.getAllActress();
    final actressesIds = <String>[].obs;
    final actressesNameRomaji = <String>[].obs;
    final actressesNameKana = <String>[].obs;
    final actressesNameKanji = <String>[].obs;
    final actressesImageUrl = <String>[].obs;

    for (var actress in actresses) {
      actressesIds.add('${actress['id']}');
      actressesNameRomaji.add('${actress['name_romaji']}');
      actressesNameKana.add('${actress['name_kana']}');
      actressesNameKanji.add('${actress['name_kanji']}');
      actressesImageUrl.add('${actress['image_url']}');
    }

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: 300,
        color: AppColor.container,
        height: 144,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.bottomCenter,
          reverseDurationMilliseconds: 10,
          durationMilliseconds: 10,
        ),
        child: VStack(
          [
            'Add Actress'.text.bold.make().pOnly(bottom: 16),
            ExAutoComplate(
              controller: tecActress,
              items: actressesNameRomaji,
              placeHolder: 'Type something...',
              onSelected: (actress) => tecActress.text = actress,
            ).pOnly(bottom: 12),
            ExButtonElevated(
              width: double.infinity,
              label: 'Submit',
              onPressed: () async {
                if (tecActress.text.isEmpty) return;

                final id = actressesIds[actressesNameRomaji.indexOf(tecActress.text)];
                final nameRomaji = tecActress.text;
                final nameKana = actressesNameKana[actressesNameRomaji.indexOf(tecActress.text)];
                final nameKanji = actressesNameKanji[actressesNameRomaji.indexOf(tecActress.text)];
                final imageUrl = actressesImageUrl[actressesNameRomaji.indexOf(tecActress.text)];
                final newActress = VideoActress(id: id.toNum(), nameRomaji: nameRomaji, nameKanji: nameKanji, nameKana: nameKana, imageUrl: imageUrl);

                currentActresses.add(newActress);
                Get.find<HomeController>().update();
                await Overlayment.dismissLast();
              },
            ),
          ],
        ).p12(),
      ),
    );
  }
}
