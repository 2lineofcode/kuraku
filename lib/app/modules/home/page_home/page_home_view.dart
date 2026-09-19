import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../core/const.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_video_info.dart';
import '../page_explore/page_explore_controller.dart';
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
    return Obx(
      () => ReorderableListView.builder(
        key: const PageStorageKey('home-sections'),
        buildDefaultDragHandles: false,
        onReorderItem: (int oldIndex, int newIndex) {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = controller.homeSectionOrder.removeAt(oldIndex);
          controller.homeSectionOrder.insert(newIndex, item);
          AppPref.setHomeOrderList(controller.homeSectionOrder.value);
          
        },
        itemCount: controller.homeSectionOrder.length,
        itemBuilder: (context, index) {
          final sectionKey = controller.homeSectionOrder[index];
          switch (sectionKey) {
            case AppPref.homeSecNewRelease:
              return Obx(
                key: ValueKey(AppPref.homeSecNewRelease),
                () => _buildVideoSection(
                  title: 'New Release',
                  icon: Icon(UIconsPro.solidRounded.flame, size: 12, color: Colors.amber),
                  height: 170,
                  list: controller.listNewRelease,
                  prefKey: AppPref.homeSecNewRelease,
                  refreshAction: controller.getListNewRelease,
                  layoutBuilder: (video) => buildLayoutFanArt(video),
                  emptyLayoutBuilder: buildLayoutEmptyFanArt,
                  index: index,
                ),
              );
            case AppPref.homeSecRecommendation:
              return Obx(
                key: ValueKey(AppPref.homeSecRecommendation),
                () => _buildVideoSection(
                  title: 'Recommended for You',
                  // subtitle: controller.recommendationSubtitle.value,
                  icon: Icon(UIconsPro.solidRounded.sparkles, size: 12, color: Vx.amber300),
                  list: controller.listRecommendation,
                  prefKey: AppPref.homeSecRecommendation,
                  refreshAction: controller.getListRecommendation,
                  layoutBuilder: (video) => buildLayoutPoster(video),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  showDirectToExplore: false,
                  index: index,
                ),
              );
            case AppPref.homeSecRandom:
              return Obx(
                key: ValueKey(AppPref.homeSecRandom),
                () => _buildVideoSection(
                  title: 'Random Video',
                  icon: Icon(UIconsPro.solidRounded.shuffle, size: 12, color: Vx.blue300),
                  list: controller.listRandom,
                  prefKey: AppPref.homeSecRandom,
                  refreshAction: controller.getListRandom,
                  layoutBuilder: (video) => buildLayoutPoster(video),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  showDirectToExplore: false,
                  index: index,
                ),
              );
            case AppPref.homeSecMostWatch:
              return Obx(
                key: ValueKey(AppPref.homeSecMostWatch),
                () => _buildVideoSection(
                  title: 'Most Watch',
                  icon: Icon(UIconsPro.solidRounded.cursor_finger, size: 12, color: Vx.pink300),
                  list: controller.listTop10Watch,
                  prefKey: AppPref.homeSecMostWatch,
                  refreshAction: controller.getListMostWatch,
                  layoutBuilder: (video) => buildLayoutPoster(video),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecFavorite:
              return Obx(
                key: ValueKey(AppPref.homeSecFavorite),
                () => _buildVideoSection(
                  title: 'Favorite',
                  icon: Icon(UIconsPro.solidRounded.square_heart, size: 12, color: Vx.red400),
                  list: controller.listFavorite,
                  prefKey: AppPref.homeSecFavorite,
                  refreshAction: controller.getListFavorite,
                  layoutBuilder: (video) => buildLayoutPoster(video),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecNewAdd:
              return Obx(
                key: ValueKey(AppPref.homeSecNewAdd),
                () => _buildVideoSection(
                  title: 'New Added',
                  icon: Icon(UIconsPro.solidRounded.add_document, size: 12, color: Vx.cyan400),
                  list: controller.listNewAdded,
                  prefKey: AppPref.homeSecNewAdd,
                  refreshAction: controller.getListNewAdded,
                  layoutBuilder: (video) => buildLayoutPoster(video),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecNeverWatch:
              return Obx(
                key: ValueKey(AppPref.homeSecNeverWatch),
                () => _buildVideoSection(
                  title: 'Never Watch',
                  icon: Icon(UIconsPro.solidRounded.popcorn, size: 12, color: Vx.green400),
                  list: controller.listNeverWatch,
                  prefKey: AppPref.homeSecNeverWatch,
                  refreshAction: controller.getListNeverWatch,
                  layoutBuilder: (video) => buildLayoutPoster(video),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecOldest:
              return Obx(
                key: ValueKey(AppPref.homeSecOldest),
                () => _buildVideoSection(
                  title: 'Oldest',
                  icon: Icon(UIconsPro.solidRounded.olive_branch_dove, size: 12, color: Vx.lime300),
                  list: controller.listOldest,
                  prefKey: AppPref.homeSecOldest,
                  refreshAction: controller.getListOldest,
                  layoutBuilder: (video) => buildLayoutPoster(video),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  showDirectToExplore: false,
                  index: index,
                ),
              );
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _buildVideoSection({
    Key? key,
    required int index,
    required String title,
    String? subtitle,
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
      key: key,
      [
        HStack([
          Container(
            decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
            child: HStack([
              MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: ReorderableDragStartListener(
                  index: index,
                  child: icon.pOnly(right: 8),
                ),
              ),
              title.text.size(12).make(),
              if (subtitle != null && subtitle.isNotEmpty) subtitle.text.size(9).color(Vx.neutral400).maxLines(1).ellipsis.make().pOnly(left: 8),
            ]).pSymmetric(h: 12, v: 4).onInkTap(() {
              final isVisible = !AppPref.getBool(prefKey);
              AppPref.setBool(prefKey, isVisible);
              controller.update();
            }),
          ),
          Spacer(),

          IconButton(
            icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
            onPressed: refreshAction,
          ),

          if (showDirectToExplore == true) ...[
            IconButton(
              icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
              onPressed: () async {
                await Get.find<HomeController>().onMenuChange(kMenuExplore);
                final exploreC = Get.find<PageExploreController>();
                await exploreC.openSelection(kCustom, title);
              },
            ),
          ],

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

        ]).pSymmetric(v: 12),
        GetBuilder(
          init: controller,
          builder: (controller) {
            return Obx(
              () => list.isEmpty
                  ? emptyLayoutBuilder()
                  : ListView.builder(
                      key: PageStorageKey('home-videos-$prefKey'),
                      itemCount: list.length,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = list[index];
                        return layoutBuilder(video);
                      },
                    ).wh(width ?? double.infinity, height ?? 210).hide(isVisible: AppPref.getBool(prefKey)),
            );
          },
        ),
      ],
    ).hide(isVisible: list.isNotEmpty, key: key);
  }


  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget buildLayoutFanArt(Videos video) {
    final double width = 260;
    return DoubleTap(
      onSingleTap: () => HomePanelVideoInfo.open(video),
      onDoubleTap: () => HelperOpener.openVideoFile(video),
      child: Container(
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

          // Release date
          Container(
            color: AppColor.black180,
            child: HStack([
              Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
              video.releaseDate.isNotEmptyAndNotNull
                  ? '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Release date: ${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}')
                  : '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Added at: ${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}')
            ]).p4(),
          ).cornerRadius(8).p2(),

          // Video title
          Container(
            color: AppColor.black180,
            height: 20,
            width: width,
            child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
          ).positioned(bottom: 0),
        ]),
      ).cornerRadius(8).pOnly(right: 8),
    );
  }

  Widget buildLayoutPoster(
    Videos video, {
    double width = 135,
    double height = 210,
    showReleaseDate = true,
    showViewCount = true,
    showQuality = true,
  }) {
    return DoubleTap(
      onSingleTap: () async => await HomePanelVideoInfo.open(video),
      onDoubleTap: () async => await HelperOpener.openVideoFile(video),
      child: Container(
        color: AppColor.container,
        child: ZStack([
          ExThumbnail(
            imageUrl: video.fanArt,
            videoPath: video.videoPath,
            width: width,
            height: height,
            prefix: 2.3,
            fitUrl: BoxFit.fitWidth,
          ),

          // sub id?
          if (video.videoPath?.isHasIdSub() == true) ...[
            Container(
              color: Vx.blue600.withAlpha(200),
              child: HStack([
                '🇮🇩'.text.size(10).minFontSize(10).make().tooltip('ID Sub'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

           // sub en?
          if (video.videoPath?.isHasEnSub() == true) ...[
            Container(
              color: Vx.purple600.withAlpha(200),
              child: HStack([
                '🇬🇧'.text.size(10).minFontSize(10).make().tooltip('EN Sub'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // reduce mosaic?
          if (video.videoPath?.isHasUncensored() == true) ...[
            Container(
              color: Vx.red600.withAlpha(200),
              child: HStack([
                '🎞️'.text.size(10).minFontSize(10).make().tooltip('Reduce Mosaic'),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // Release date
          if (showReleaseDate) ...[
            Container(
              color: AppColor.black180,
              child: HStack([
                Icon(UIconsPro.solidRounded.calendar, size: 10).pOnly(right: 5),
                video.releaseDate.isNotEmptyAndNotNull
                    ? '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Release date: ${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}')
                    : '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Added at: ${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}')
              ]).p4(),
            ).cornerRadius(8).p2(),
          ],

          // Quality
          if (video.quality.isNotEmptyAndNotNull) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                '${HelperMisc.formatVideoQuality(video.quality ?? '').maxWords(1)}'.text.orange500.bold.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.filesize?.toFileSizeFormat() != null ? '${video.filesize?.toFileSizeFormat()}' : '').positioned(bottom: 24, left: 4),
          ],

          // View count
          if (showViewCount) ...[
            Container(
              color: AppColor.black120,
              child: HStack([
                Icon(UIconsPro.solidRounded.eye, size: 10).pOnly(right: 5, top: 2),
                '${video.viewCount ?? 0}'.text.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.viewCount != null ? 'View: ${video.viewCount}' : '').positioned(bottom: 24, right: 4),
          ],

           // Video title
          Container(
            color: AppColor.black180,
            height: 20,
            width: width,
            child: '${video.videoCode == '' ? video.title?.maxChars(10) : video.videoCode}'.text.align(TextAlign.center).bold.ellipsis.makeCentered(),
          ).positioned(bottom: 0, left: 0, right: 0),
        ]),
      ).cornerRadius(8).pOnly(right: 8),
    );
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
