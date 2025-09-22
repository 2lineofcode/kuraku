import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../core/const.dart';
import '../../../data/models/videos_entity.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';
import '../page_explore/page_explore_controller.dart';
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
              illustration: Icon(UIconsPro.regularRounded.square_dashed_circle_plus, size: 128),
              title: '~ Fresh ~',
              message: 'Hi There, Select Or Drag & Drop your JAV Folder Here',
            ),
    );
  }

  Widget buildPage() {
    return VStack(
      [
        _buildVideoSection(
          title: 'New Release',
          icon: Icon(UIconsPro.solidRounded.flame, size: 12, color: Colors.amber),
          height: 170,
          list: controller.listNewRelease,
          prefKey: AppPref.homeSecNewRelease,
          refreshAction: controller.getListNewRelease,
          layoutBuilder: (video) => buildLayoutFanArt(video, showReleaseDate: true),
          emptyLayoutBuilder: buildLayoutEmptyFanArt,
        ),
        _buildVideoSection(
          title: 'Random Video',
          icon: Icon(UIconsPro.solidRounded.shuffle, size: 12, color: Vx.blue300),
          list: controller.listRandom,
          prefKey: AppPref.homeSecRandom,
          refreshAction: controller.getListRandom,
          layoutBuilder: (video) => buildLayoutPoster(video, showViewCount: false),
          emptyLayoutBuilder: buildLayoutEmptyPoster,
          showDirectToExplore: false,
        ),
        _buildVideoSection(
          title: 'Most Watch',
          icon: Icon(UIconsPro.solidRounded.cursor_finger, size: 12, color: Vx.pink300),
          list: controller.listTop10Watch,
          prefKey: AppPref.homeSecMostWatch,
          refreshAction: controller.getListMostWatch,
          layoutBuilder: (video) => buildLayoutPoster(video, showViewCount: true),
          emptyLayoutBuilder: buildLayoutEmptyPoster,
        ),
        _buildVideoSection(
          title: 'Favorite',
          icon: Icon(UIconsPro.solidRounded.square_heart, size: 12, color: Vx.red400),
          list: controller.listFavorite,
          prefKey: AppPref.homeSecFavorite,
          refreshAction: controller.getListFavorite,
          layoutBuilder: (video) => buildLayoutPoster(video, showViewCount: false),
          emptyLayoutBuilder: buildLayoutEmptyPoster,
        ),
        _buildVideoSection(
          title: 'New Added',
          icon: Icon(UIconsPro.solidRounded.add_document, size: 12, color: Vx.cyan400),
          list: controller.listNewAdded,
          prefKey: AppPref.homeSecNewAdd,
          refreshAction: controller.getListNewAdded,
          layoutBuilder: (video) => buildLayoutPoster(video, showViewCount: false),
          emptyLayoutBuilder: buildLayoutEmptyPoster,
        ),
        _buildVideoSection(
          title: 'Never Watch',
          icon: Icon(UIconsPro.solidRounded.popcorn, size: 12, color: Vx.green400),
          list: controller.listNeverWatch,
          prefKey: AppPref.homeSecNeverWatch,
          refreshAction: controller.getListNeverWatch,
          layoutBuilder: (video) => buildLayoutPoster(video, showViewCount: false),
          emptyLayoutBuilder: buildLayoutEmptyPoster,
        ),
        _buildVideoSection(
          title: 'Oldest',
          icon: Icon(UIconsPro.solidRounded.olive_branch_dove, size: 12, color: Vx.lime300),
          list: controller.listOldest,
          prefKey: AppPref.homeSecOldest,
          refreshAction: controller.getListOldest,
          layoutBuilder: (video) => buildLayoutPoster(video, showViewCount: false),
          emptyLayoutBuilder: buildLayoutEmptyPoster,
          showDirectToExplore: false,
        ),
        _buildPlaylistSection(),
      ],
    ).scrollVertical();
  }

  /// Builds a generic section for displaying a list of videos.
  Widget _buildVideoSection({
    required String title,
    required Widget icon,
    required RxList<Videos> list,
    required String prefKey,
    required VoidCallback refreshAction,
    required Widget Function(Videos video) layoutBuilder,
    required Widget Function() emptyLayoutBuilder,
    double? width,
    double? height,
    bool? showDirectToExplore = true,
  }) {
    return VStack(
      [
        HStack([
          Container(
            decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
            child: HStack([
              icon.pOnly(right: 8),
              title.text.size(12).make(),
            ]).pSymmetric(h: 12, v: 4).onInkTap(() {
              final isVisible = !AppPref.getBool(prefKey);
              AppPref.setBool(prefKey, isVisible);
              controller.update();
            }),
          ),
          Spacer(),
          GetBuilder(
            init: controller,
            builder: (controller) {
              return IconButton(
                icon: Icon(
                  AppPref.getBool(prefKey) ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                  size: 12,
                ),
                onPressed: () async {
                  final isVisible = !AppPref.getBool(prefKey);
                  AppPref.setBool(prefKey, isVisible);
                  controller.update();
                },
              );
            },
          ),

          if (showDirectToExplore == true) ...[
            IconButton(
              icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
              onPressed: () async {
                await Get.find<HomeController>().onMenuChange(kMenuExplore);
                final exploreC = Get.find<PageExploreController>();
                await exploreC.onMenuChange(kCustom);
                exploreC.tecSearchLeft.text = title;
                exploreC.onLeftListDoSearch(title);
                await exploreC.onLeftListTap(exploreC.leftListFiltered[0]);
              },
            ),
          ],

          IconButton(
            icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
            onPressed: refreshAction,
          ),
        ]).pSymmetric(v: 12),
        GetBuilder(
          init: controller,
          builder: (controller) {
            return Obx(
              () => list.isEmpty
                  ? emptyLayoutBuilder()
                  : ListView.builder(
                      itemCount: list.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = list[index];
                        return layoutBuilder(video);
                      },
                    )
                      .wh(width ?? double.infinity, height ?? 210)
                      .hide(isVisible: AppPref.getBool(prefKey)),
            );
          },
        ),
      ],
    ).hide(isVisible: list.isNotEmpty);
  }

  /// Builds the playlist section.
  Widget _buildPlaylistSection() {
    return VStack(
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
    ).hide();
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget buildLayoutFanArt(
    Videos video, {
    bool showViewCount = false,
    bool showReleaseDate = false,
  }) {
    final double width = 260;
    return Container(
      color: AppColor.container,
      child: ZStack([
        ExThumbnail(
          imageUrl: video.fanArt,
          videoPath: video.videoPath,
          width: width,
          height: 170,
          fitUrl: BoxFit.cover,
          fitMemory: BoxFit.fitWidth,
        ),
        showViewCount ? ' View: ${video.viewCount}'.text.size(10).minFontSize(10).make().wh(70, 17).color(Vx.black.withAlpha(200)).positioned() : 0.heightBox,
        showReleaseDate ? ' ${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().wh(80, 17).color(Vx.black.withAlpha(200)).positioned() : 0.heightBox,
        Container(
          color: Vx.black.withAlpha(150),
          height: 20,
          width: width,
          child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
        ).positioned(bottom: 0),
      ]),
    ).cornerRadius(8).pOnly(right: 8).onInkTap(() => PageSearchOverlay.onItemTap(video));
  }

  Widget buildLayoutPoster(
    Videos video, {
    bool showViewCount = false,
    bool showReleaseDate = false,
  }) {
    final double width = 135;
    return Container(
      color: AppColor.container,
      child: ZStack([
        ExThumbnail(
          imageUrl: video.fanArt,
          videoPath: video.videoPath,
          width: width,
          height: 210,
          prefix: 2.3,
          fitUrl: BoxFit.fitWidth,
        ),
        showViewCount ? ' View: ${video.viewCount}'.text.size(10).minFontSize(10).make().wh(56, 17).color(Vx.black.withAlpha(200)).positioned() : 0.heightBox,
        showReleaseDate ? ' ${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().wh(80, 17).color(Vx.black.withAlpha(200)).positioned() : 0.heightBox,
        Container(
          color: Vx.black.withAlpha(150),
          height: 20,
          width: width,
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
