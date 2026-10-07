import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_color.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';

mixin HomePanelMetadata {
  static Future<void> open(Videos video) async {
    Widget section(String title, List<Widget> children) => CupertinoFormSection.insetGrouped(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      backgroundColor: Colors.transparent,
      decoration: BoxDecoration(color: AppColor.panel, borderRadius: BorderRadius.circular(10)),
      header: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColor.muted)),
      children: children,
    );

    Widget inputField({required String label, required TextEditingController controller, String? placeholder,
      Widget? suffix, Widget? labelAction, bool multiline = false, TextInputType? keyboardType}) => CupertinoFormRow(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      prefix: SizedBox(width: 112, child: Text(label, style: TextStyle(fontSize: 12, color: AppColor.text))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(label: label, child: AppTextField(
          controller: controller, placeholder: placeholder, keyboardType: keyboardType,
          maxLines: multiline ? 3 : 1, minLines: multiline ? 2 : null,
          decoration: const InputDecoration(border: InputBorder.none),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          suffix: suffix,
        )),
        if (labelAction != null) Align(alignment: Alignment.centerLeft, child: labelAction),
      ]),
    );

    Widget iconButton(String tooltip, IconData icon, VoidCallback onPressed, {double size = AppStyle.iconSize}) => Tooltip(
      message: tooltip,
      child: CupertinoButton(
        padding: EdgeInsets.zero, minimumSize: const Size.square(AppStyle.iconTarget),
        onPressed: onPressed,
        child: Icon(icon, size: size, color: CupertinoColors.activeBlue),
      ),
    );

    final tecVideoCode = TextEditingController(text: video.videoCode ?? '');
    final tecTitle = TextEditingController(text: video.title ?? '');
    final tecFanArt = TextEditingController(text: video.fanArt ?? '');
    final tecReleaseDate = TextEditingController(text: video.releaseDate ?? '');
    final tecDuration = TextEditingController(text: video.duration?.toString() ?? '');
    final tecStudio = TextEditingController(text: video.studio ?? '');
    final tecLabel = TextEditingController(text: video.label ?? '');
    final tecDirector = TextEditingController(text: video.director ?? '');
    final tecSeries = TextEditingController(text: video.series ?? '');

    final actresses = [...?video.actress];
    final categories = [...?video.category];

    WidgetsBinding.instance.scheduleFrame();
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: Get.width < 552 ? Get.width - 32 : 520,
        height: Get.height * .8,
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.container,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 8, 10), child: Row(children: [
            Expanded(child: Text(
              'Edit Metadata @{videoCode}'.trNamed({'videoCode': '${video.videoCode.isNotEmptyAndNotNull ? '(${video.videoCode})' : ''}'}),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColor.text),
            )),
            iconButton('Close'.tr, CupertinoIcons.xmark, () => Overlayment.dismissLast()),
          ])),
          Divider(height: 1, thickness: .5, color: AppColor.border),
          Expanded(child: SingleChildScrollView(child: Column(children: [
            section('Basic Info'.tr, [
              inputField(label: 'Video Code'.tr, controller: tecVideoCode, placeholder: 'Leave empty for NON-JAV'.tr),
              inputField(label: 'Title'.tr, controller: tecTitle, placeholder: 'Title'.tr, multiline: true),
              inputField(
                label: 'Cover URL'.tr, controller: tecFanArt, placeholder: 'Paste image URL here...'.tr,
                keyboardType: TextInputType.url,
                labelAction: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 28),
                  onPressed: () {
                    tecFanArt.text = 'https://img3.javmost.ws/images/480/${HelperMisc.resolveVideoCode(videoPath: video.videoPath)}.webp';
                  },
                  child: Text('Get From JavMost'.tr, style: const TextStyle(fontSize: 11)),
                ),
              ),
            ]),
            section('Cast & Tags'.tr, [
              GetBuilder<HomeController>(
                init: Get.find<HomeController>(),
                builder: (controller) => Padding(padding: const EdgeInsets.all(12), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text('Actress'.tr, style: TextStyle(fontSize: 12, color: AppColor.text))),
                      iconButton('Add actress'.tr, CupertinoIcons.add, () => _showDialogAddActress(actresses)),
                    ]),
                    if (actresses.isEmpty)
                      Text('No actress added'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))
                    else Wrap(spacing: 8, runSpacing: 8, children: actresses.map((actress) {
                      final name = actress.nameRomaji ?? actress.nameKana ?? actress.nameKanji ?? '';
                      return Container(
                        width: 96, padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: AppColor.container, borderRadius: BorderRadius.circular(8)),
                        child: Column(children: [
                          Row(children: [
                            ExThumbnail(
                              imageUrl: actress.imageUrl.isNotEmptyAndNotNull ? actress.imageUrl!.genAvatarUrl() : '', width: 44, height: 44,
                              fitUrl: BoxFit.cover, withProxy: false, iconSize: AppStyle.largeIconSize,
                            ).cornerRadius(22),
                            iconButton('${'Delete'.tr} $name', CupertinoIcons.xmark, () {
                              actresses.remove(actress);
                              controller.update();
                            }, size: 10),
                          ]),
                          const SizedBox(height: 6),
                          Tooltip(message: name, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppColor.text))),
                        ]),
                      );
                    }).toList()),
                  ],
                )),
              ),
              GetBuilder<HomeController>(
                init: Get.find<HomeController>(),
                builder: (controller) => Padding(padding: const EdgeInsets.all(12), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text('Category'.tr, style: TextStyle(fontSize: 12, color: AppColor.text))),
                      iconButton('Add category'.tr, CupertinoIcons.add, () => _showDialogAddCategory(categories)),
                    ]),
                    if (categories.isEmpty)
                      Text('No category added'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))
                    else Wrap(spacing: 8, runSpacing: 8, children: categories.map((cat) => Container(
                      padding: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(color: AppColor.container, borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(cat.category ?? '', style: TextStyle(fontSize: 11, color: AppColor.text))),
                        iconButton('${'Delete'.tr} ${cat.category ?? ''}', CupertinoIcons.xmark, () {
                          categories.remove(cat);
                          controller.update();
                        }, size: 10),
                      ]),
                    )).toList()),
                  ],
                )),
              ),
            ]),
            section('Metadata'.tr, [
              inputField(label: 'Release Date'.tr, controller: tecReleaseDate, placeholder: 'YYYY-MM-DD',
                keyboardType: TextInputType.datetime),
              inputField(label: 'Duration (minutes)'.tr, controller: tecDuration, placeholder: 'e.g. 120',
                keyboardType: TextInputType.number),
              inputField(label: 'Studio'.tr, controller: tecStudio, placeholder: 'Studio name'.tr),
              inputField(label: 'Label'.tr, controller: tecLabel, placeholder: 'Label name'.tr),
              inputField(label: 'Director'.tr, controller: tecDirector, placeholder: 'Director'.tr),
              inputField(label: 'Series'.tr, controller: tecSeries, placeholder: 'Series'.tr),
            ]),
          ]))),
          Divider(height: 1, thickness: .5, color: AppColor.border),
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32),
              onPressed: () => _remove(video),
              child: Text('Delete'.tr, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemRed)),
            ),
            const Spacer(),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 20), minimumSize: const Size(0, 32),
              borderRadius: BorderRadius.circular(AppStyle.radius),
              onPressed: () {
                final videoCode = tecVideoCode.text.trim().toUpperCase();
                if (videoCode.isNotEmpty && !videoCode.isValidVideoCode()) {
                  HelperToast.warn('Video code not valid'.tr);
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
              child: Text('Submit'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ])),
        ]),
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
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        child: VStack(
          [
            'Add Category'.tr.text.bold.make().pOnly(bottom: 16),
            ExAutoComplate(
              controller: tecCategory,
              items: categoriesNames,
              placeHolder: 'Type something...'.tr,
              onSelected: (cat) => tecCategory.text = cat,
            ).pOnly(bottom: 12),
            AppButton(variant: AppButtonVariant.filled,
              width: double.infinity,
              label: 'Submit'.tr,
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
        backgroundSettings: BackgroundSettings(blur: 5, color: AppColor.appBar.withAlpha(10)),
        animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
        color: AppColor.panel,
        child: VStack(
          [
            'Add Actress'.tr.text.bold.make().pOnly(bottom: 16),
            ExAutoComplate(
              controller: tecActress,
              items: actressesNameRomaji,
              placeHolder: 'Type something...'.tr,
              onSelected: (actress) => tecActress.text = actress,
            ).pOnly(bottom: 12),
            AppButton(variant: AppButtonVariant.filled,
              width: double.infinity,
              label: 'Submit'.tr,
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
