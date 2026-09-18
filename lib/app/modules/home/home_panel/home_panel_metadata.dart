import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';

mixin HomePanelMetadata {
  // ~
  static Future<void> open(Videos video) async {
    // helpers for consistent micro UI styling
    Widget sectionLabel(String title) => HStack([
          title.text.semiBold.size(12).white.make(),
          Expanded(child: Divider(color: AppColor.border.withValues(alpha: .6)).pOnly(left: 12)),
        ]).pOnly(bottom: 8, top: 16);

    Widget inputField({required String label, required TextEditingController controller, String? placeholder, Widget? suffix}) {
      return VStack([
        label.text.size(11).color(Vx.neutral400).make(),
        6.heightBox,
        DecoratedBox(
          decoration: ExDecorator.box(borderRadius: 8, borderColor: AppColor.border, fillColor: AppColor.container.withValues(alpha: .65)),
          child: HStack([
            CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              style: TextStyle(fontSize: 13, color: Vx.white),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            ).expand(),
            if (suffix != null) suffix.pOnly(right: 10),
          ]),
        ),
      ]).pOnly(bottom: 12);
    }

    final tecVideoCode = TextEditingController(text: video.videoCode ?? '');
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

    Widget _actionButton({required String label, required Color color, required VoidCallback onTap, bool isLeft = false}) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(isLeft ? 10 : 0),
            bottomRight: Radius.circular(isLeft ? 0 : 10),
          ),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColor.container.withValues(alpha: .85),
              border: Border(
                right: isLeft ? BorderSide(color: AppColor.border, width: .4) : BorderSide.none,
              ),
            ),
            child: Center(
              child: label.text.semiBold.size(13).color(color).make(),
            ),
          ),
        ),
      );
    }

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: 500,
        height: Get.height * 80 / 100,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black.withAlpha(240),
        child: Stack(
          children: [
            VStack(
              [
                HStack([
                  Icon(UIconsPro.regularRounded.pen_square, size: 16).pOnly(right: 8),
                  'Edit Metadata ${video.videoCode.isNotEmptyAndNotNull ? '(${video.videoCode})' : ''}'.text.bold.white.make(),
                ]).pOnly(bottom: 12),

                // basic info
                sectionLabel('Basic Info'),
                inputField(label: 'Video Code', controller: tecVideoCode, placeholder: 'Leave empty for NON-JAV'),
                inputField(label: 'Title', controller: tecTitle, placeholder: 'Title'),
                inputField(label: 'Cover URL', controller: tecFanArt, placeholder: 'Paste image URL here...'),

                // cast & tags
                sectionLabel('Cast & Tags'),
                HStack([
                  'Actress'.text.color(Vx.neutral400).size(11).make(),
                  Spacer(),
                  IconButton(
                    icon: Icon(CupertinoIcons.add, size: 16),
                    tooltip: 'Add actress',
                    onPressed: () => _showDialogAddActress(actresses),
                  ),
                ]),
                GetBuilder(
                  init: Get.find<HomeController>(),
                  builder: (controller) {
                    return DecoratedBox(
                      decoration: ExDecorator.box(borderRadius: 10, borderColor: AppColor.border, fillColor: AppColor.container.withValues(alpha: .4)),
                      child: actresses.isEmpty
                          ? 'No actress added'.text.color(Vx.neutral500).size(11).makeCentered().p16()
                          : Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ...actresses.map(
                                  (actress) => ZStack([
                                    ExThumbnail(
                                      imageUrl: '${actress.imageUrl?.genAvatarUrl()}',
                                      width: 56,
                                      height: 56,
                                      fitUrl: BoxFit.cover,
                                      withProxy: false,
                                      iconSize: 24,
                                    ).cornerRadius(10).tooltip(actress.nameRomaji ?? actress.nameKana!).pOnly(right: 8),

                                    Icon(UIconsPro.regularRounded.cross, size: 10)
                                        .pOnly(right: 6, top: 6)
                                        .onInkTap(() {
                                      actresses.remove(actress);
                                      controller.update();
                                    }).positioned(right: 0, top: 0),
                                  ]).p4(),
                                )
                              ],
                            ).w(double.infinity).p12(),
                    );
                  },
                ),

                8.heightBox,
                HStack([
                  'Category'.text.color(Vx.neutral400).size(11).make(),
                  Spacer(),
                  IconButton(
                    icon: Icon(CupertinoIcons.add, size: 16),
                    tooltip: 'Add category',
                    onPressed: () async => await _showDialogAddCategory(categories),
                  ),
                ]),
                GetBuilder(
                  init: Get.find<HomeController>(),
                  builder: (controller) {
                    return DecoratedBox(
                      decoration: ExDecorator.box(borderRadius: 10, borderColor: AppColor.border, fillColor: AppColor.container.withValues(alpha: .4)),
                      child: categories.isEmpty
                          ? 'No category added'.text.color(Vx.neutral500).size(11).makeCentered().p16()
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ...categories.map(
                                  (cat) => HStack([
                                    '${cat.id ?? ''}'.text.size(10).color(Vx.neutral500).make().pOnly(right: 4),
                                    '${cat.category ?? ''}'.text.size(11).semiBold.white.make(),
                                    Icon(UIconsPro.regularRounded.cross, size: 10)
                                        .pOnly(left: 6)
                                        .onInkTap(() {
                                      categories.remove(cat);
                                      controller.update();
                                    }),
                                  ])
                                      .pSymmetric(h: 10, v: 8)
                                      .box
                                      .border(color: AppColor.border)
                                      .color(AppColor.container.withValues(alpha: .7))
                                      .withRounded(value: 30)
                                      .make(),
                                )
                              ],
                            ).w(double.infinity).p12(),
                    );
                  },
                ),

                // production metadata
                sectionLabel('Metadata'),
                inputField(
                  label: 'Release Date',
                  controller: tecReleaseDate,
                  placeholder: 'YYYY-MM-DD',
                  suffix: '${video.releaseDateFormated ?? ''}'.text.size(11).minFontSize(11).neutral500.make(),
                ),
                inputField(
                  label: 'Duration (minutes)',
                  controller: tecDuration,
                  placeholder: 'e.g. 120',
                  suffix: '${video.durationFormated ?? ''}'.text.size(11).minFontSize(11).neutral500.make(),
                ),
                inputField(label: 'Studio', controller: tecStudio, placeholder: 'Studio name'),
                inputField(label: 'Label', controller: tecLabel, placeholder: 'Label name'),
                inputField(label: 'Director', controller: tecDirector, placeholder: 'Director'),
                inputField(label: 'Series', controller: tecSeries, placeholder: 'Series'),

                60.heightBox,
              ],
            ).p16().scrollVertical(),
            ClipRRect(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColor.container,
                  border: Border(top: BorderSide(color: AppColor.border, width: .4)),
                ),
                child: HStack(
                  [
                    _actionButton(
                      label: 'Delete',
                      color: Vx.red400,
                      isLeft: true,
                      onTap: () {
                        _remove(video);
                      },
                    ),
                    _actionButton(
                      label: 'Submit',
                      color: Get.context!.accentColor,
                      onTap: () {
                        final videoCode = tecVideoCode.text.trim().toUpperCase();
                        if (videoCode.isNotEmpty && !videoCode.isValidVideoCode()) {
                          HelperToast.warn('Video code not valid');
                          return;
                        }
                        final edited = video;
                        edited.videoCode = videoCode.getVideoCode();
                        edited.title = tecTitle.text;
                        edited.fanArt = tecFanArt.text.trim();
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
                    ),
                  ],
                ),
              ),
            ).positioned(bottom: 0, left: 0, right: 0),
          ],
        ),
      ),
    );
  }

  static Future<void> _submit(Videos video) async {
    await DBVideos.update(video);
    await Overlayment.dismissLast();
    await Get.forceAppUpdate();
  }

  static Future<void> _remove(Videos video) async {
    await DBVideos.delete(video);
    await Overlayment.dismissLast();
  }

  static Future<void> _showDialogAddCategory(List<VideoCategory> currentCategories) async {
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
        height: 144,
        backgroundSettings: BackgroundSettings(blur: 5, color: Colors.orange.withAlpha(50)),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black.withAlpha(230),
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

  static Future<void> _showDialogAddActress(List<VideoActress> currentActresses) async {
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
        height: 144,
        backgroundSettings: BackgroundSettings(blur: 5, color: Colors.orange.withAlpha(50)),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: Colors.black.withAlpha(230),
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
