import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_color.dart';
import '../../../core/app_shortcut.dart';
import '../../../core/app_translations.dart';
import '../../../data/models/activity_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_media_stack.dart';
import '../../widgets/widget_screenshot_source.dart';
import '../../widgets/widget_style.dart';
import '../../widgets/widget_thumbnail.dart';
import '../../widgets/widget_title_translation.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_video_info.dart';
import '../page_explore/page_explore_controller.dart';
import 'page_deleted_items_view.dart';
import 'page_tools_controller.dart';

class PageToolsView extends GetView<PageToolsController> {
  const PageToolsView({super.key});
  @override
  Widget build(BuildContext context) {
    AppColor.dependOn(context);
    return VStack(
      [
        // header
        _buildMenu().h(30).pOnly(bottom: 16),

        buildResolutionScan(),

        // content
        Obx(() {
          switch (controller.currentMenuSelected.value) {
            case kTopLargeFile: return uiTopLargeFileSize().expand();
            case kDuplicate: return uiDuplicateVideo().expand();
            case kDeletedItems: return const PageDeletedItemsView().expand();
            case kTodo: return uiTODO().expand();
            case kAdvanceSearch: return uiAdvanceSearch(context).expand();
            default: return Container();
          }
        })
      ],
    );
  }

  Widget _buildMenu() {
    return Obx(() => ListView.builder(
      itemCount: controller.menus.length,
      scrollDirection: Axis.horizontal,
      itemBuilder: (context, index) {
        final item = controller.menus[index];
        return Obx(
          () => AppButton(variant: AppButtonVariant.outlined,
            label: item.tr,
            labelSize: 12,
            labelColor: controller.currentMenuSelected.value == item ? AppColor.text : AppColor.muted,
            borderColor: controller.currentMenuSelected.value == item ? AppColor.selected : AppColor.container,
            backgroundColor: controller.currentMenuSelected.value == item ? AppColor.selected : AppColor.container,
            onPressed: () => controller.onMenuChange(item),
          ).pOnly(right: 8),
        );
      },
    ));
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ ~ content
  // ────────────────────────────────────────────────────────────────
  Widget buildResolutionScan() => Obx(() {
    final running = controller.qualityScanRunning.value;
    final missing = controller.missingQualityCount.value;
    final status = controller.qualityScanStatus.value;
    final failed = controller.qualityScanFailed.value;
    final stopping = controller.qualityScanStopping.value;
    if (!running && missing == 0 && !failed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        if (running) ...[
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(
            strokeWidth: 1.5,
            value: controller.qualityScanTotal.value == 0 ? null : controller.qualityScanChecked.value / controller.qualityScanTotal.value,
            semanticsLabel: 'Resolution scan progress'.tr,
          )),
          const SizedBox(width: 8),
          Expanded(child: Tooltip(
            message: '@{qualityScanFile}\n@{qualityScanUpdated} updated · @{qualityScanSkipped} skipped'.trNamed({'qualityScanFile': '${controller.qualityScanFile.value}', 'qualityScanUpdated': '${controller.qualityScanUpdated.value}', 'qualityScanSkipped': '${controller.qualityScanSkipped.value}'}),
            child: Text('Scanning @{qualityScanChecked}/@{qualityScanTotal}'.trNamed({'qualityScanChecked': '${controller.qualityScanChecked.value}', 'qualityScanTotal': '${controller.qualityScanTotal.value}'}), style: const TextStyle(fontSize: 11)),
          )),
        ],
        if (!running && (failed || controller.qualityScanSkipped.value > 0))
          Tooltip(message: status, child: const Padding(
            padding: EdgeInsets.only(right: 4),
            child: HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: AppStyle.iconSize),
          )),
        Tooltip(
          message: running ? 'Keep completed results'.tr : 'Scan missing video resolutions'.tr,
          child: AppButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: stopping && running ? null : running ? controller.stopQualityScan : controller.scanAndUpdateDBVideoRes,
            child: Text(running ? stopping ? 'Stopping…'.tr : 'Stop'.tr : 'Scan (@{missing})'.trNamed({'missing': '$missing'}), style: const TextStyle(fontSize: 11)),
          ),
        ),
      ]),
    );
  });

  Widget uiTopLargeFileSize() => Obx(() {
    final items = controller.topLargeFileSizeList;
    final loading = controller.topLargeLoading.value;
    final error = controller.topLargeError.value;
    final totalSize = items.fold<num>(0, (total, item) => total + (item.filesize ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Top @{length} Large File'.trNamed({'length': '${items.length}'}), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Largest first · up to 200 files'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppDropdown<String>(
            value: controller.topLargeFilterMode.value,
            prefix: const HugeIcon(icon: HugeIcons.strokeRoundedFilter, size: AppStyle.iconSize),
            items: [
              DropdownMenuItem(value: 'all', child: Text('All'.tr)),
              DropdownMenuItem(value: 'internal', child: Text('Internal'.tr)),
              DropdownMenuItem(value: 'external', child: Text('External'.tr)),
            ],
            onChanged: (value) {
              if (value == null) return;
              controller.getTopLargeFileSize(mode: value);
            },
          ),
          const SizedBox(width: 4),
          AppIconButton(
            tooltip: 'Refresh'.tr,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
            onPressed: loading ? null : () => controller.getTopLargeFileSize(mode: controller.topLargeFilterMode.value),
          ),
        ]),
      ]),
      const SizedBox(height: 12),
      Expanded(child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppColor.panel, border: Border.all(color: AppColor.border, width: .5), borderRadius: BorderRadius.circular(AppStyle.radius)),
        child: Column(children: [
          Container(
            color: AppColor.container,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(child: Text('File'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted))),
              Text('Listed size: @{size}'.trNamed({'size': totalSize.toFileSizeFormat()}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
            ]),
          ),
          Expanded(child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : error.isNotEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error.tr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  AppButton(label: 'Retry'.tr, onPressed: () => controller.getTopLargeFileSize(mode: controller.topLargeFilterMode.value)),
                ]).p12())
              : items.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedFilm01, size: AppStyle.emptyIconSize, color: AppColor.muted),
                    const SizedBox(height: 12),
                    Text('No files with a recorded size in this location.'.tr, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColor.muted)),
                  ]).p12())
                : ScreenshotSource.separated(
                    items: controller.topLargeFileSizeList,
                    separatorBuilder: (_, _) => Divider(height: 1, thickness: .5, color: AppColor.border),
                    itemBuilder: (_, index) => _largeFileRow(items[index], index),
                  ),
          ),
        ]),
      )),
    ]).pOnly(left: 8);
  });

  Widget _largeFileRow(Videos item, int index) {
    final path = item.videoPath ?? '';
    final code = (item.videoCode ?? '').trim();
    final filename = path.isEmpty ? 'NON-JAV' : p.basename(path);
    final quality = (item.quality ?? '').trim();
    return ExVideoContextMenu(videoPath: path, videoCode: item.videoCode,
      screenshotItems: controller.topLargeFileSizeList,
      contextMenuIsAllowed: (_) => path.isNotEmpty,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          hoverColor: AppColor.hover,
          onTap: () => HomePanelVideoInfo.open(item, items: controller.topLargeFileSizeList),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              SizedBox(width: 24, child: Text('${index + 1}', style: TextStyle(fontSize: 11, color: AppColor.muted))),
              IgnorePointer(child: SizedBox(width: 48, height: 60, child: _buildMediaThumbnail(poster: item.poster ?? '', videoPath: path, width: 48, height: 60))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Tooltip(message: code.isEmpty ? filename : code, child: Text(code.isEmpty ? filename : code, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                if (code.isNotEmpty) Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColor.muted)),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  Tooltip(message: quality, child: Text(quality.isEmpty ? 'Unknown resolution'.tr : HelperMisc.formatVideoQuality(quality), style: TextStyle(fontSize: 10, color: AppColor.muted))),
                  Text(HelperMisc.isExternalDrive(path) ? 'External drive'.tr : 'Local drive'.tr, style: TextStyle(fontSize: 10, color: AppColor.muted)),
                ]),
                const SizedBox(height: 4),
                Tooltip(message: path, child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColor.muted))),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text((item.filesize ?? 0).toFileSizeFormat(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                AppIconButton(
                  tooltip: 'Open File Path'.tr,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: AppStyle.iconSize, color: AppColor.muted),
                  onPressed: path.isEmpty ? null : () => HelperOpener.openFilePath(path),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget uiDuplicateVideo() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final mode in controller.duplicateModes) Obx(() => AppButton(variant: AppButtonVariant.outlined,
        label: mode == 'exact' ? 'Same Video'.tr : 'Probable'.tr,
        labelSize: 11,
        labelColor: controller.duplicateMode.value == mode ? AppColor.text : AppColor.muted,
        borderColor: controller.duplicateMode.value == mode ? AppColor.selected : AppColor.container,
        backgroundColor: controller.duplicateMode.value == mode ? AppColor.selected : AppColor.container,
        onPressed: () => controller.setDuplicateMode(mode),
      )),
      Obx(() => AppIconButton(
        tooltip: 'Refresh'.tr,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
        onPressed: controller.duplicateLoading.value ? null : controller.getDuplicateVideos,
      )),
      Obx(() => Text('@{groups} groups · @{videos} videos'.trNamed({'groups': '${controller.duplicateGroups.length}', 'videos': '${controller.duplicateVideoCount}'}), style: TextStyle(fontSize: 11, color: AppColor.muted))),
    ]),
    const SizedBox(height: 8),
    Obx(() => Text(controller.duplicateMode.value == 'exact'
      ? 'Same code, or matching names and file sizes. File contents are not verified.'.tr
      : 'Matching names or titles with similar duration or size. Review each candidate.'.tr,
      style: TextStyle(fontSize: 11, color: AppColor.muted),
    )),
    const SizedBox(height: 12),
    AppTextField(
      controller: controller.tecDuplicateSearch,
      placeholder: 'Search code, title, path or resolution...'.tr,
      style: TextStyle(color: AppColor.text),
      prefix: Padding(padding: const EdgeInsets.only(left: 8), child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize, color: AppColor.muted)),
      clearButtonMode: OverlayVisibilityMode.editing,
      onChanged: (value) => controller.duplicateQuery.value = value,
    ),
    const SizedBox(height: 12),
    Expanded(child: Obx(() {
      if (controller.duplicateLoading.value) return const Center(child: CupertinoActivityIndicator());
      if (controller.duplicateError.value.isNotEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(controller.duplicateError.value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        AppButton(onPressed: controller.getDuplicateVideos, child: Text('Retry'.tr)),
      ]));
      final groups = controller.filteredDuplicateGroups;
      if (groups.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        HugeIcon(icon: HugeIcons.strokeRoundedFilm01, size: AppStyle.emptyIconSize, color: AppColor.muted),
        const SizedBox(height: 12),
        Text(controller.duplicateGroups.isEmpty ? 'No duplicate candidates found'.tr : 'No matching groups'.tr, style: TextStyle(fontSize: 12, color: AppColor.muted)),
      ]));
      return ListView.separated(
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => _duplicateGroup(groups[index]),
      );
    })),
  ]).pOnly(left: 8);

  Widget _duplicateGroup(List<Videos> videos) {
    final first = videos.first;
    final code = (first.videoCode ?? '').trim();
    final title = code.isNotEmpty ? code : (first.title ?? '').trim().isNotEmpty ? first.title! : p.basename(first.videoPath ?? '');
    final reason = code.isNotEmpty ? 'Same video code'.tr : controller.duplicateMode.value == 'exact' ? 'Matching names and file sizes'.tr : 'Similar names and duration or size'.tr;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColor.text.withValues(alpha: .025), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Text('@{count} files'.trNamed({'count': '${videos.length}'}), style: TextStyle(fontSize: 11, color: AppColor.muted)),
        ]),
        const SizedBox(height: 4),
        Text(reason, style: TextStyle(fontSize: 10, color: AppColor.muted)),
        ScreenshotSource.column(items: videos, itemBuilder: (_, index) => Column(children: [
          Divider(height: 20, thickness: .5, color: AppColor.border),
          _duplicateFile(videos[index], videos),
        ])),
      ]),
    );
  }

  Widget _duplicateFile(Videos video, List<Videos> videos) {
    final path = video.videoPath ?? '';
    final available = controller.duplicateFileAvailable[path] == true;
    final poster = (video.poster ?? '').isNotEmpty ? video.poster! : video.fanArt ?? '';
    return ExVideoContextMenu(videoPath: path, videoCode: video.videoCode,
      screenshotItems: videos,
      child: Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => HelperOpener.openVideoInfo(video, items: videos),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IgnorePointer(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 56, height: 72,
            child: poster.isEmpty ? HugeIcon(icon: HugeIcons.strokeRoundedFilm01, size: AppStyle.largeIconSize, color: AppColor.muted) : ExThumbnail(imageUrl: poster, width: 56, height: 72, prefix: 1.9),
          ))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.basename(path), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 4, children: [
              Text((video.quality ?? '').isEmpty ? 'Unknown resolution'.tr : HelperMisc.formatVideoQuality(video.quality!), style: TextStyle(fontSize: 11, color: AppColor.muted)),
              Text((video.filesize ?? 0) > 0 ? video.filesize!.toFileSizeFormat() : 'Unknown size'.tr, style: TextStyle(fontSize: 11, color: AppColor.muted)),
              if ((video.duration ?? 0) > 0) Text(HelperMisc.durationFormatDB(video.duration!), style: TextStyle(fontSize: 11, color: AppColor.muted)),
            ]),
            const SizedBox(height: 6),
            Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColor.muted)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              Text(HelperMisc.isExternalDrive(path) ? 'External drive'.tr : 'Local drive'.tr, style: TextStyle(fontSize: 10, color: AppColor.muted)),
              Text(available ? 'Available'.tr : 'Unavailable'.tr, style: TextStyle(fontSize: 10, color: available ? AppColor.muted : Colors.orange)),
            ]),
          ])),
          const SizedBox(width: 4),
          Column(mainAxisSize: MainAxisSize.min, children: [
            AppIconButton(tooltip: 'Open Info'.tr, icon: const HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: AppStyle.iconSize),
              style: IconButton.styleFrom(minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () => HomePanelVideoInfo.open(video, items: videos),
            ),
            AppIconButton(tooltip: 'Open File Path'.tr, icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: AppStyle.iconSize),
              style: IconButton.styleFrom(minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: available ? () => HelperOpener.openFilePath(path) : null,
            ),
            if (Get.isRegistered<HomeController>()) Obx(() {
              final home = Get.find<HomeController>();
              final added = home.isInCart(video);
              return AppIconButton(tooltip: added ? 'Already in panel cart'.tr : 'Add to Panel Cart'.tr,
                icon: HugeIcon(icon: added ? HugeIcons.strokeRoundedTick02 : HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
                style: IconButton.styleFrom(minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: added ? null : () => home.addToCart(video),
              );
            }),
          ]),
        ]),
      )),
    );
  }

  Widget uiTODO() => Obx(() {
    final pending = <Activity>[];
    final downloaded = <Activity>[];
    for (final item in controller.todoList) {
      ((item.content ?? '').startsWith('✔︎') ? downloaded : pending).add(item);
    }
    return Column(children: [
      Row(children: [
        Expanded(child: Text('Total Todo: @{length}'.trNamed({'length': '${controller.todoList.length}'}), style: TextStyle(fontSize: 12, color: AppColor.muted))),
        AppIconButton(
          tooltip: 'Refresh'.tr,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh01, size: AppStyle.iconSize),
          onPressed: controller.getTodos,
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: AppShortcut.label('Add Todo: [⌘ + T]'.tr),
          child: AppButton(
            label: 'Add New Todo'.tr,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: AppStyle.iconSize),
            onPressed: controller.addTodo,
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final todo = _todoColumn('TODO', pending, HugeIcons.strokeRoundedCircle, AppColor.muted, 'No pending todos'.tr);
        final done = _todoColumn('DOWNLOADED', downloaded, HugeIcons.strokeRoundedCheckmarkCircle02, AppColor.accentForeground, 'No downloaded todos yet'.tr);
        if (constraints.maxWidth < 560) return Column(children: [Expanded(child: todo), const SizedBox(height: 12), Expanded(child: done)]);
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: todo), const SizedBox(width: 12), Expanded(child: done)]);
      })),
    ]).pOnly(left: 8);
  });

  Widget _todoColumn(String title, List<Activity> items, List<List<dynamic>> icon, Color color, String emptyMessage) => Container(
    key: ValueKey(title),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColor.text.withValues(alpha: .025), borderRadius: BorderRadius.circular(6)),
    child: Column(children: [
      Row(children: [
        HugeIcon(icon: icon, size: AppStyle.iconSize, color: color),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('${items.length}', style: TextStyle(fontSize: 11, color: AppColor.muted)),
      ]),
      const SizedBox(height: 12),
      Expanded(child: items.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            HugeIcon(icon: icon, size: AppStyle.largeIconSize, color: AppColor.muted.withValues(alpha: .5)),
            const SizedBox(height: 10),
            Text(emptyMessage, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColor.muted)),
          ]))
        : ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) => _todoCard(items[index]),
          ),
      ),
    ]),
  );

  Widget _todoCard(Activity item) {
    final text = (item.content ?? '').replaceAll('✔︎', '').trim();
    final isVideo = text.isValidVideoCode();
    return Material(
      color: AppColor.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: AppColor.border, width: .5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isVideo ? () => HelperOpener.openVideoInfo({'video_code': text}) : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            SizedBox(width: 64, height: 80, child: _buildTodoThumbnail(text)),
            const SizedBox(width: 10),
            Expanded(child: Tooltip(message: text, child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: isVideo ? FontWeight.w600 : FontWeight.normal)))),
            AppIconButton(
              tooltip: 'Delete'.tr,
              style: IconButton.styleFrom(minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
              icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: AppStyle.iconSize, color: AppColor.muted),
              onPressed: () => controller.deleteTodos(item),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTodoThumbnail(String? todoContent) {
    final code = (todoContent ?? '').replaceAll('✔︎', '').trim();
    if (!code.isValidVideoCode()) {
      return HugeIcon(icon: HugeIcons.strokeRoundedFile01, size: AppStyle.largeIconSize, color: AppColor.muted).centered();
    }

    final poster = controller.todoPosterByCode[code] ?? '';
    if (poster.isEmpty) {
      return HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: AppStyle.largeIconSize, color: Vx.neutral500).centered();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ExThumbnail(imageUrl: poster, width: 64, height: 80, prefix: 1.9),
    );
  }

  Widget _buildMediaThumbnail({String poster = '', String videoPath = '', bool preferVideoPath = false, double width = 80, double height = 100}) {
    final hasPoster = poster.trim().isNotEmpty;
    final hasVideoPath = videoPath.trim().isNotEmpty;
    final useVideoPath = hasVideoPath && (preferVideoPath || !hasPoster);

    if (!hasPoster && !hasVideoPath) {
      return HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: AppStyle.largeIconSize, color: Vx.neutral500).centered();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ExThumbnail(
        imageUrl: useVideoPath ? '' : poster,
        videoPath: useVideoPath ? videoPath : '',
        width: width,
        height: height,
        prefix: 1.9,
      ),
    ).centered();
  }

  Widget uiAdvanceSearch(BuildContext context) {
    return HStack([
      _buildLeftPart(context).pOnly(right: 12),
      _buildRightPart().expand(),
    ]).pOnly(left: 8);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ REUSABLE WIDGETS
  // ────────────────────────────────────────────────────────────────

  Widget _buildLeftPart(BuildContext context) {
    final rowHeight = 84 * MediaQuery.textScalerOf(context).scale(12) / 12;
    return Container(
      width: 220,
      height: Get.height,
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: VStack(
        [

          // filter by
          HStack([
            'Browse'.tr.text.size(12).bold.make().expand(),
            Obx(() => AppDropdown<String>(
              value: controller.currentFilterBy.value,
              onChanged: (kind) {
                switch (kind) {
                  case kActress: controller.filterByActress(); break;
                  case kSeries: controller.filterBySeries(); break;
                  case kCategory: controller.filterByCategories(); break;
                  case kYear: controller.filterByYear(); break;
                }
              },
              items: [for (final kind in [kActress, kSeries, kCategory, kYear])
                DropdownMenuItem(value: kind, child: Text(kind.tr)),
              ],
            )).tooltip('Browse catalog by'.tr),
          ]),

          // search
          AppTextField(
            controller: controller.tecFilterSearchLeft,
            focusNode: controller.fnFilterSearchLeft,
            placeholder: 'Search @{toLowerCase}...'.trNamed({'toLowerCase': '${controller.currentFilterBy.value.tr.toLowerCase()}'}),
            style: TextStyle(color: AppColor.text),
            clearButtonMode: OverlayVisibilityMode.editing,
            prefix: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize, color: Vx.neutral500).pOnly(left: 8),
            onChanged: controller.searchAdvancedGroups,
            onSubmitted: (s) async => await controller.onLeftListDoSearch(s),
          ).pSymmetric(v: 12),
          '@{length} items · ↑ ↓ to browse'.trNamed({'length': '${controller.leftList.length}'}).text.size(10).color(AppColor.muted).make().pOnly(bottom: 8),

          if (controller.leftListLoading.value) const LinearProgressIndicator(minHeight: 2),
          if (controller.leftListError.value.isNotEmpty) Column(children: [
            Text(controller.leftListError.value, style: const TextStyle(fontSize: 11)),
            AppButton(onPressed: () => controller.onLeftListDoSearch(controller.tecFilterSearchLeft.text), child: Text('Retry'.tr)),
          ]),
          if (!controller.leftListLoading.value && controller.leftListError.value.isEmpty && controller.leftList.isEmpty)
            'No matching items'.tr.text.size(11).color(AppColor.muted).make().p8(),
          // list
          FocusScope(
            autofocus: true,
            child: KeyboardListener(
              focusNode: controller.leftListFocusNode,
              autofocus: true,
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    controller.onLeftListKeyPressedArrowDown();
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    controller.onLeftListKeyPressedArrowUp();
                  }
                }
              },
              child: FlutterListView(
                controller: controller.leftListScrollController.value,
                delegate: FlutterListViewDelegate((context, index) {
                    final item = controller.leftList[index];
                    return SizedBox(
                      height: rowHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Expanded(child: Obx(
                          () {
                            final isSelected = '${item['id']}' == controller.leftListSelectedId.value;
                            final isHovered = index == controller.leftListHoveredIndex.value;
                            return MouseRegion(
                              onEnter: (_) => controller.leftListHoveredIndex.value = index,
                              onExit: (_) => controller.leftListHoveredIndex.value = -1,
                              child: InkWell(
                                onTap: () async => await controller.onLeftListTap(item, index),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Text(HelperDecensor.decensor(item['name_en']), style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if ((item['name_ja'] ?? '').toString().trim().isNotEmpty && item['name_ja'] != item['name_en'])
                                    Text('${item['name_ja']}', style: TextStyle(fontSize: 10, color: AppColor.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text('@{video_count} videos · @{unknown}'.trNamed({'video_count': '${item['video_count']}', 'unknown': '${item['max_release_date'] ?? 'Date unknown'}'}), style: TextStyle(fontSize: 9, color: AppColor.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ]).w(double.infinity).p4(),
                              )
                                  .color(isSelected ? AppColor.selected : isHovered ? AppColor.border : Colors.transparent)
                                  .cornerRadius(8),
                            );
                          },
                        )),
                        Divider(color: AppColor.border, thickness: 0.5, height: 8),
                      ],
                      ),
                    );
                },
                  childCount: controller.leftList.length,
                  onItemKey: (index) => '${controller.currentFilterBy.value}:${controller.leftList[index]['id']}',
                  onItemHeight: (_) => rowHeight,
                  preferItemHeight: rowHeight,
                  disableCacheItems: true,
                ),
              ),
            ),
          ).expand(),
        ],
      ).p12(),
    );
  }

  Widget _buildRightPart() {

    if (controller.leftListSelected.isEmpty) {
      return Container(
        decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
        child: ExUiErrorOrEmpty(
          illustration: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeftDouble, size: AppStyle.emptyIconSize).pOnly(bottom: 12),
          message: 'Choose an actress, series, category or year to browse the R18 catalog.'.tr,
        ),
      );
    }

    return Container(
      decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
      child: controller.obx(
        (state) => Obx(() => VStack(
          [
            // header
            HStack([
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TitleTranslation(
                  key: ValueKey(controller.leftListSelectedId.value),
                  title: controller.leftListSelected.value,
                  child: Text(HelperDecensor.decensor(controller.leftListSelected.value), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text('@{length} of @{length2} videos'.trNamed({'length': '${controller.rightListFiltered.length}', 'length2': '${controller.rightList.length}'}), style: TextStyle(fontSize: 10, color: AppColor.muted)),
              ])),
              if (controller.hasAdvancedFilters) AppButton(
                onPressed: controller.clearAdvancedFilters,
                child: Text('Clear'.tr, style: TextStyle(fontSize: 11)),
              ),

              // 2
              Obx(
                () => ZStack([
                  AppIconButton(
                    tooltip: 'More filters: video code, categories, year and duration'.tr,
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedFilter,
                      size: AppStyle.iconSize,
                    ),
                    onPressed: () => controller.openDialogFilter(),
                  ).pOnly(left: 8),
                  controller.filter.isFiltered.isTrue ? Container(height: 6, width: 6, color: Vx.red500).cornerRadius(90).positioned(right: 8, top: 8) : 0.heightBox,
                ]),
              ),
            ]).pOnly(bottom: 8),
            AppTextField(
              controller: controller.tecResultSearch,
              placeholder: 'Search video code or title...'.tr,
              style: TextStyle(color: AppColor.text),
              clearButtonMode: OverlayVisibilityMode.editing,
              prefix: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: AppStyle.iconSize, color: AppColor.muted).pOnly(left: 8),
              onChanged: (value) {
                controller.resultQuery.value = value;
                controller.applyAdvancedFilters();
              },
            ).pOnly(bottom: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _advancedOption('Release'.tr, controller.releaseFilter.value, {'all': 'All dates'.tr, 'released': 'Released'.tr, 'upcoming': 'Upcoming'.tr}, (value) => controller.releaseFilter.value = value),
              _advancedOption('Library'.tr, controller.libraryFilter.value, {'all': 'All videos'.tr, 'owned': 'In Library'.tr, 'missing': 'Not in Library'.tr}, (value) => controller.libraryFilter.value = value),
              _advancedOption('Sort'.tr, controller.resultSort.value, {'newest': 'Newest released'.tr, 'oldest': 'Oldest'.tr, 'code': 'Video code'.tr}, (value) => controller.resultSort.value = value),
            ]).pOnly(bottom: 12),

            // list video
            Obx(() => controller.rightListFiltered.isEmpty
                ? Center(child: Text('No videos match the current filters'.tr))
                : _buildVideoList()).expand(),

          ],
        ).p12()),
        onLoading: ExUiLoading(message: 'Loading...'.tr.text.size(11).minFontSize(11).makeCentered()),
        onError: (error) => Center(child: Text(error ?? 'Could not load videos'.tr)),
        onEmpty: ExUiErrorOrEmpty(
          illustration: HugeIcon(icon: HugeIcons.strokeRoundedInbox, size: AppStyle.emptyIconSize),
          title: 'No Data Found'.tr,
          message: 'No Result Found, as you searched for "@{leftListSelected}"'.trNamed({'leftListSelected': '${controller.leftListSelected}'}),
        ),
      ),
    );
  }

  Widget _advancedOption(String label, String selected, Map<String, String> options, void Function(String) onSelected) {
    return AppDropdown<String>(
      value: selected,
      items: options.entries.map((item) => DropdownMenuItem(
        value: item.key, child: Text(item.value),
      )).toList(),
      onChanged: (value) {
        if (value == null) return;
        onSelected(value);
        controller.applyAdvancedFilters();
      },
    ).tooltip(label);
  }

  Widget _buildVideoList() {
    return ScreenshotSource.grid(
      items: controller.rightListFiltered,
      key: ValueKey(controller.leftListSelectedId.value),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
      ),
      itemCount: controller.rightListFiltered.length,
      itemBuilder: (context, i) {
        final item = controller.rightListFiltered[i];
        final date = DateTime.tryParse('${item['release_date'] ?? ''}')?.toIso8601String().substring(0, 10) ?? 'Date unknown';
        return LayoutBuilder(builder: (context, constraints) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: MediaStack([
            ExThumbnail(
              screenshotItems: controller.rightListFiltered,
              imageUrl: item['fan_art'] ?? '',
              videoCode: item['video_code'],
              width: constraints.maxWidth,
              height: 200,
              fitUrl: BoxFit.cover,
            ),
            Positioned(bottom: 0, left: 0, right: 0, child: Container(
              color: AppColor.black180,
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item['video_code']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)).onInkTap(() {
                  HelperMisc.copyToClipboard(item['video_code'], showToast: true);
                }).tooltip('Copy video code'.tr),
                if ('${item['title'] ?? ''}'.trim().isNotEmpty)
                  Text(HelperDecensor.decensor(item['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
              ]),
            )),
            Positioned(top: 6, left: 6, child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: (constraints.maxWidth - 48).clamp(0, double.infinity)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(date, style: const TextStyle(fontSize: 10)).p4().color(AppColor.black180).cornerRadius(4),
                if (item['is_released'] == false)
                  Text('Upcoming'.tr, style: TextStyle(fontSize: 10)).p4().color(Colors.brown.shade800).cornerRadius(4).pOnly(top: 4),
                if (item['match'] == true)
                  Text('In Library'.tr, style: TextStyle(fontSize: 10)).p4().color(Colors.green.shade800).cornerRadius(4).pOnly(top: 4),
                if (Get.isRegistered<HomeController>()) GetBuilder<HomeController>(builder: (_) => item['is_clicked'] == true
                    ? Text('Requested'.tr, style: TextStyle(fontSize: 10)).p4().color(Colors.blue.shade800).cornerRadius(4).pOnly(top: 4)
                    : const SizedBox.shrink()),
              ]),
            )),
            Positioned(right: 6, top: 6, child: Column(children: [
              AppIconButton(
                tooltip: 'Open trailer'.tr,
                style: IconButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlay, size: AppStyle.iconSize),
                onPressed: () => HelperOpener.openTrailer(item),
              ),
              const SizedBox(height: 4),
              AppIconButton(
                tooltip: 'Open screenshots'.tr,
                style: IconButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: AppStyle.iconSize),
                onPressed: () => HelperOpener.openScreenshot(item, items: controller.rightListFiltered),
              ),
            ])),
          ]).onInkTap(() async => await HelperOpener.openVideoInfo(item, items: controller.rightListFiltered)),
        ));
      },
    );
  }
}
