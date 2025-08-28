import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../../env.g.dart';
import '../../core/app_color.dart';
import '../../core/app_logging.dart';
import '../../data/models/videos_entity.dart';
import '../widgets/widgets.dart';
import 'home_controller.dart';

mixin HomeEditVideoDetail {
  static Future<void> onEditVideoDetail(Videos video) async {
    final tecTitle = TextEditingController(text: video.title ?? '');
    final tecFanArt = TextEditingController(text: video.fanArt ?? '');
    final tecReleaseDate = TextEditingController(text: video.releaseDate ?? '');
    final tecDuration = TextEditingController(text: video.duration.toString());
    final tecStudio = TextEditingController(text: video.studio ?? '');
    final tecLabel = TextEditingController(text: video.label ?? '');
    final tecDirector = TextEditingController(text: video.director ?? '');
    final tecSeries = TextEditingController(text: video.series ?? '');

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: Get.width * 50 / 100,
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
                'Edit Metadata (${video.videoCode ?? ''})'.text.bold.white.make().pOnly(bottom: 16),
                HStack([
                  'Title'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecTitle,
                    placeholder: 'Title',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]).pSymmetric(v: 8),
                HStack([
                  'Cover URL'.text.size(13).make().w(100),
                  CupertinoTextField(
                    controller: tecFanArt,
                    placeholder: 'Cover URL',
                    style: TextStyle(fontSize: 13, color: Vx.white),
                  ).expand(),
                ]).pSymmetric(v: 8),
                HStack([
                  'Actress'.text.make(),
                  Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(CupertinoIcons.add, size: 16),
                  ),
                ]),
                ListView.builder(
                  itemCount: video.actress?.length ?? 0,
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final item = video.actress?[index];
                    return VStack([
                      ExThumbnail(
                        imageUrl: '${Env.actressUrl}/${item?.imageUrl ?? ''}',
                        width: 48,
                        height: 48,
                        fitUrl: BoxFit.cover,
                        withProxy: false,
                        iconSize: 24,
                      ).cornerRadius(90).tooltip(item?.nameRomaji ?? item!.nameKana!).pOnly(right: 8),
                    ]);
                  },
                ).h(48).pSymmetric(v: 8),
                HStack([
                  'Category'.text.make(),
                  Spacer(),
                  IconButton(
                    onPressed: () async {
                      await _addCategory(video);
                    },
                    icon: Icon(CupertinoIcons.add, size: 16),
                  ),
                ]),
                GetBuilder(
                  init: Get.find<HomeController>(),
                  builder: (c) {
                    return ListView.builder(
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: video.category?.length ?? 0,
                      scrollDirection: Axis.vertical,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final item = video.category?[index];
                        return VStack([
                          '${item?.id ?? ''} ${item?.category ?? ''}'.text.minFontSize(11).size(11).neutral500.make(),
                        ]);
                      },
                    ).pSymmetric(v: 8);
                  },
                ),
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
              color: AppColor.selected,
              width: Get.width * 50 / 100,
              child: ExButtonText(
                label: 'Submit',
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
                  _submit(edited);
                },
              ),
            ).positioned(bottom: 0, right: 0),
          ],
        ),
      ),
    );
  }

  static Future<void> _submit(Videos video) async {
    AppLog.logD('video -> $video');
  }

  static Future<void> _addCategory(Videos video) async {
    final tecCategory = TextEditingController();

    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: 200,
        color: Vx.black,
        height: 144,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.bottomCenter,
          reverseDurationMilliseconds: 10,
          durationMilliseconds: 10,
        ),
        child: VStack(
          [
            'Add Category'.text.bold.make().pOnly(bottom: 16),
            CupertinoTextField(
              controller: tecCategory,
              placeholder: 'Name',
              style: TextStyle(fontSize: 13, color: Vx.white),
            ).pOnly(bottom: 12),
            ExButtonElevated(
              width: double.infinity,
              label: 'Submit',
              onPressed: () {
                if (tecCategory.text.isEmpty) return;
                final newCat = VideoCategory(
                  id: ExRandom.between(100000, 999999),
                  category: tecCategory.text,
                );
                video.category?.add(newCat);
                Get.find<HomeController>().update();
                Overlayment.dismissLast();
              },
            )
          ],
        ).p12(),
      ),
    );
  }
}
