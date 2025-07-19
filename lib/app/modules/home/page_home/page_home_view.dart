import 'package:cached_network_image/cached_network_image.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_color.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_misc.dart';
import '../page_search/page_search_overlay.dart';
import 'page_home_controller.dart';

class PageHomeView extends GetView<PageHomeController> {
  const PageHomeView({super.key});
  @override
  Widget build(BuildContext context) {
    return VStack(
      [
        ExButtonElevated(
          label: 'Delete all data',
          onPressed: () => controller.test(),
        ),

        // New Release
        HStack([
          'New Release'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
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
                ).wh(double.infinity, 120),
        ),

        // Top 10: Watch again and again
        HStack([
          'Watch again and again'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
            onPressed: () => controller.getListTop10Watch(),
          ),
        ]).pOnly(bottom: 8, top: 8),
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

        // Favorite videos
        HStack([
          'Favorite videos'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
            onPressed: () => controller.getListFavorite(),
          ),
        ]).pOnly(bottom: 8, top: 8),
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

        // Featured Actress
        HStack([
          'Featured Actress'.text.size(12).make(),
          Spacer(),
          IconButton(
            icon: Icon(CupertinoIcons.refresh, size: 16),
            onPressed: () {},
          ),
        ]).pOnly(bottom: 8, top: 8),
        ListView.builder(
          itemCount: 5,
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            return Container(
              width: 120,
              color: AppColor.container,
            ).cornerRadius(8).pOnly(left: 4, right: 4);
          },
        ).wh(double.infinity, 200),
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
        if (video.poster == null || video.poster == '') ...[
          FutureBuilder(
            future: controller.getThumbnail(video.videoPath ?? ''),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Icon(
                  CupertinoIcons.photo,
                  size: 32,
                ).wh(200, 120).color(Vx.neutral900);
              }

              return snapshot.hasData ? Image.memory(snapshot.data!, fit: BoxFit.cover, width: 200, height: 120) : 0.heightBox;
            },
          ),
        ] else ...[
          CachedNetworkImage(
            imageUrl: '${video.fanArt?.imgUrl()}',
            width: 200,
            height: 120,
            fit: BoxFit.fitWidth,
          ),
        ],
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
        if (video.poster == null || video.poster == '') ...[
          FutureBuilder(
            future: controller.getThumbnail(video.videoPath ?? ''),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Icon(CupertinoIcons.photo, size: 64).centered().color(Vx.neutral900);
              }

              return snapshot.hasData ? Image.memory(snapshot.data!, fit: BoxFit.cover, width: 120, height: 200) : 0.heightBox;
            },
          ),
        ] else ...[
          CachedNetworkImage(
            imageUrl: '${video.poster?.imgUrl()}',
            width: 120,
            height: 200,
            fit: BoxFit.fitHeight,
          ),
        ],
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
          height: 120,
          color: AppColor.container,
        ).cornerRadius(8).pOnly(right: 8);
      },
    ).wh(double.infinity, 120);
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
