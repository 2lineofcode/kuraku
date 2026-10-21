import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_translations.dart';
import '../../../core/const.dart';
import '../../../data/models/library_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_screenshot_source.dart';
import '../../widgets/widgets.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_library.dart';
import '../home_panel/home_panel_video_info.dart';
import '../local_video_selection_item.dart';
import '../page_explore/page_explore_controller.dart';
import 'page_home_controller.dart';

class PageHomeView extends GetView<PageHomeController> {
  const PageHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return Obx(
      () => controller.totalVideo.value != 0 || controller.listImageAlbums.isNotEmpty
          ? Column(children: [
              Align(alignment: Alignment.centerRight, child: LocalVideoSelectionClear(controller: controller)),
              Expanded(child: buildPage()),
            ])
          : LibraryEmptyState(onAdd: () => HomePanelLibrary.showDialogAddorEditLibrary()),
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
                () => _buildMediaSection(
                  title: 'New Release'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedFire, size: AppStyle.iconSize, color: Colors.amber),
                  height: 170,
                  list: controller.listNewRelease,
                  prefKey: AppPref.homeSecNewRelease,
                  refreshAction: controller.getListNewRelease,
                  layoutBuilder: (video) => buildLayoutFanArt(video, items: controller.listNewRelease),
                  emptyLayoutBuilder: buildLayoutEmptyFanArt,
                  index: index,
                ),
              );
            case AppPref.homeSecRecommendation:
              return Obx(
                key: ValueKey(AppPref.homeSecRecommendation),
                () => _buildMediaSection(
                  title: 'Recommended for You'.tr,
                  // subtitle: controller.recommendationSubtitle.value,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedSparkles, size: AppStyle.iconSize, color: Vx.amber300),
                  list: controller.listRecommendation,
                  prefKey: AppPref.homeSecRecommendation,
                  refreshAction: controller.getListRecommendation,
                  layoutBuilder: (video) => buildLayoutPoster(video, items: controller.listRecommendation),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  showDirectToExplore: false,
                  index: index,
                ),
              );
            case AppPref.homeSecRandom:
              return Obx(
                key: ValueKey(AppPref.homeSecRandom),
                () => _buildMediaSection(
                  title: 'Random Video'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedShuffle, size: AppStyle.iconSize, color: Vx.blue300),
                  list: controller.listRandom,
                  prefKey: AppPref.homeSecRandom,
                  refreshAction: controller.getListRandom,
                  layoutBuilder: (video) => buildLayoutPoster(video, items: controller.listRandom),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  showDirectToExplore: false,
                  index: index,
                ),
              );
            case AppPref.homeSecMostWatch:
              return Obx(
                key: ValueKey(AppPref.homeSecMostWatch),
                () => _buildMediaSection(
                  title: 'Most Watch'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedRanking, size: AppStyle.iconSize, color: Vx.pink300),
                  list: controller.listTop10Watch,
                  prefKey: AppPref.homeSecMostWatch,
                  refreshAction: controller.getListMostWatch,
                  layoutBuilder: (video) => buildLayoutPoster(video, items: controller.listTop10Watch),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecFavorite:
              return Obx(
                key: ValueKey(AppPref.homeSecFavorite),
                () => _buildMediaSection(
                  title: 'Favorite'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: AppStyle.iconSize, color: Vx.red400),
                  list: controller.listFavorite,
                  prefKey: AppPref.homeSecFavorite,
                  refreshAction: controller.getListFavorite,
                  layoutBuilder: (video) => buildLayoutPoster(video, items: controller.listFavorite),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecNewAdd:
              return Obx(
                key: ValueKey(AppPref.homeSecNewAdd),
                () => _buildMediaSection(
                  title: 'New Added'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedFileAdd, size: AppStyle.iconSize, color: Vx.cyan400),
                  list: controller.listNewAdded,
                  prefKey: AppPref.homeSecNewAdd,
                  refreshAction: controller.getListNewAdded,
                  layoutBuilder: (video) => buildLayoutPoster(video, items: controller.listNewAdded),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecNeverWatch:
              return Obx(
                key: ValueKey(AppPref.homeSecNeverWatch),
                () => _buildMediaSection(
                  title: 'Never Watch'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedPlaySquare, size: AppStyle.iconSize, color: AppColor.success),
                  list: controller.listNeverWatch,
                  prefKey: AppPref.homeSecNeverWatch,
                  refreshAction: controller.getListNeverWatch,
                  layoutBuilder: (video) => buildLayoutPoster(video, items: controller.listNeverWatch),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  index: index,
                ),
              );
            case AppPref.homeSecOldest:
              return Obx(
                key: ValueKey(AppPref.homeSecOldest),
                () => _buildMediaSection(
                  title: 'Oldest'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedHistory, size: AppStyle.iconSize, color: Vx.lime300),
                  list: controller.listOldest,
                  prefKey: AppPref.homeSecOldest,
                  refreshAction: controller.getListOldest,
                  layoutBuilder: (video) => buildLayoutPoster(video, items: controller.listOldest),
                  emptyLayoutBuilder: buildLayoutEmptyPoster,
                  showDirectToExplore: false,
                  index: index,
                ),
              );
            case AppPref.homeSecImageAlbums:
              return Obx(
                key: const ValueKey(AppPref.homeSecImageAlbums),
                () => _buildMediaSection<Library>(
                  title: 'Image Albums'.tr,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: AppStyle.iconSize),
                  list: controller.listImageAlbums,
                  prefKey: AppPref.homeSecImageAlbums,
                  refreshAction: controller.getImageAlbums,
                  layoutBuilder: buildLayoutAlbum,
                  emptyLayoutBuilder: () => const SizedBox.shrink(),
                  showDirectToExplore: false,
                  height: 170,
                  index: index,
                ),
              );
            default:
              return SizedBox.shrink(key: ValueKey(sectionKey));
          }
        },
      ),
    );
  }

  Widget _buildMediaSection<T>({
    Key? key,
    required int index,
    required String title,
    String? subtitle,
    required Widget icon,
    required RxList<T> list,
    required String prefKey,
    required VoidCallback refreshAction,
    required Widget Function(T item) layoutBuilder,
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
              if (subtitle != null && subtitle.isNotEmpty) subtitle.text.size(9).color(AppColor.muted).maxLines(1).ellipsis.make().pOnly(left: 8),
            ]).pSymmetric(h: 12, v: 4).onInkTap(() {
              controller.toggleSection(prefKey);
            }),
          ),
          Spacer(),

          AppIconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
            onPressed: refreshAction,
          ).pOnly(right: 4),

          if (showDirectToExplore == true) ...[
            AppIconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedBookOpen02, size: AppStyle.iconSize),
              onPressed: () async {
                await Get.find<HomeController>().onMenuChange(kMenuExplore);
                final exploreC = Get.find<PageExploreController>();
                await exploreC.openSelection(kCustom, title);
              },
            ).pOnly(right: 4),
          ],

          GetBuilder(
            init: controller,
            builder: (controller) {
              return AppIconButton(
                icon: HugeIcon(
                  icon: AppPref.getBool(prefKey) ?  HugeIcons.strokeRoundedView : HugeIcons.strokeRoundedViewOff,
                  size: AppStyle.iconSize,
                ),
                onPressed: () async {
                  await controller.toggleSection(prefKey);
                },
              );
            },
          ).pOnly(right: 8),

        ]).pSymmetric(v: 12),
        GetBuilder(
          init: controller,
          builder: (controller) {
            if (!AppPref.getBool(prefKey)) return const SizedBox.shrink();
            return Obx(
              () => list.isEmpty
                  ? emptyLayoutBuilder()
                  : ScreenshotSource.list(
                      items: list,
                      itemExtent: prefKey == AppPref.homeSecNewRelease ? 268 : prefKey == AppPref.homeSecImageAlbums ? 228 : 143,
                      key: PageStorageKey('home-videos-$prefKey'),
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final video = list[index];
                        return layoutBuilder(video);
                      },
                    ).wh(width ?? double.infinity, height ?? 210),
            );
          },
        ),
      ],
    ).hide(isVisible: list.isNotEmpty || !AppPref.getBool(prefKey), key: key);
  }


  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget buildLayoutAlbum(Library album) {
    final cover = File(controller.imageAlbumCovers[album.rootFolder] ?? album.images!.first);
    final available = Directory(album.rootFolder ?? '').existsSync();
    Widget placeholder() => Center(child: HugeIcon(icon: HugeIcons.strokeRoundedImage01,
      size: AppStyle.emptyIconSize, color: AppColor.muted));
    return SizedBox(width: 220, child: Material(
      color: AppColor.container, borderRadius: BorderRadius.circular(8), clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => HomePanelLibrary.openImageAlbum(album),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: double.infinity, height: 120,
            child: cover.existsSync() ? Image(image: ResizeImage(FileImage(cover), width: 440, height: 880,
              policy: ResizeImagePolicy.fit), fit: BoxFit.fitWidth, alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) => placeholder()) : placeholder()),
          Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(album.alias?.trim().isNotEmpty == true ? album.alias! : (album.rootFolder ?? '').getLastPath(),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(available ? 'Images: @{count}'.trNamed({'count': '${album.images!.length}'}) : 'Unavailable'.tr,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColor.muted)),
            ])),
        ]),
    ))).pOnly(right: 8);
  }

  Widget buildLayoutFanArt(Videos video, {List<Videos>? items}) {
    final double width = 260;
    return LocalVideoSelectionItem(
      controller: controller, video: video,
      onSingleTap: () => HomePanelVideoInfo.open(video, items: items),
      onDoubleTap: () => HelperOpener.openVideoFile(video),
      child: Container(
        color: AppColor.container,
        child: MediaStack([
          ExThumbnail(
            imageUrl: video.fanArt,
            screenshotItems: items,
            videoPath: video.videoPath,
            contextMenuIsAllowed: (_) => controller.selectedVideos.isEmpty,
            width: width,
            height: 170,
            fitUrl: BoxFit.cover,
            fitMemory: BoxFit.fitWidth,
          ),

          // Release date
          Container(
            color: AppColor.black180,
            child: HStack([
              HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, size: AppStyle.smallIconSize).pOnly(right: 5),
              video.releaseDate.isNotEmptyAndNotNull
                  ? '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Release date: @{kMdY}'.trNamed({'kMdY': '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'}))
                  : '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Added at: @{kMdY}'.trNamed({'kMdY': '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'}))
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
    List<Videos>? items,
    double width = 135,
    double height = 210,
    showReleaseDate = true,
    showViewCount = true,
    showQuality = true,
  }) {
    return LocalVideoSelectionItem(
      controller: controller, video: video,
      onSingleTap: () async => await HomePanelVideoInfo.open(video, items: items),
      onDoubleTap: () async => await HelperOpener.openVideoFile(video),
      child: Container(
        color: AppColor.container,
        child: MediaStack([
          ExThumbnail(
            imageUrl: video.fanArt,
            screenshotItems: items,
            videoPath: video.videoPath,
            contextMenuIsAllowed: (_) => controller.selectedVideos.isEmpty,
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
                const HugeIcon(icon: HugeIcons.strokeRoundedClosedCaption, size: AppStyle.smallIconSize).tooltip('ID Sub'.tr)
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

           // sub en?
          if (video.videoPath?.isHasEnSub() == true) ...[
            Container(
              color: Vx.purple600.withAlpha(200),
              child: HStack([
                const HugeIcon(icon: HugeIcons.strokeRoundedClosedCaption, size: AppStyle.smallIconSize).tooltip('EN Sub'.tr),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // reduce mosaic?
          if (video.videoPath?.isHasUncensored() == true) ...[
            Container(
              color: Vx.red600.withAlpha(200),
              child: HStack([
                const HugeIcon(icon: HugeIcons.strokeRoundedFilm01, size: AppStyle.smallIconSize).tooltip('Reduce Mosaic'.tr),
              ]).p4(),
            ).cornerRadius(8).p2().positioned(right: 0, top: 0),
          ],

          // Release date
          if (showReleaseDate) ...[
            Container(
              color: AppColor.black180,
              child: HStack([
                HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, size: AppStyle.smallIconSize).pOnly(right: 5),
                video.releaseDate.isNotEmptyAndNotNull
                    ? '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Release date: @{kMdY}'.trNamed({'kMdY': '${video.releaseDate?.reformatDate(from: kYMd, to: kMdY)}'}))
                    : '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'.text.size(10).minFontSize(10).make().tooltip('Added at: @{kMdY}'.trNamed({'kMdY': '${video.updatedAt?.reformatDate(from: kYMd, to: kMdY)}'}))
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
                HugeIcon(icon: HugeIcons.strokeRoundedView, size: AppStyle.smallIconSize).pOnly(right: 5, top: 2),
                '${video.viewCount ?? 0}'.text.size(10).minFontSize(10).make(),
              ]).pSymmetric(h: 4, v: 2),
            ).cornerRadius(4).tooltip(video.viewCount != null ? 'View: @{count}'.trNamed({'count': '${video.viewCount}'}) : '').positioned(bottom: 24, right: 4),
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
