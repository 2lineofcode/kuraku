import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_color.dart';
import '../../../core/app_translations.dart';
import '../../../core/const.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';

mixin HomePanelMetadata {
  static Future<void> open(Videos video) async {
    final original = Videos.fromJson(video.toJson());
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

    var saving = false;
    var editorOpen = true;
    late OverPanel panel;
    panel = OverPanel(
        alignment: Alignment.center,
        actions: OverlayActions(canClose: (_) async {
          editorOpen = false;
          return true;
        }),
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
                      iconButton('Add actress'.tr, CupertinoIcons.add, () => _showDialogAddActress(actresses, isAvailable: () => editorOpen && !saving)),
                    ]),
                    if (actresses.isEmpty)
                      Text('No actress added'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))
                    else Wrap(spacing: 8, runSpacing: 8, children: actresses.map((actress) {
                      final name = _actressName(actress);
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
                      iconButton('Add category'.tr, CupertinoIcons.add, () => _showDialogAddCategory(categories, isAvailable: () => editorOpen && !saving)),
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
          StatefulBuilder(builder: (context, setState) => Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32),
              onPressed: saving ? null : () async {
                if (saving) return;
                setState(() => saving = true);
                await _remove(video, panel);
                if (context.mounted) setState(() => saving = false);
              },
              child: Text('Delete'.tr, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemRed)),
            ),
            const Spacer(),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 20), minimumSize: const Size(0, 32),
              borderRadius: BorderRadius.circular(AppStyle.radius),
              onPressed: saving ? null : () async {
                if (saving) return;
                final videoCode = tecVideoCode.text.trim().toUpperCase();
                if (videoCode.isNotEmpty && !videoCode.isValidVideoCode()) {
                  await HelperToast.warn('Video code not valid'.tr);
                  return;
                }
                final releaseDate = tecReleaseDate.text.trim();
                final parsedDate = DateTime.tryParse(releaseDate);
                if (releaseDate.isNotEmpty && (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(releaseDate) ||
                    parsedDate == null || parsedDate.toIso8601String().substring(0, 10) != releaseDate)) {
                  await HelperToast.warn('Enter a valid release date (YYYY-MM-DD) or leave it empty.'.tr);
                  return;
                }
                final durationText = tecDuration.text.trim();
                final duration = int.tryParse(durationText);
                if (durationText.isNotEmpty && (duration == null || duration < 0)) {
                  await HelperToast.warn('Enter a whole number of minutes (0 or more) or leave it empty.'.tr);
                  return;
                }
                final edited = Videos.fromJson(video.toJson());
                edited.videoCode = videoCode.getVideoCode();
                edited.title = tecTitle.text;
                edited.fanArt = tecFanArt.text.trim();
                edited.releaseDate = releaseDate;
                edited.releaseDateFormated = releaseDate.isEmpty ? '' : releaseDate.reformatDate(from: kYMd, to: kMdY);
                edited.duration = duration ?? 0;
                edited.durationFormated = HelperMisc.durationFormatDB(edited.duration!);
                edited.studio = tecStudio.text;
                edited.label = tecLabel.text;
                edited.director = tecDirector.text;
                edited.series = tecSeries.text;
                edited.category = categories;
                edited.actress = actresses;
                setState(() => saving = true);
                await _submit(edited, original, panel);
                if (context.mounted) setState(() => saving = false);
              },
              child: Text('Submit'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]))),
        ]),
    );
    WidgetsBinding.instance.scheduleFrame();
    try {
      await Overlayment.show(context: Get.context, panel);
    } finally {
      editorOpen = false;
      for (final controller in [tecVideoCode, tecTitle, tecFanArt, tecReleaseDate, tecDuration, tecStudio, tecLabel, tecDirector, tecSeries]) {
        controller.dispose();
      }
    }
  }

  static Future<void> _submit(Videos video, Videos original, OverPanel panel) async {
    try {
      await DBVideos.update(video, original: original);
      await Overlayment.dismiss(panel);
    } catch (e) {
      await HelperToast.error(e is StateError ? '${e.message}'.tr : e.toString());
    }
  }

  static Future<void> _remove(Videos video, OverPanel panel) async {
    try {
      await DBVideos.delete(video);
      await Overlayment.dismiss(panel);
    } catch (e) {
      await HelperToast.error(e.toString());
    }
  }

  static Future<void> _showDialogAddCategory(List<VideoCategory> currentCategories, {required bool Function() isAvailable}) async {
    if (!isAvailable()) return;
    final tecCategory = TextEditingController();

    try {
      final categories = (await DBR18.getAllCategories()).where((category) => category['name_en'] is String
        && (category['name_en'] as String).trim().isNotEmpty).toList();
      if (!isAvailable()) return;
      final categoriesNames = categories.map((category) => '${category['name_en']}').toList();
      var submitted = false;

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
                  if (submitted) return;
                  final category = categories.firstWhereOrNull((category) => (category['name_en'] as String).trim() == tecCategory.text.trim());
                  if (category == null) {
                    await HelperToast.warn('Choose a category from the suggestions.'.tr);
                    return;
                  }
                  final id = num.tryParse('${category['id']}');
                  if (id == null) {
                    await HelperToast.warn('Choose a category from the suggestions.'.tr);
                    return;
                  }
                  submitted = true;
                  if (!currentCategories.any((existing) => existing.category?.trim().toLowerCase() == '${category['name_en']}'.trim().toLowerCase())) {
                    currentCategories.add(VideoCategory(id: id, category: category['name_en'] as String));
                  }
                  Get.find<HomeController>().update();
                  await Overlayment.dismissLast();
                },
              ),
            ],
          ).p12(),
        ),
      );
    } catch (e) {
      if (isAvailable()) await HelperToast.error(e.toString());
    } finally {
      tecCategory.dispose();
    }
  }

  static Future<void> _showDialogAddActress(List<VideoActress> currentActresses, {required bool Function() isAvailable}) async {
    if (!isAvailable()) return;
    final tecActress = TextEditingController();

    try {
      final actresses = (await DBR18.getAllActress()).map(VideoActress.fromJson).toList();
      if (!isAvailable()) return;
      final actressesNames = actresses.map(_actressName).toList();
      var submitted = false;

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
                items: actressesNames,
                placeHolder: 'Type something...'.tr,
                onSelected: (actress) => tecActress.text = actress,
              ).pOnly(bottom: 12),
              AppButton(variant: AppButtonVariant.filled,
                width: double.infinity,
                label: 'Submit'.tr,
                onPressed: () async {
                  if (submitted) return;
                  final actress = actresses.firstWhereOrNull((actress) => _actressName(actress) == tecActress.text.trim());
                  if (actress == null || actress.id == null) {
                    await HelperToast.warn('Choose an actress from the suggestions.'.tr);
                    return;
                  }
                  submitted = true;
                  if (!currentActresses.any((existing) => existing.id == actress.id)) {
                    currentActresses.add(actress);
                  }
                  Get.find<HomeController>().update();
                  await Overlayment.dismissLast();
                },
              ),
            ],
          ).p12(),
        ),
      );
    } catch (e) {
      if (isAvailable()) await HelperToast.error(e.toString());
    } finally {
      tecActress.dispose();
    }
  }

  static String _actressName(VideoActress actress) => [actress.nameRomaji, actress.nameKana, actress.nameKanji]
    .firstWhereOrNull((name) => name != null && name.trim().isNotEmpty)?.trim() ?? '';
}
