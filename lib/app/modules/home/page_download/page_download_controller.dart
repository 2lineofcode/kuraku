import 'dart:async';
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
import '../../../data/models/activity_entity.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';
import 'page_download_search_tab.dart';

class PageDownloadController extends GetxController {
  final tabs = <PageDownloadSearchTab>[].obs;
  final activeTabIndex = 0.obs;
  final tabScrollController = ScrollController();
  int _nextTabId = 0;
  PageDownloadSearchTab get activeTab => tabs[activeTabIndex.value];

  final downloadStdout = ''.obs;
  final currentProcessDownload = Rx<Process?>(null);
  final retryCount = 0.obs;
  final appSetting = Get.find<AppSettingService>();

  @override
  void onInit() {
    super.onInit();
    final saved = AppPref.getDownloadTabs();
    final entries = saved['tabs'];
    if (entries is List) {
      for (final entry in entries.whereType<Map<String, dynamic>>()) {
        final tab = createTab(_nextTabId++);
        tab.restorePreferences(entry);
        tab.watchPreferences(_saveTabs);
        tabs.add(tab);
        unawaited(tab.restoreSearch());
      }
    }
    if (tabs.isEmpty) {
      addTab();
    } else {
      final active = saved['activeTab'];
      selectTab(active is int ? active.clamp(0, tabs.length - 1) : 0);
    }
  }

  void _saveTabs() {
    unawaited(AppPref.setDownloadTabs({
      'tabs': tabs.map((tab) => tab.toPreferences()).toList(),
      'activeTab': activeTabIndex.value,
    }).catchError((Object error) {
      AppLog.logW('Saving Download tabs failed: $error');
    }));
  }

  PageDownloadSearchTab createTab(int id) => PageDownloadSearchTab(id);

  void addTab() {
    final tab = createTab(_nextTabId++);
    tab.watchPreferences(_saveTabs);
    tabs.add(tab);
    selectTab(tabs.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && tabScrollController.hasClients) tabScrollController.jumpTo(tabScrollController.position.maxScrollExtent);
    });
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeTabIndex.value = index;
    _saveTabs();
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs.removeAt(index);
    tab.close();
    if (tabs.isEmpty) {
      addTab();
    } else {
      final next = index < activeTabIndex.value ? activeTabIndex.value - 1 : activeTabIndex.value;
      selectTab(next.clamp(0, tabs.length - 1));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());
  }

  Future<void> onRefresh() async {
    for (final tab in tabs.toList()) {
      await tab.onRefresh();
    }
  }

  @override
  void onClose() {
    _saveTabs();
    tabScrollController.dispose();
    for (final tab in tabs) {
      tab.dispose();
    }
    super.onClose();
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
          color: AppColor.panel,
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
    final tecFilename = TextEditingController(text: activeTab.tecSearch.text);

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
                    await FilePicker.getDirectoryPath(initialDirectory: tecDir.text).then((dir) {
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
                  style: TextStyle(fontSize: 13, color: AppColor.text),
                  onChanged: (s) => AppPref.setDownloadWorker(s.toInt() ?? 1),
                ).w(90),
              ],
            ).pOnly(bottom: 12),
            CupertinoTextField(
              controller: tecUrl,
              focusNode: fnUrl,
              prefix: Icon(UIconsPro.regularRounded.link, size: 13).pOnly(left: 8),
              placeholder: 'Url',
              style: TextStyle(fontSize: 12, color: AppColor.text),
              onChanged: (value) {
                tecFilename.text = value.split('/').last;
              },
            ).pOnly(bottom: 12),
            CupertinoTextField(
              controller: tecFilename,
              prefix: Icon(UIconsPro.regularRounded.hastag, size: 13).pOnly(left: 8),
              placeholder: 'Filename',
              style: TextStyle(fontSize: 12, color: AppColor.text),
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
                  Text('Raw Url', style: TextStyle(fontSize: 12, color: AppColor.text)).pOnly(left: 8),
                ]).wFull(Get.context!).onInkTap(() => isRawUrl.value = !isRawUrl.value),
              ),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Open Log', style: TextStyle(fontSize: 12, color: AppColor.text)),
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

              await Get.find<HomeController>().updateFooterSummary();
              await HelperToast.error('Download Failed 🔴');
              
              final currentActivity = await DBActivity.getDownloadLogByFilename(safeFilename);
              await DBActivity.updateDownloadLog(id: currentActivity?.id ?? '', content: genJsonFormat('failed', url, dir, safeFilename));
              await HelperMisc.playSoundDownloadComplate();
            }

            if (code == 0) {
              downloadStdout.value = 'Download Finished ✅';
              await Get.find<HomeController>().updateFooterSummary();

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

      await Get.find<HomeController>().updateFooterSummary();
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
