import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../data/models/videos_entity.dart';
import '../../widgets/widgets.dart';
import '../page_search/page_search_overlay.dart';
import 'page_home_controller.dart';

class PageHomeView extends GetView<PageHomeController> {
  const PageHomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return Obx(
      () => controller.totalVideo.value != 0
          ? buildPage()
          : ExUiErrorOrEmpty(
              illustration: Icon(UIconsPro.regularRounded.mug_hot_alt),
              title: '~ Fresh ~',
              message: 'No Data Found, Please Add New Library First or just \n`drag your JAV Video Folder here`',
            ),
    );
  }

  Widget buildPage() {
    return VStack(
      [
        // New Release
        VStack(
          [
            HStack([
              '🎉 New Release'.text.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListNewRelease(),
              ),
            ]).pOnly(bottom: 8),
            Obx(
              () => controller.listNewRelease.isEmpty
                  ? buildLayoutEmptyFanArt()
                  : ListView.builder(
                      itemCount: controller.listNewRelease.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = controller.listNewRelease[index];
                        return buildLayoutFanArt(video);
                      },
                    ).wh(double.infinity, 150),
            ),
          ],
        ).hide(isVisible: controller.listNewRelease.isNotEmpty),

        // Random Videos
        VStack(
          [
            HStack([
              '👍🏻 Video Maybe you like'.text.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListRandom(),
              ),
            ]).pSymmetric(v: 12),
            Obx(
              () => controller.listRandom.isEmpty
                  ? buildLayoutEmptyPoster()
                  : ListView.builder(
                      itemCount: controller.listRandom.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = controller.listRandom[index];
                        return buildLayoutPoster(video, showViewCount: false);
                      },
                    ).wh(double.infinity, 200),
            ),
          ],
        ).hide(isVisible: controller.listRandom.isNotEmpty),

        // Top 10: Watch again and again
        VStack(
          [
            HStack([
              '👀 Watch again and again'.text.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListTop10Watch(),
              ),
            ]).pSymmetric(v: 12),
            Obx(
              () => controller.listTop10Watch.isEmpty
                  ? buildLayoutEmptyPoster()
                  : ListView.builder(
                      itemCount: controller.listTop10Watch.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = controller.listTop10Watch[index];
                        return buildLayoutPoster(video, showViewCount: true);
                      },
                    ).wh(double.infinity, 200),
            ),
          ],
        ).hide(isVisible: controller.listTop10Watch.isNotEmpty),

        // Favorite videos
        VStack(
          [
            HStack([
              '⭐ Favorite videos'.text.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListFavorite(),
              ),
            ]).pSymmetric(v: 12),
            Obx(
              () => controller.listFavorite.isEmpty
                  ? buildLayoutEmptyPoster()
                  : ListView.builder(
                      itemCount: controller.listFavorite.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = controller.listFavorite[index];
                        return buildLayoutPoster(video, showViewCount: false);
                      },
                    ).wh(double.infinity, 200),
            ),
          ],
        ).hide(isVisible: controller.listFavorite.isNotEmpty),

        // new added
        VStack(
          [
            HStack([
              '🆕 New Added'.text.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListNewAdded(),
              ),
            ]).pSymmetric(v: 12),
            Obx(
              () => controller.listNewAdded.isEmpty
                  ? buildLayoutEmptyPoster()
                  : ListView.builder(
                      itemCount: controller.listNewAdded.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = controller.listNewAdded[index];
                        return buildLayoutPoster(video, showViewCount: false);
                      },
                    ).wh(double.infinity, 200),
            ),
          ],
        ).hide(isVisible: controller.listNewAdded.isNotEmpty),

        // never watch
        VStack(
          [
            HStack([
              '👁️‍🗨️ Never Watch'.text.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListNeverWatch(),
              ),
            ]).pSymmetric(v: 12),
            Obx(
              () => controller.listNeverWatch.isEmpty
                  ? buildLayoutEmptyPoster()
                  : ListView.builder(
                      itemCount: controller.listNeverWatch.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = controller.listNeverWatch[index];
                        return buildLayoutPoster(video, showViewCount: false);
                      },
                    ).wh(double.infinity, 200),
            ),
          ],
        ).hide(isVisible: controller.listNeverWatch.isNotEmpty),

        // oldest
        VStack(
          [
            HStack([
              '👴🏻 Oldest'.text.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListOldest(),
              ),
            ]).pSymmetric(v: 12),
            Obx(
              () => controller.listOldest.isEmpty
                  ? buildLayoutEmptyPoster()
                  : ListView.builder(
                      itemCount: controller.listOldest.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = controller.listOldest[index];
                        return buildLayoutPoster(video, showViewCount: false);
                      },
                    ).wh(double.infinity, 200),
            ),
          ],
        ).hide(isVisible: controller.listOldest.isNotEmpty),

        // playlist ~
        VStack(
          [
            HStack([
              'Playlist'.text.bold.size(12).make(),
              Spacer(),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListRandom(),
              ),
              IconButton(
                icon: Icon(CupertinoIcons.add, size: 16),
                onPressed: () => controller.addOrEditPlaylist(),
              ),
            ]).pSymmetric(v: 12),
            Obx(
              () => ListView.builder(
                itemCount: controller.listPlaylistHeader.length,
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final item = controller.listPlaylistHeader[index];
                  return Container(
                    height: 70,
                    width: 150,
                    color: AppColor.selected,
                    child: ZStack([
                      '${item.name}'.text.ellipsis.bold.make().positioned(bottom: 0, right: 0),
                    ]).p12(),
                  ).onInkTap(() => controller.addOrEditPlaylist(header: item)).cornerRadius(8).pOnly(right: 12);
                },
              ).wh(double.infinity, 70),
            ),
          ],
        ).hide(),
      ],
    ).scrollVertical();
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ ~
  // ────────────────────────────────────────────────────────────────
  Widget buildLayoutFanArt(Videos video) {
    return Container(
      color: AppColor.container,
      child: ZStack([
        ExThumbnail(
          imageUrl: video.fanArt,
          videoPath: video.videoPath,
          width: 200,
          height: 150,
          fitUrl: BoxFit.cover,
          fitMemory: BoxFit.fitWidth,
        ),
        Container(
          color: Vx.black.withAlpha(150),
          height: 20,
          width: 200,
          child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
        ).positioned(bottom: 0),
      ]),
    ).cornerRadius(8).pOnly(right: 8).onInkTap(() => PageSearchOverlay.onItemTap(video));
  }

  Widget buildLayoutPoster(Videos video, {bool showViewCount = false}) {
    return Container(
      color: AppColor.container,
      child: ZStack([
        ExThumbnail(
          imageUrl: video.fanArt,
          videoPath: video.videoPath,
          width: 120,
          height: 200,
          prefix: 2.5,
          fitUrl: BoxFit.fitWidth,
        ),
        showViewCount ? ' View: ${video.viewCount}'.text.size(10).minFontSize(10).make().wh(63, 17).color(Vx.black.withAlpha(150)).positioned() : 0.heightBox,
        Container(
          color: Vx.black.withAlpha(150),
          height: 20,
          width: 120,
          child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
        ).positioned(bottom: 0),
      ]),
    ).cornerRadius(8).pOnly(right: 8).onInkTap(() => PageSearchOverlay.onItemTap(video));
  }

  Widget buildLayoutEmptyFanArt() {
    return ListView.builder(
      itemCount: 10,
      scrollDirection: Axis.horizontal,
      itemBuilder: (context, index) {
        return Container(
          width: 200,
          height: 150,
          color: AppColor.container,
        ).cornerRadius(8).pOnly(right: 8);
      },
    ).wh(double.infinity, 150);
  }

  Widget buildLayoutEmptyPoster() {
    return ListView.builder(
      itemCount: 10,
      scrollDirection: Axis.horizontal,
      itemBuilder: (context, index) {
        return Container(
          width: 120,
          height: 200,
          color: AppColor.container,
        ).cornerRadius(8).pOnly(right: 8);
      },
    ).wh(double.infinity, 200);
  }
}
