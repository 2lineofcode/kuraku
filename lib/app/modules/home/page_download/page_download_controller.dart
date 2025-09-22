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
import '../../../core/app_pref.dart';
import '../../../core/app_setting.dart';
import '../../../core/const.dart';
import '../../../data/api/api_javit.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/__javit_search_entity.dart';
import '../../../data/models/activity_entity.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../../widgets/widget_auto_complate.dart';
import '../home_controller.dart';

class PageDownloadController extends GetxController {
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearch = ''.obs;
  final currentLang = kLangEn.obs;
  final currentMode = kModeDB.obs;
  final scrollController = ScrollController();

  final response = JavitSearch().obs;
  final hasNextPage = false.obs;
  final currentPage = 0.obs;
  final videos = <JavitSearchResult>[].obs;

  // downloader
  final downloadStdout = ''.obs;
  final currentProcessDownload = Rx<Process?>(null);
  final retryCount = 0.obs;

  // filters
  final isFiltered = false.obs;
  final tecVideoCode = TextEditingController();
  final tecActressName = TextEditingController();
  final tecCategory = TextEditingController();
  final actresses = <String>[].obs;
  final categories = <String>[].obs;
  final categoriesSelected = <String>[].obs;
  final currentRange = RangeValues(2000, DateTime.now().year.toDouble()).obs;

  // app setting
  final appSetting = Get.find<AppSettingService>();

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page download ==> onInit called');
    phSearch.value = 'Video Code or Title...';
    await onReset();
    isFiltered.value = false;
    // await _onResetFilter();
  }

  Future<void> onSearch(String s) async {

    if (s.isEmpty) {
      await onReset();
      return;
    }

    // ** net mode
    if (currentMode.value == kModeNet) {
      try {
        
        HelperLoading.show();
        response.value = await ApiJavit.search(s: s, lang: currentLang.value, page: currentPage.value);
        final existVideo = await DBVideos.getAll();

        if (response.value.result == null || response.value.result!.isEmpty) {
          if (retryCount.value < 2) {
            retryCount.value++;
            AppLog.logD('retryC.value++ -> ${retryCount.value}');
            await 1.seconds.delay();
            await onSearch(s);
          }
        }

        hasNextPage.value = response.value.hasNextPage ?? false;
        currentPage.value = response.value.page ?? 1;

        videos.clear();
        for (JavitSearchResult video in response.value.result ?? []) {
          video.isUncensoredLeak = video.videoCode?.contains('UNCENSORED-LEAK');
          video.videoCode = video.videoCode?.replaceAll('-UNCENSORED-LEAK', '');
          video.match = existVideo.any((eVid) => video.videoCode == eVid.videoCode);
          videos.add(video);
        }

        retryCount.value = 0;
        fnSearch.requestFocus();
        HelperLoading.dismiss();

        if (scrollController.hasClients) {
          await scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
        }
      } catch (e) {
        // AppLog.logE('onSearch netMode e -> $e');
      }
    }

    // ** db mode
    else {
      try {

        HelperLoading.show();
        final r18videos = await DBR18.search(s);
        final existVideos = await DBVideos.getAll();

        final output = <JavitSearchResult>[];
        for (var i = 0; i < r18videos.length; i++) {
          final videoCode = r18videos[i]['video_code'].toString();
          if (videoCode.isValidVideoCode() == false) continue;
          final hasMatch = existVideos.any((eVid) => videoCode == (eVid.videoCode ?? ''));

          final actresses = r18videos[i]['actresses'].toString().split(',').map((e) => e.trim()).toList();
          final categories = r18videos[i]['categories'].toString().split(',').map((e) => e.trim()).toList();

          output.add(
            JavitSearchResult(
              videoId: r18videos[i]['id'],
              videoCode: r18videos[i]['video_code'],
              duration: r18videos[i]['duration'],
              durationFormated: '${r18videos[i]['release_date']}',
              releaseDate: '${r18videos[i]['release_date']}',
              title: r18videos[i]['title'],
              fanArt: r18videos[i]['fan_art'].toString().genImageUrl(),
              poster: r18videos[i]['poster'],
              trailer: r18videos[i]['trailer'],
              match: hasMatch,
              isReleased: DateTime.tryParse(r18videos[i]['release_date'] ?? '')?.isBefore(DateTime.now()),
              actresses: actresses,
              categories: categories,
            ),
          );
        }

        videos.value = output;
        HelperLoading.dismiss();

        if (scrollController.hasClients) {
          await scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
        }

        if (isFiltered.isTrue) await _onApplyFilter();
      } catch (e) {
        AppLog.logE('onSearch dbMode e -> $e');
      }
    }
  }

  Future<void> onNextPage() async {
    if (hasNextPage.value == true) {
      currentPage.value++;
      await onSearch(tecSearch.text);
    }
  }

  Future<void> onPreviousPage() async {
    if (currentPage.value > 1) {
      currentPage.value--;
      await onSearch(tecSearch.text);
    }
  }

  Future<void> onReset() async {
    response.value = JavitSearch();
    currentPage.value = 0;
    retryCount.value = 0;
    hasNextPage.value = false;
    videos.value = [];
    currentLang.value = AppPref.getDownloadLang();
    currentMode.value = AppPref.getDownloadMode();
    tecSearch.text = '';
    fnSearch.requestFocus();
  }

  // ~ Filters ────────────────────────────────────────────────────────────────
  Future<void> openDialogFilter() async {
    // actresses
    if (actresses.isEmpty) {
      await DBR18.getAllActress().then((actress) {
        for (var i = 0; i < actress.length; i++) {
          actresses.add('${actress[i]['name_romaji']}');
        }
        actresses.unique();
      });
    }

    // categories
    if (categories.isEmpty) {
      await DBR18.getAllCategories().then((cat) {
        for (var i = 0; i < cat.length; i++) {
          categories.add('${cat[i]['name_en']}');
        }
        categories.unique();
      });
    }

    await Overlayment.show(
      context: Get.context!,
      OverPanel(
        alignment: Alignment.center,
        width: Get.width * 50 / 100,
        animation: OverSlideAnimation(
          beginAlignment: Alignment.bottomCenter,
          reverseDurationMilliseconds: 100,
          durationMilliseconds: 400,
        ),
        child: VStack(
          [
            'Filter'.text.bold.make().pOnly(bottom: 16),
            Container(
              decoration: ExDecorator.box(borderColor: AppColor.border, borderRadius: 4),
              child: VStack(
                [
                  HStack(
                    [
                      CupertinoTextField(
                        controller: tecVideoCode,
                        clearButtonMode: OverlayVisibilityMode.editing,
                        placeholder: 'Video Code..',
                        style: TextStyle(color: Vx.white, fontSize: 12),
                      ).expand(),
                      12.widthBox,
                      ExAutoComplate(
                        controller: tecActressName,
                        items: actresses,
                        fontSize: 12,
                        placeHolder: 'Actress Name (${actresses.length})',
                        onSelected: (s) => tecActressName.text = s,
                      ).expand(),
                    ],
                  ).pOnly(bottom: 16),
                  Obx(
                    () => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categoriesSelected.map((tag) {
                        return Chip(
                          label: Text(tag, style: TextStyle(fontSize: 9)),
                          deleteIcon: Icon(Icons.close, size: 12),
                          labelPadding: EdgeInsets.all(2),
                          side: BorderSide(color: AppColor.container),
                          backgroundColor: AppColor.selected,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(1)),
                          onDeleted: () => {
                            categoriesSelected.remove(tag),
                          },
                        );
                      }).toList(),
                    ).pOnly(bottom: 12),
                  ),
                  ExAutoComplate(
                    controller: tecCategory,
                    items: categories,
                    fontSize: 12,
                    placeHolder: 'Add Category (${categories.length})',
                    emptyText: 'No Category with `${tecCategory.text}` Found ',
                    onSelected: (s) {
                      tecCategory.clear();
                      if (categoriesSelected.contains(s)) return;
                      categoriesSelected.add(s);
                    },
                  ).pOnly(bottom: 12),
                  HStack(
                    [
                      'Year:'.text.size(11).make().pOnly(right: 24),
                      Obx(
                        () => SliderTheme(
                          data: SliderTheme.of(Get.context!).copyWith(
                            trackHeight: 4,
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: AppColor.selected,
                            inactiveTrackColor: AppColor.container,
                            rangeTrackShape: RectangularRangeSliderTrackShape(),
                            valueIndicatorTextStyle: const TextStyle(fontSize: 10, color: Colors.white),
                            valueIndicatorColor: AppColor.container,
                            rangeThumbShape: RoundRangeSliderThumbShape(
                              enabledThumbRadius: 6,
                              disabledThumbRadius: 0,
                            ),
                          ),
                          child: RangeSlider(
                            values: currentRange.value,
                            min: 2000,
                            max: DateTime.now().year.toDouble(),
                            divisions: (DateTime.now().year.toDouble() - 2000).toInt(),
                            labels: RangeLabels(
                              currentRange.value.start.toInt().toString(),
                              currentRange.value.end.toInt().toString(),
                            ),
                            onChanged: (RangeValues values) {
                              currentRange.value = values;
                            },
                          ),
                        ).expand(),
                      ),
                      Obx(() => '${currentRange.value.start.toInt()} - ${currentRange.value.end.toInt()}'.text.size(11).make().pOnly(left: 24)),
                    ],
                  ),
                ],
              ).p12(),
            ),
            HStack(
              [
                ExButtonElevated(
                  height: 38,
                  label: 'Clear Filter',
                  labelColor: Vx.red300,
                  labelSize: 12,
                  onPressed: () async => await _onResetFilter(),
                ).pOnly(right: 12),
                ExButtonElevated(
                  height: 38,
                  label: 'Filter',
                  labelSize: 12,
                  backgroundColor: AppColor.selected,
                  onPressed: () async => await _onApplyFilter(),
                ).expand(),
              ],
            ).pOnly(top: 24, bottom: 16),
          ],
        ).p16(),
      ),
    );
  }

  Future<void> _onResetFilter() async {
    tecVideoCode.text = '';
    tecActressName.text = '';
    tecCategory.text = '';
    actresses.clear();
    categories.clear();
    categoriesSelected.clear();
    currentRange.value = RangeValues(2000, DateTime.now().year.toDouble());
    isFiltered.value = false;
    await onSearch(tecSearch.text);
    await Overlayment.dismissLast();
  }

  Future<void> _onApplyFilter() async {
    var filteredVideos = videos.toList();

    // filter `video_code`
    if (tecVideoCode.text.isNotBlank) {
      final query = tecVideoCode.text.toLowerCase();
      filteredVideos = filteredVideos.where((video) => video.videoCode.toString().toLowerCase().contains(query)).toList();
    }

    // filter `actresses`
    if (tecActressName.text.isNotBlank) {
      final query = tecActressName.text.toLowerCase();
      filteredVideos = filteredVideos.where((video) => video.actresses.toString().toLowerCase().contains(query)).toList();
    }

    // filter `categories`
    if (categoriesSelected.isNotEmpty) {
      filteredVideos = filteredVideos.where((video) => video.categories!.containsAll(categoriesSelected)).toList();
    }

    // filter `years`
    if (currentRange.value.start.toInt() > 0 || currentRange.value.end.toInt() > 0) {
      filteredVideos = filteredVideos.where((video) {
        if (video.releaseDate == null) return false;
        final year = video.releaseDate!.toDateEx(format: kYMd).year;
        final startYear = currentRange.value.start.toInt();
        final endYear = currentRange.value.end.toInt();
        return year >= startYear && year <= endYear;
      }).toList();
    }

    isFiltered.value = true;
    videos.value = filteredVideos;
    await Overlayment.dismissLast();
  }

  // ~ Download ────────────────────────────────────────────────────────────────
  Future<void> openDownloadLog() async {
    Get.back();
    final data = await DBActivity.getAll(
      where: 'type = ?',
      whereArgs: [kActivityTypeDownload],
      orderBy: 'updated_at DESC',
      groupBy: 'json_extract(content, "\$.filename")',
    );
    await Overlayment.show(
        context: Get.context,
        OverPanel(
          alignment: Alignment.center,
          width: 680,
          height: Get.height * 0.5,
          animation: OverSlideAnimation(
            beginAlignment: Alignment.bottomCenter,
            reverseDurationMilliseconds: 100,
            durationMilliseconds: 400,
          ),
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
                    }
                ).pOnly(right: 8),
                ExButtonElevated(
                  height: 38,
                  child: HStack([
                    Icon(UIconsPro.regularRounded.trash, size: 11, color: Vx.red300).pOnly(right: 8),
                    'Clear All Log'.text.size(11).minFontSize(11).red300.make(),
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
                                await startProcessDownload('hls', jsonData['url'], jsonData['dir'], jsonData['filename'], worker: 1);
                                await Overlayment.dismissLast();
                              }),
                            ],
                            Icon(UIconsPro.regularRounded.trash, size: 12).p4().tooltip('delete log').onInkTap(() async {
                              await DBActivity.deleteByFilename(jsonData['filename']);
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

    ExAlert.adaptive(
      title: Text('Download', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: VStack(
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
              await startProcessDownload('hls', tecUrl.text, tecDir.text, tecFilename.text);
            },
          ).pOnly(bottom: 12),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Open Log', style: TextStyle(fontSize: 12, color: Vx.white)),
          onPressed: () async => await openDownloadLog(),
        ),
        CupertinoDialogAction(
          child: Text('Start Download', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          onPressed: () async {
            await startProcessDownload('hls', tecUrl.text, tecDir.text, tecFilename.text);
          },
        ),
      ],
    );
  }

  Future<void> startProcessDownload(String type, String url, String dir, String filename, {int? worker}) async {
    if (url.isEmpty || dir.isEmpty || filename.isEmpty) {
      await HelperToast.warn('Please fill all fields');
      return;
    }

    try {
      Get.back();

      try {
        await shell.run('chmod +x "${appSetting.appPath}/javit_dl"');
      } catch (e) {
        await HelperToast.error('${e.toString()}');
        return;
      }

      // log to activity
      // final id = UuidV4().generate();
      await DBActivity.add(Activity(type: kActivityTypeDownload, content: genJsonFormat('start', url, dir, filename)));

      await shell.run(
        '${appSetting.appPath}/javit_dl $type -u "$url" -d "$dir" -o "$filename" -w ${ worker ?? AppPref.getDownloadWorker()}',
        commandVerbose: false,
        verbose: false,
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
              Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
              await HelperToast.error('Download Failed 🔴');
              
              final currentActivity = await DBActivity.getByFilename(filename);
              currentActivity.content = genJsonFormat('failed', url, dir, filename);
              await DBActivity.update(currentActivity);
            }

            if (code == 0) {
              downloadStdout.value = 'Download Finished ✅';
              Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
              await HelperToast.success('Download Finished ✅');

              final currentActivity = await DBActivity.getByFilename(filename);
              currentActivity.content = genJsonFormat('finish', url, dir, filename);
              await DBActivity.update(currentActivity);
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
      Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
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

// ────────────────────────────────────────────────────────────────
// ⵌ const
// ────────────────────────────────────────────────────────────────
// language
const kLangEn = 'en';
const kLangId = 'id';
// search mode
const kModeNet = 'net';
const kModeDB = 'db';