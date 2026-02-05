import 'dart:convert';

import 'package:ex_kit/ex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:process_run/process_run.dart' as shell;
import 'package:process_run/stdio.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_notification.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_setting.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/__javit_search_entity.dart';
import '../../../data/models/activity_entity.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';

class PageDownloadController extends GetxController {
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearch = ''.obs;
  final scrollController = ScrollController();

  final response = JavitSearch().obs;
  final hasNextPage = false.obs;
  final currentPage = 0.obs;
  final videos = <JavitSearchResult>[].obs;
  final allVideos = <JavitSearchResult>[].obs;
  final havingVideos = 0.obs;
  final totalResults = 0.obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;

  // downloader
  final downloadStdout = ''.obs;
  final currentProcessDownload = Rx<Process?>(null);
  final retryCount = 0.obs;

  // filters
  final filter = VideoFilterState();

  // app setting
  final appSetting = Get.find<AppSettingService>();
  final _perPage = 200;
  String _lastQuery = '';
  Set<String> _existingVideoCodes = {};
  static const _defaultYearStart = 2000;

  @override
  Future<void> onInit() async {
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();

    phSearch.value = 'Video Code or Title...';
    scrollController.removeListener(_onScroll);
    scrollController.addListener(_onScroll);
    await onReset();

    AppLog.logI('page download ==> onInit called: ${sw.elapsedMilliseconds} ms');
  }

  @override
  void onClose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    tecSearch.dispose();
    fnSearch.dispose();
    super.onClose();
  }

  Future<void> onSearch(String s) async {
    if (s.isEmpty) {
      await onReset();
      return;
    }

    // ** db mode
    else {
      try {
        _lastQuery = s;
        isLoading.value = true;
        HelperLoading.show();

        await _refreshSearchWithFilters();

        if (scrollController.hasClients) {
          await scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
        }
      } catch (e) {
        AppLog.logE('onSearch dbMode e -> $e');
      } finally {
        isLoading.value = false;
        HelperLoading.dismiss();
      }
    }
  }

  Future<void> onReset() async {
    response.value = JavitSearch();
    currentPage.value = 0;
    retryCount.value = 0;
    hasNextPage.value = false;
    videos.value = [];
    allVideos.value = [];
    havingVideos.value = 0;
    totalResults.value = 0;
    tecSearch.text = '';
    fnSearch.requestFocus();
    filter.isFiltered.value = false;
    _lastQuery = '';
    _existingVideoCodes = {};
    isLoading.value = false;
    isLoadingMore.value = false;
  }

  bool get _hasCustomYearRange {
    final startYear = filter.currentRange.value.start.toInt();
    final endYear = filter.currentRange.value.end.toInt();
    final currentYear = DateTime.now().year;
    return startYear > _defaultYearStart || endYear < currentYear;
  }

  String? _filterVideoCode() {
    final value = filter.tecVideoCode.text.trim();
    return value.isEmpty ? null : value;
  }

  String? _filterActressName() {
    final value = filter.tecActressName.text.trim();
    return value.isEmpty ? null : value;
  }

  List<String>? _filterCategories() {
    return filter.categoriesSelected.isEmpty ? null : filter.categoriesSelected.toList();
  }

  int? _filterYearStart() {
    if (_hasCustomYearRange == false) return null;
    return filter.currentRange.value.start.toInt();
  }

  int? _filterYearEnd() {
    if (_hasCustomYearRange == false) return null;
    return filter.currentRange.value.end.toInt();
  }

  Future<void> _refreshSearchWithFilters({bool showLoading = false}) async {
    if (_lastQuery.isEmpty) return;

    if (showLoading) {
      isLoading.value = true;
      HelperLoading.show();
    }

    currentPage.value = 1;
    hasNextPage.value = true;
    allVideos.clear();
    videos.clear();
    havingVideos.value = 0;

    final videoCode = _filterVideoCode();
    final actressName = _filterActressName();
    final categories = _filterCategories();
    final yearStart = _filterYearStart();
    final yearEnd = _filterYearEnd();

    switch (_lastQuery) {
      case '/new':
        totalResults.value = await DBR18.getNewReleaseCount(
          videoCode: videoCode,
          actressName: actressName,
          categories: categories,
          yearStart: yearStart,
          yearEnd: yearEnd,
        );
        break;
      default:
        totalResults.value = await DBR18.getSearchCount(
          _lastQuery,
          videoCode: videoCode,
          actressName: actressName,
          categories: categories,
          yearStart: yearStart,
          yearEnd: yearEnd,
        );
        break;
    }

    await _loadPage(isLoadMore: false);

    if (showLoading) {
      isLoading.value = false;
      HelperLoading.dismiss();
    }
  }

  // ~ Filters ────────────────────────────────────────────────────────────────
  final _filterAdapter = VideoFilterAdapter<JavitSearchResult>(
    videoCode: (video) => video.videoCode ?? '',
    actresses: (video) => video.actresses ?? <String>[],
    categories: (video) => video.categories ?? <String>[],
    releaseDate: (video) => video.releaseDate,
    categoryMatch: (videoCategories, selected) => videoCategories.toSet().containsAll(selected),
  );

  void _syncHavingVideos(List<JavitSearchResult> list) {
    havingVideos.value = 0;
    for (var video in list) {
      if (video.match == true) havingVideos.value++;
    }
  }

  Future<void> _loadPage({required bool isLoadMore}) async {
    if (_lastQuery.isEmpty) return;
    if (isLoadMore && hasNextPage.isFalse) return;
    if (isLoadMore) isLoadingMore.value = true;

    try {
      final videoCode = _filterVideoCode();
      final actressName = _filterActressName();
      final categories = _filterCategories();
      final yearStart = _filterYearStart();
      final yearEnd = _filterYearEnd();

      final List<Map<String, dynamic>> r18videos;
      switch (_lastQuery) {
        case '/new':
          r18videos = await DBR18.getNewRelease(
            page: currentPage.value,
            perPage: _perPage + 1,
            videoCode: videoCode,
            actressName: actressName,
            categories: categories,
            yearStart: yearStart,
            yearEnd: yearEnd,
          );
          break;
        default:
          r18videos = await DBR18.search(
            _lastQuery,
            page: currentPage.value,
            perPage: _perPage + 1,
            videoCode: videoCode,
            actressName: actressName,
            categories: categories,
            yearStart: yearStart,
            yearEnd: yearEnd,
          );
          break;
      }

      if (_existingVideoCodes.isEmpty) {
        final existVideos = await DBVideos.getAll();
        _existingVideoCodes = existVideos.map((e) => e.videoCode ?? '').toSet();
      }

      hasNextPage.value = r18videos.length > _perPage;
      final pageItems = r18videos.take(_perPage).toList();

      final output = <JavitSearchResult>[];
      for (var i = 0; i < pageItems.length; i++) {
        final videoCode = pageItems[i]['video_code'].toString();
        if (videoCode.isValidVideoCode() == false) continue;
        final hasMatch = _existingVideoCodes.contains(videoCode);

        final actresses = pageItems[i]['actresses'].toString().split(',').map((e) => e.trim()).toList();
        final categories = pageItems[i]['categories'].toString().split(',').map((e) => e.trim()).toList();

        output.add(
          JavitSearchResult(
            videoId: pageItems[i]['id'],
            videoCode: pageItems[i]['video_code'],
            duration: pageItems[i]['duration'],
            durationFormated: '${pageItems[i]['release_date']}',
            releaseDate: '${pageItems[i]['release_date']}',
            title: pageItems[i]['title'],
            fanArt: pageItems[i]['fan_art'].toString().genImageUrl(),
            poster: pageItems[i]['poster'],
            trailer: pageItems[i]['trailer'],
            match: hasMatch,
            isReleased: DateTime.tryParse(pageItems[i]['release_date'] ?? '')?.isBefore(DateTime.now()),
            actresses: actresses,
            categories: categories,
          ),
        );
      }

      if (isLoadMore) {
        allVideos.addAll(output);
      } else {
        allVideos.value = output;
      }

      videos.value = allVideos.toList();
      _syncHavingVideos(videos.toList());
    } catch (e) {
      AppLog.logE('_loadPage e -> $e');
    } finally {
      if (isLoadMore) isLoadingMore.value = false;
    }
  }

  void _onScroll() {
    if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 240) {
      if (hasNextPage.isTrue && isLoadingMore.isFalse && isLoading.isFalse) {
        currentPage.value += 1;
        _loadPage(isLoadMore: true);
      }
    }
  }

  Future<void> openDialogFilter() async {
    await HelperOpener.openFilterDialog<JavitSearchResult>(
      state: filter,
      allVideos: allVideos.toList(),
      videos: videos,
      adapter: _filterAdapter,
      applyLocalFilter: false,
      onApplied: (_) async => _refreshSearchWithFilters(showLoading: true),
      onReset: () async => _refreshSearchWithFilters(showLoading: true),
    );
  }

  // ~ Download ────────────────────────────────────────────────────────────────
  Future<void> openDownloadLog() async {
    Get.back();
    final data = await DBActivity.getDownloadLogs(
      orderBy: 'updated_at DESC',
      groupBy: 'json_extract(content, "\$.filename")',
    );
    await Overlayment.show(
        context: Get.context,
        OverPanel(
          alignment: Alignment.center,
          width: 550,
          height: Get.height * 0.5,
          backgroundSettings: BackgroundSettings(blur: 5, color: Colors.transparent),
          animation: OverFadeAnimation(reverseDurationMilliseconds: 100, durationMilliseconds: 100),
          color: Colors.black.withAlpha(230),
          child: VStack([
            'Downloads'.text.bold.make().pOnly(bottom: 12),

            // ** actions
            HStack(
              [
                ExButtonElevated(
                  height: 38,
                  backgroundColor: AppColor.selected,
                  child: HStack(
                    [Icon(UIconsPro.regularRounded.plus, size: 11)],
                  ),
                  onPressed: () {
                    Overlayment.dismissLast();
                    openDialogDownload();
                  },
                ).pOnly(right: 6),
                ExButtonElevated(
                    height: 38,
                    child: HStack([
                      Icon(UIconsPro.regularRounded.progress_complete, size: 11, color: Vx.amber300).pOnly(right: 8),
                      'Clear Complete Task'.text.size(11).minFontSize(11).amber300.make(),
                    ]),
                    onPressed: () async {
                      await DBActivity.deleteAll(where: 'type = ? AND content LIKE ?', whereArgs: [kActivityTypeDownload, '%finish%']);
                      await Overlayment.dismissLast();
                      await openDownloadLog();
                    }).pOnly(right: 8),
                ExButtonElevated(
                  height: 38,
                  child: HStack([
                    Icon(UIconsPro.regularRounded.trash, size: 11, color: Vx.red300).pOnly(right: 8),
                    'Clear All Download Log'.text.size(11).minFontSize(11).red300.make(),
                  ]),
                  onPressed: () {
                    Overlayment.dismissLast();
                    ExAlert.adaptive(title: Text('Are you sure?', style: TextStyle(fontSize: 14)), content: Text('Clear all download log?', style: TextStyle(fontSize: 12)).pOnly(top: 8), actions: [
                      CupertinoDialogAction(
                        child: Text('Yes', style: TextStyle(color: Vx.red500, fontSize: 13)),
                        onPressed: () async {
                          await DBActivity.deleteAll(where: 'type = ?', whereArgs: [kActivityTypeDownload]);
                          await openDownloadLog();
                        },
                      ),
                      CupertinoDialogAction(
                        child: Text('No', style: TextStyle(fontSize: 13)),
                        onPressed: () async {
                          Get.back();
                          await openDownloadLog();
                        },
                      ),
                    ]);
                  },
                ),
              ],
            ).pOnly(bottom: 12),

            // ** body
            data.isEmpty
                ? ExUiErrorOrEmpty(
                    illustration: Icon(UIconsPro.regularRounded.empty_set, size: 32),
                    title: 'No Data Download Log',
                    message: 'Add some by click `+` button',
                    bgColor: AppColor.container,
                  ).expand()
                : Expanded(
                    child: Table(
                      border: TableBorder.all(color: AppColor.border),
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(3),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(1),
                        4: FlexColumnWidth(1),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: AppColor.container),
                          children: [
                            'Name'.text.size(11).minFontSize(11).bold.make().p8(),
                            'Url'.text.size(11).minFontSize(11).bold.make().p8(),
                            'Status'.text.size(11).minFontSize(11).bold.make().p8(),
                            'Added'.text.size(11).minFontSize(11).bold.make().p8(),
                            'DL Time'.text.size(11).minFontSize(11).bold.make().p8(),
                            'Action'.text.size(11).minFontSize(11).bold.make().p8(),
                          ],
                        ),

                        // items
                        ...List.generate(
                          data.length,
                          (index) {
                            final item = data[index];
                            final jsonData = jsonDecode(item.content ?? '');
                            final dt1 = DateTime.parse(item.createdAt ?? '');
                            final dt2 = DateTime.parse(item.updatedAt ?? '');
                            final diff = dt2.difference(dt1);
                            final totalSeconds = diff.inSeconds;
                            final finishTime = totalSeconds > 0 ? '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalSeconds % 60).toString().padLeft(2, '0')}' : '';
                            final statusIcon = () {
                              switch (jsonData['ev']) {
                                case 'finish': return '✅';
                                case 'failed': return '❌';
                                default: return '🏃🏻';
                              }
                            }();

                            var createdAt = item.createdAt?.toDateEx();
                            var addedTime = createdAt != null && createdAt.isSameDay(DateTime.now()) ? '• ${item.createdAt!.reformatDate(to: 'HH:mm')}' : item.createdAt?.reformatDate(to: 'yy/M/d');

                            return TableRow(
                              children: [
                                // -> Filename
                                HStack(
                                  [
                                    Icon(UIconsPro.regularRounded.folder, size: 11).pOnly(left: 8).onInkTap(() {
                                      HelperOpener.openFilePath('${jsonData['dir']}/${jsonData['filename']}.mp4');
                                    }),
                                    '${jsonData['filename']}'.text.size(12).minFontSize(12).maxLines(1).ellipsis.make().p(6).onInkTap(() {
                                      HelperMisc.copyToClipboard(jsonData['filename'], showToast: true);
                                    }).expand(),
                                  ],
                                ),
                                // -> URL
                                '${jsonData['url']}'.text.size(12).minFontSize(12).maxLines(1).ellipsis.make().p(6).onInkTap(() {
                                  HelperMisc.copyToClipboard(jsonData['url'], showToast: true);
                                }),
                                // -> Status
                                '$statusIcon'.text.size(12).minFontSize(12).maxLines(1).ellipsis.makeCentered().p(6).tooltip('${jsonData['ev']}'),
                                // -> Added Time
                                '$addedTime'.text.size(12).minFontSize(12).make().p(6).tooltip('${item.createdAt?.reformatDate(to: 'yy/M/d HH:mm:ss')}'),
                                // -> Finish Time
                                '$finishTime'.text.size(12).minFontSize(12).make().p(6).tooltip(HelperMisc.durationFormatFFmpeg(totalSeconds)),
                                // -> Action
                                HStack([
                                  if (statusIcon == '❌') ...[
                                    Icon(UIconsPro.regularRounded.rotate_left, size: 12).p4().onInkTap(() async {
                                      await startProcessDownload(jsonData['url'], jsonData['dir'], jsonData['filename'], worker: 1);
                                      await Overlayment.dismissLast();
                                    }),
                                  ],
                                  Icon(UIconsPro.regularRounded.trash, size: 12).p4().tooltip('delete log').onInkTap(() async {
                                    await DBActivity.deleteDownloadLogByFilename(jsonData['filename']);
                                    await Overlayment.dismissLast();
                                    await openDownloadLog();
                                  }),
                                ]).centered().p(6),
                              ],
                            );
                          },
                        ),
                      ],
                    ).scrollVertical(),
                  ),
          ]).p12(),
        ));
  }

  Future<void> openDialogDownload() async {
    final tecChunk = TextEditingController(text: AppPref.getDownloadWorker().toString());
    final tecUrl = TextEditingController();
    final tecDir = TextEditingController();
    final fnUrl = FocusNode();
    final tecFilename = TextEditingController(text: tecSearch.text);

    tecDir.text = AppPref.getDownloadPath();
    fnUrl.requestFocus();

    final isRawUrl = false.obs;

    ExAlert.adaptive(
      isDismissible: true,
      title: Text('Download', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 160),
        child: VStack(
          [
            HStack(
              [
                CupertinoTextField(
                  readOnly: true,
                  controller: tecDir,
                  placeholder: 'Save To...',
                  prefix: Icon(UIconsPro.regularRounded.folder, size: 13).pOnly(left: 8),
                  placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
                  style: TextStyle(fontSize: 13, color: Vx.neutral500),
                  onTap: () async {
                    await FilePicker.platform.getDirectoryPath(initialDirectory: tecDir.text).then((dir) {
                      if (dir != null) {
                        AppPref.setDownloadPath(dir);
                        tecDir.text = dir;
                      }
                    });
                  },
                ).expand(),
                6.widthBox,
                CupertinoTextField(
                  controller: tecChunk,
                  placeholder: 'Chunk',
                  prefix: Icon(UIconsPro.regularRounded.download, size: 13).pOnly(left: 8),
                  placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
                  style: TextStyle(fontSize: 13, color: Vx.white),
                  onChanged: (s) => AppPref.setDownloadWorker(s.toInt() ?? 1),
                ).w(90),
              ],
            ).pOnly(bottom: 12),
            CupertinoTextField(
              controller: tecUrl,
              focusNode: fnUrl,
              prefix: Icon(UIconsPro.regularRounded.link, size: 13).pOnly(left: 8),
              placeholder: 'Url',
              style: TextStyle(fontSize: 12, color: Vx.white),
              onChanged: (value) {
                tecFilename.text = value.split('/').last;
              },
            ).pOnly(bottom: 12),
            CupertinoTextField(
              controller: tecFilename,
              prefix: Icon(UIconsPro.regularRounded.hastag, size: 13).pOnly(left: 8),
              placeholder: 'Filename',
              style: TextStyle(fontSize: 12, color: Vx.white),
              onSubmitted: (value) async {
                await startProcessDownload(tecUrl.text, tecDir.text, tecFilename.text, isRawUrl: isRawUrl.value);
              },
            ).pOnly(bottom: 12),

            // RadioListTile
            Material(
              color: Colors.transparent,
              child: Transform.translate(
                offset: Offset(-0, -0),
                child: HStack([
                  Obx(
                    () => Checkbox.adaptive(
                      value: isRawUrl.value,
                      onChanged: (s) => isRawUrl.value = s ?? false,
                    ),
                  ),
                  Text('Raw Url', style: TextStyle(fontSize: 12, color: Vx.white)).pOnly(left: 8),
                ]).wFull(Get.context!).onInkTap(() => isRawUrl.value = !isRawUrl.value),
              ),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Open Log', style: TextStyle(fontSize: 12, color: Vx.white)),
          onPressed: () async => await openDownloadLog(),
        ),
        CupertinoDialogAction(
          child: Text('Start Download', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          onPressed: () async {
            await startProcessDownload(tecUrl.text, tecDir.text, tecFilename.text, isRawUrl: isRawUrl.value);
          },
        ),
      ],
    );
  }

  Future<void> startProcessDownload(String url, String dir, String filename, {int? worker, bool? isRawUrl = false}) async {
    if (url.isEmpty || dir.isEmpty || filename.isEmpty) {
      await HelperToast.warn('Please fill all fields');
      return;
    }

    final sanitizedFilename = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final safeFilename = sanitizedFilename.trim().substring(0, sanitizedFilename.length.clamp(0, 100));

    try {
      Get.back();

      try {
        await shell.run('chmod +x "${appSetting.appPath}/javit_dl"');
      } catch (e) {
        await HelperToast.error('${e.toString()}');
        return;
      }

      // log to activity
      await DBActivity.addDownloadLog(Activity(type: kActivityTypeDownload, content: genJsonFormat('start', url, dir, filename)));

      // legacy env PATH (macOS only)
      const homebrewPath = '/opt/homebrew/bin';
      final currentPath = Platform.environment['PATH'] ?? '/usr/bin:/bin:/usr/sbin:/sbin';
      final envPath = '$homebrewPath:$currentPath';

      final execPath = '${appSetting.appPath}/javit_dl';
      final execArgs = [
        '-u', '"$url"',
        '-o', '"$dir/$safeFilename"',
        '-tf', '"${appSetting.appPath}/.dl_tmp"',
        '-r', '5',
        '-c', '${worker ?? AppPref.getDownloadWorker()}',
        '-auto',
        if (isRawUrl == true) '-rawurl',
      ];

      await shell.run('$execPath ${execArgs.join(' ')}', 
        workingDirectory: appSetting.appPath,
        runInShell: true,
        commandVerbose: false,
        verbose: false,
        environment: {'PATH': envPath},
        onProcess: (process) async {
          currentProcessDownload.value = process;
          // listen stdout
          process.outLines.listen((s) {
            downloadStdout.value = s;
            Get.find<HomeController>().footerText.value = s;
          }).onError((e) {
            AppLog.logE('listen stdout e -> $e');
            downloadStdout.value = '$e';
          });

          await process.exitCode.then((code) async {
            if (code == 1) {
              downloadStdout.value = 'Download Failed 🔴';

              final _totalFileSize = await DBVideos.getTotalFileSizeAllVideo();
              Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()} (${_totalFileSize?.toFileSizeFormat()})';
              await HelperToast.error('Download Failed 🔴');
              
              final currentActivity = await DBActivity.getDownloadLogByFilename(safeFilename);
              await DBActivity.updateDownloadLog(id: currentActivity?.id ?? '', content: genJsonFormat('failed', url, dir, safeFilename));
              await HelperMisc.playSoundDownloadComplate();
            }

            if (code == 0) {
              downloadStdout.value = 'Download Finished ✅';
              final _totalFileSize = await DBVideos.getTotalFileSizeAllVideo();
              Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()} (${_totalFileSize?.toFileSizeFormat()})';

              await HelperToast.success('Download Finished ✅');

              final currentActivity = await DBActivity.getDownloadLogByFilename(safeFilename);
              await DBActivity.updateDownloadLog(id: currentActivity?.id ?? '', content: genJsonFormat('finish', url, dir, safeFilename));
              await HelperMisc.playSoundDownloadComplate();

              // create notification
              final notificationModel = NotificationModel(
                title: '$safeFilename',
                body: 'Download Finished. Click to see details',
                payload: '$dir/$safeFilename.mp4',
              );

              await AppNotification.show(notificationModel);
              AppNotification.registerNotificationTapHandler((v) {
                print('payload: $v');
              });
            }

            process.kill();
          });

          // listen stderr
          // process.errLines.listen((s) => AppLog.logE('process.errLines e -> $s'));
        },
      );

      if (currentProcessDownload.value != null) {
        if (await currentProcessDownload.value?.exitCode == 0) {
          downloadStdout.value = '';
        }
      }
    } catch (e) {
      AppLog.logE('startProcessDownload e -> $e');
    }
  }

  Future<void> killProcessDownload() async {
    try {
      currentProcessDownload.value?.kill(ProcessSignal.sigkill);
      currentProcessDownload.value = null;
      downloadStdout.value = '';

      final _totalFileSize = await DBVideos.getTotalFileSizeAllVideo();
      Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()} (${_totalFileSize?.toFileSizeFormat()})';
    } catch (e) {
      AppLog.logD('killProcessDownload e -> $e');
    }
  }

  String genJsonFormat(String ev, String url, String dir, String filename, {String? error}) {
    final o = {}.obs;
    o['ev'] = ev;
    o['url'] = url;
    o['dir'] = dir;
    o['filename'] = filename;
    o['error'] = error ?? '';
    return jsonEncode(o);
  }
}
