import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_pref.dart';
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
              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
                child: HStack([
                  Icon(UIconsPro.solidRounded.flame, size: 12, color: Colors.amber).pOnly(right: 8),
                  'New Release'.text.size(12).make(),
                ]).pSymmetric(h: 12, v: 4).onInkTap(() {
                  AppPref.setHomeSecNewRelease(!AppPref.getHomeSecNewRelease());
                  controller.update();
                }),
              ),
              Spacer(),
              GetBuilder(
                init: controller,
                builder: (controller) {
                  return IconButton(
                    icon: Icon(
                      AppPref.getHomeSecNewRelease() ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                      size: 12,
                    ),
                    onPressed: () async {
                      AppPref.setHomeSecNewRelease(!AppPref.getHomeSecNewRelease());
                      controller.update();
                    },
                  );
                },
              ),
              IconButton(
                  icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
                  onPressed: () async {
                    await Get.find<HomeController>().onMenuChange(kMenuExplore);
                    final exploreC = Get.find<PageExploreController>();
                    await exploreC.onFilterByChange(kCustom);
                    exploreC.tecSearch.text = 'New Release';
                    exploreC.onOListSearch('New Release');
                    await exploreC.onOListTap(exploreC.oListFiltered[0]);
                  }),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListNewRelease(),
              ),
            ]).pOnly(bottom: 8),
            GetBuilder(
              init: controller,
              builder: (controller) {
                return Obx(
                  () => controller.listNewRelease.isEmpty
                      ? buildLayoutEmptyFanArt()
                      : ListView.builder(
                          itemCount: controller.listNewRelease.length,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final video = controller.listNewRelease[index];
                            return buildLayoutFanArt(video);
                          },
                        ).wh(double.infinity, 170).hide(isVisible: AppPref.getHomeSecNewRelease()),
                );
              },
            ),
          ],
        ).hide(isVisible: controller.listNewRelease.isNotEmpty),

        // Random Videos
        VStack(
          [
            HStack([
              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
                child: HStack([
                  Icon(UIconsPro.solidRounded.shuffle, size: 12, color: Vx.blue300).pOnly(right: 8),
                  'Random Video'.text.size(12).make(),
                ]).pSymmetric(h: 12, v: 4).onInkTap(() {
                  AppPref.setHomeSecRandom(!AppPref.getHomeSecRandom());
                  controller.update();
                }),
              ),
              Spacer(),
              GetBuilder(
                init: controller,
                builder: (controller) {
                  return IconButton(
                    icon: Icon(
                      AppPref.getHomeSecRandom() ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                      size: 12,
                    ),
                    onPressed: () async {
                      AppPref.setHomeSecRandom(!AppPref.getHomeSecRandom());
                      controller.update();
                    },
                  );
                },
              ),
              IconButton(
                  icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
                  onPressed: () async {
                    await Get.find<HomeController>().onMenuChange(kMenuExplore);
                    final exploreC = Get.find<PageExploreController>();
                    await exploreC.onFilterByChange(kCustom);
                    exploreC.tecSearch.text = 'Random';
                    exploreC.onOListSearch('Random');
                    await exploreC.onOListTap(exploreC.oListFiltered[0]);
                  }),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListRandom(),
              ),


            ]).pSymmetric(v: 12),
            GetBuilder(
              init: controller,
              builder: (controller) {
                return Obx(
                  () => controller.listRandom.isEmpty
                      ? buildLayoutEmptyPoster()
                      : ListView.builder(
                          itemCount: controller.listRandom.length,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final video = controller.listRandom[index];
                            return buildLayoutPoster(video, showViewCount: false);
                          },
                        ).wh(double.infinity, 200).hide(isVisible: AppPref.getHomeSecRandom()),
                );
              },
            ),
          ],
        ).hide(isVisible: controller.listRandom.isNotEmpty),

        // Most Watch
        VStack(
          [
            HStack([
              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
                child: HStack([
                  Icon(UIconsPro.solidRounded.cursor_finger, size: 12, color: Vx.pink300).pOnly(right: 8),
                  'Most Watch'.text.size(12).make(),
                ]).pSymmetric(h: 12, v: 4).onInkTap(() {
                  AppPref.setHomeSecMostWatch(!AppPref.getHomeSecMostWatch());
                  controller.update();
                }),
              ),
              Spacer(),
              GetBuilder(
                init: controller,
                builder: (controller) {
                  return IconButton(
                    icon: Icon(
                      AppPref.getHomeSecMostWatch() ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                      size: 12,
                    ),
                    onPressed: () async {
                      AppPref.setHomeSecMostWatch(!AppPref.getHomeSecMostWatch());
                      controller.update();
                    },
                  );
                },
              ),
              IconButton(
                  icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
                  onPressed: () async {
                    await Get.find<HomeController>().onMenuChange(kMenuExplore);
                    final exploreC = Get.find<PageExploreController>();
                    await exploreC.onFilterByChange(kCustom);
                    exploreC.tecSearch.text = 'Most Watch';
                    exploreC.onOListSearch('Most Watch');
                    await exploreC.onOListTap(exploreC.oListFiltered[0]);
                  }),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListMostWatch(),
              ),
            ]).pSymmetric(v: 12),
            GetBuilder(
              init: controller,
              builder: (controller) {
                return Obx(
                  () => controller.listTop10Watch.isEmpty
                      ? buildLayoutEmptyPoster()
                      : ListView.builder(
                          itemCount: controller.listTop10Watch.length,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final video = controller.listTop10Watch[index];
                            return buildLayoutPoster(video, showViewCount: true);
                          },
                        ).wh(double.infinity, 200).hide(isVisible: AppPref.getHomeSecMostWatch()),
                );
              },
            ),
          ],
        ).hide(isVisible: controller.listTop10Watch.isNotEmpty),

        // Favorite videos
        VStack(
          [
            HStack([
              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
                child: HStack([
                  Icon(UIconsPro.solidRounded.square_heart, size: 12, color: Vx.red400).pOnly(right: 8),
                  'Favorite videos'.text.size(12).make(),
                ]).pSymmetric(h: 12, v: 4).onInkTap(() {
                  AppPref.setHomeSecFavorite(!AppPref.getHomeSecFavorite());
                  controller.update();
                }),
              ),
              Spacer(),
              GetBuilder(
                init: controller,
                builder: (controller) {
                  return IconButton(
                    icon: Icon(
                      AppPref.getHomeSecFavorite() ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                      size: 12,
                    ),
                    onPressed: () async {
                      AppPref.setHomeSecFavorite(!AppPref.getHomeSecFavorite());
                      controller.update();
                    },
                  );
                },
              ),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
                onPressed: () async {
                  await Get.find<HomeController>().onMenuChange(kMenuExplore);
                  final exploreC = Get.find<PageExploreController>();
                  await exploreC.onFilterByChange(kCustom);
                  exploreC.tecSearch.text = 'Favorite';
                  exploreC.onOListSearch('Favorite');
                  await exploreC.onOListTap(exploreC.oListFiltered[0]);
                }
              ),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListFavorite(),
              ),
            ]).pSymmetric(v: 12),
            GetBuilder(
              init: controller,
              builder: (controller) {
                return Obx(
                  () => controller.listFavorite.isEmpty
                      ? buildLayoutEmptyPoster()
                      : ListView.builder(
                          itemCount: controller.listFavorite.length,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final video = controller.listFavorite[index];
                            return buildLayoutPoster(video, showViewCount: false);
                          },
                        ).wh(double.infinity, 200).hide(isVisible: AppPref.getHomeSecFavorite()),
                );
              },
            ),
          ],
        ).hide(isVisible: controller.listFavorite.isNotEmpty),

        // new added
        VStack(
          [
            HStack([
              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
                child: HStack([
                  Icon(UIconsPro.solidRounded.add_document, size: 12, color: Vx.cyan400).pOnly(right: 8),
                  'Recently Added'.text.size(12).make(),
                ]).pSymmetric(h: 12, v: 4).onInkTap(() {
                  AppPref.setHomeSecNewAdd(!AppPref.getHomeSecNewAdd());
                  controller.update();
                }),
              ),
              Spacer(),
              GetBuilder(
                init: controller,
                builder: (controller) {
                  return IconButton(
                    icon: Icon(
                      AppPref.getHomeSecNewAdd() ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                      size: 12,
                    ),
                    onPressed: () async {
                      AppPref.setHomeSecNewAdd(!AppPref.getHomeSecNewAdd());
                      controller.update();
                    },
                  );
                },
              ),
              IconButton(
                  icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
                  onPressed: () async {
                    await Get.find<HomeController>().onMenuChange(kMenuExplore);
                    final exploreC = Get.find<PageExploreController>();
                    await exploreC.onFilterByChange(kCustom);
                    exploreC.tecSearch.text = 'New Added';
                    exploreC.onOListSearch('New Added');
                    await exploreC.onOListTap(exploreC.oListFiltered[0]);
                  }),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListNewAdded(),
              ),
            ]).pSymmetric(v: 12),
            GetBuilder(
              init: controller,
              builder: (controller) {
                return Obx(
                  () => controller.listNewAdded.isEmpty
                      ? buildLayoutEmptyPoster()
                      : ListView.builder(
                          itemCount: controller.listNewAdded.length,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final video = controller.listNewAdded[index];
                            return buildLayoutPoster(video, showViewCount: false);
                          },
                        ).wh(double.infinity, 200).hide(isVisible: AppPref.getHomeSecNewAdd()),
                );
              },
            ),
          ],
        ).hide(isVisible: controller.listNewAdded.isNotEmpty),

        // never watch
        VStack(
          [
            HStack([
              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
                child: HStack([
                  Icon(UIconsPro.solidRounded.popcorn, size: 12, color: Vx.green400).pOnly(right: 8),
                  'Never Watch'.text.size(12).make(),
                ]).pSymmetric(h: 12, v: 4).onInkTap(() {
                  AppPref.setHomeSecNeverWatch(!AppPref.getHomeSecNeverWatch());
                  controller.update();
                }),
              ),
              Spacer(),
              GetBuilder(
                init: controller,
                builder: (controller) {
                  return IconButton(
                    icon: Icon(
                      AppPref.getHomeSecNeverWatch() ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                      size: 12,
                    ),
                    onPressed: () async {
                      AppPref.setHomeSecNeverWatch(!AppPref.getHomeSecNeverWatch());
                      controller.update();
                    },
                  );
                },
              ),
              IconButton(
                  icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
                  onPressed: () async {
                    await Get.find<HomeController>().onMenuChange(kMenuExplore);
                    final exploreC = Get.find<PageExploreController>();
                    await exploreC.onFilterByChange(kCustom);
                    exploreC.tecSearch.text = 'Never Watch';
                    exploreC.onOListSearch('Never Watch');
                    await exploreC.onOListTap(exploreC.oListFiltered[0]);
                  }),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListNeverWatch(),
              ),
            ]).pSymmetric(v: 12),
            GetBuilder(
              init: controller,
              builder: (controller) {
                return Obx(
                  () => controller.listNeverWatch.isEmpty
                      ? buildLayoutEmptyPoster()
                      : ListView.builder(
                          itemCount: controller.listNeverWatch.length,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final video = controller.listNeverWatch[index];
                            return buildLayoutPoster(video, showViewCount: false);
                          },
                        ).wh(double.infinity, 200).hide(isVisible: AppPref.getHomeSecNeverWatch()),
                );
              },
            ),
          ],
        ).hide(isVisible: controller.listNeverWatch.isNotEmpty),

        // oldest
        VStack(
          [
            HStack([
              Container(
                decoration: ExDecorator.box(borderColor: Colors.transparent, borderRadius: 90, fillColor: AppColor.container),
                child: HStack([
                  Icon(UIconsPro.solidRounded.olive_branch_dove, size: 12, color: Vx.lime300).pOnly(right: 8),
                  'Oldest'.text.size(12).make(),
                ]).pSymmetric(h: 12, v: 4).onInkTap(() {
                  AppPref.setHomeSecOldest(!AppPref.getHomeSecOldest());
                  controller.update();
                }),
              ),
              Spacer(),
              GetBuilder(
                init: controller,
                builder: (controller) {
                  return IconButton(
                    icon: Icon(
                      AppPref.getHomeSecOldest() ? UIconsPro.regularRounded.eye_crossed : UIconsPro.regularRounded.eye,
                      size: 12,
                    ),
                    onPressed: () async {
                      AppPref.setHomeSecOldest(!AppPref.getHomeSecOldest());
                      controller.update();
                    },
                  );
                },
              ),
              IconButton(
                  icon: Icon(UIconsPro.regularRounded.book_alt, size: 12),
                  onPressed: () async {
                    await Get.find<HomeController>().onMenuChange(kMenuExplore);
                    final exploreC = Get.find<PageExploreController>();
                    await exploreC.onFilterByChange(kCustom);
                    exploreC.tecSearch.text = 'Oldest';
                    exploreC.onOListSearch('Oldest');
                    await exploreC.onOListTap(exploreC.oListFiltered[0]);
                  }),
              IconButton(
                icon: Icon(UIconsPro.regularRounded.rotate_right, size: 12),
                onPressed: () => controller.getListOldest(),
              ),
            ]).pSymmetric(v: 12),
            GetBuilder(
              init: controller,
              builder: (controller) {
                return Obx(
                  () => controller.listOldest.isEmpty
                      ? buildLayoutEmptyPoster()
                      : ListView.builder(
                          itemCount: controller.listOldest.length,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final video = controller.listOldest[index];
                            return buildLayoutPoster(video, showViewCount: false);
                          },
                        ).wh(double.infinity, 200).hide(isVisible: AppPref.getHomeSecOldest()),
                );
              },
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
          width: 250,
          height: 170,
          fitUrl: BoxFit.cover,
          fitMemory: BoxFit.fitWidth,
        ),
        Container(
          color: Vx.black.withAlpha(150),
          height: 20,
          width: 250,
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
