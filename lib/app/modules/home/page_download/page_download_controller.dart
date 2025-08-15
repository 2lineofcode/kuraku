import 'dart:convert';

import 'package:ex_kit/ex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:process_run/process_run.dart' as shell;
import 'package:process_run/stdio.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:uuid/v4.dart';

import '../../../../env.g.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_setting.dart';
import '../../../data/api/api_javit.dart';
import '../../../data/database/db_history.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/__javit_search_entity.dart';
import '../../../data/models/history_entity.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';

class PageDownloadController extends GetxController {
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearch = ''.obs;
  final currentLang = 'en'.obs;   // en | id
  final currentMode = 'net'.obs;  // net | db
  final scrollController = ScrollController();

  final response = JavitSearch().obs;
  final hasNextPage = false.obs;
  final currentPage = 0.obs;
  final videos = <JavitSearchResult>[].obs;

  // downloader
  final downloadStdout = ''.obs;
  final cProcessDownload = Rx<Process?>(null);
  final retryC = 0.obs;

  final appSetting = Get.find<AppSettingService>();

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page download ==> onInit called');
    phSearch.value = await DBVideos.getRandomVideoCode();
    await onReset();
  }

  Future<void> onSearch(String s) async {
    
    // ** net mode
    if (currentMode.value == 'net') {
      try {
        if (s.isEmpty) {
          await onReset();
          return;
        }

        HelperLoading.show();
        response.value = await ApiJavit.search(s: s, lang: currentLang.value, page: currentPage.value);

        if (response.value.result == null || response.value.result!.isEmpty) {
          if (retryC.value < 2) {
            retryC.value++;
            AppLog.logD('retryC.value++ -> ${retryC.value}');
            await 1.seconds.delay();
            await onSearch(s);
          }
        }

        hasNextPage.value = response.value.hasNextPage ?? false;
        currentPage.value = response.value.page ?? 1;
        videos.value = response.value.result ?? [];
        retryC.value = 0;
        fnSearch.requestFocus();
        HelperLoading.dismiss();

        await scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      } catch (_) {}
    } 
    
    // ** db mode
    else {
      try {

        if (s.isEmpty) {
          await onReset(); return;
        }

        HelperLoading.show();
        final r18 = await DBR18.search(s);
        HelperLoading.dismiss();

        final output = <JavitSearchResult>[];
        for (var i = 0; i < r18.length; i++) {
          if (r18[i]['video_code'] == null || r18[i]['video_code'].isEmpty) continue;
          output.add(
            JavitSearchResult(
              videoId: r18[i]['id'],
              videoCode: r18[i]['video_code'],
              duration: r18[i]['duration'],
              durationFormated: '${r18[i]['release_date']}',
              title: r18[i]['title'],
              fanArt: r18[i]['fan_art'].toString().imgUrl(),
              poster: r18[i]['poster'],
              trailer: r18[i]['trailer'],
          ));
        }

        videos.value = output;

        await scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      } catch (e) {
        AppLog.logE('e -> $e');
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
    retryC.value = 0;
    hasNextPage.value = false;
    videos.value = [];
    currentLang.value = AppPref.getDownloadLang();
    currentMode.value = AppPref.getDownloadMode();
    fnSearch.requestFocus();
  }

  Future<void> onItemTap(JavitSearchResult item) async {
    if (currentMode.value == 'db') {
      await launchUrlString('${Env.njavUrl}/${currentLang.value}/search/${item.videoCode}');
    } else {
      await launchUrlString('${Env.njavUrl}/${currentLang.value}/${item.videoCode}');
    }
  }

  // ~ Download ────────────────────────────────────────────────────────────────
  Future<void> openDialogDownload() async {
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
          CupertinoTextField(
            readOnly: true,
            controller: tecDir,
            placeholder: 'Save To...',
            prefix: Icon(CupertinoIcons.folder, size: 13).pOnly(left: 8),
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
          ).pOnly(bottom: 12),
          CupertinoTextField(
            controller: tecUrl,
            focusNode: fnUrl,
            prefix: Icon(CupertinoIcons.link, size: 13).pOnly(left: 8),
            placeholder: 'Url',
            style: TextStyle(fontSize: 12, color: Vx.white),
          ).pOnly(bottom: 12),
          CupertinoTextField(
            controller: tecFilename,
            prefix: Icon(CupertinoIcons.number_square, size: 13).pOnly(left: 8),
            placeholder: 'Filename',
            style: TextStyle(fontSize: 12, color: Vx.white),
            onSubmitted: (value) async {
              await startProcessDownload('hls', tecUrl.text, tecDir.text, tecFilename.text);
            },
          ).pOnly(bottom: 12),
          Text('* (NEW) Support HLS(.m3u8)', style: TextStyle(fontSize: 10)),
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

  Future<void> startProcessDownload(String type, String url, String dir, String filename) async {
    if (url.isEmpty || dir.isEmpty || filename.isEmpty) {
      await HelperToast.warn('Please fill all fields');
      return;
    }

    try {
      Get.back();

      try {
        await shell.run('chmod +x "${appSetting.appPath}/dl"');
      } catch (e) {
        await HelperToast.error('${e.toString()}');
        return;
      }

      // log to history
      final id = UuidV4().generate();
      await DBHistory.add(History(id: id, type: 'download', message: genJsonFormat('start', url, dir, filename)));

      await shell.run(
        '${appSetting.appPath}/dl $type -u "$url" -d "$dir" -o "$filename"',
        commandVerbose: false,
        verbose: false,
        onProcess: (process) async {
          cProcessDownload.value = process;
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
              await DBHistory.update(History(id: id, type: 'download', message: genJsonFormat('failed', url, dir, filename)));
            }

            if (code == 0) {
              downloadStdout.value = 'Download Finished ✅';
              Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
              await HelperToast.success('Download Finished ✅');
              await DBHistory.update(History(id: id, type: 'download', message: genJsonFormat('finish', url, dir, filename)));
            }

            await shell.run('${appSetting.appPath}/dl clear -y', commandVerbose: false, verbose: false);

            process.kill();
          });

          // listen stderr
          // process.errLines.listen((s) => AppLog.logE('process.errLines e -> $s'));
        },
      );

      if (cProcessDownload.value != null) {
        if (await cProcessDownload.value?.exitCode == 0) {
          downloadStdout.value = '';
        }
      }
    } catch (e) {
      AppLog.logE('startProcessDownload e -> $e');
    }
  }

  Future<void> killProcessDownload() async {
    try {
      cProcessDownload.value?.kill(ProcessSignal.sigkill);
      cProcessDownload.value = null;
      downloadStdout.value = '';
      Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
    } catch (e) {
      AppLog.logD('killProcessDownload e -> $e');
    }
  }

  Future<void> openDownloadLog() async {
    Get.back();
    final data = await DBHistory.getAll(where: 'type = ?', whereArgs: ['download'], orderBy: 'updated_at DESC');
    await Overlayment.show(
        context: Get.context,
        OverPanel(
          alignment: Alignment.centerRight,
          width: 300,
          animation: OverSlideAnimation(
            beginAlignment: Alignment.centerRight,
            reverseDurationMilliseconds: 100,
            durationMilliseconds: 400,
          ),
          child: VStack([
            'Download Log'.text.bold.make().pOnly(bottom: 24),
            ListView.separated(
              itemCount: data.length,
              separatorBuilder: (context, index) => Divider(),
              itemBuilder: (context, index) {
                final item = data[index];
                final jsonData = jsonDecode(item.message ?? '');
                final dt1 = DateTime.parse(item.createdAt ?? '');
                final dt2 = DateTime.parse(item.updatedAt ?? '');
                final diff = dt2.difference(dt1);
                int totalSeconds = diff.inSeconds;
                int minutes = totalSeconds ~/ 60;
                int seconds = totalSeconds % 60;

                var result = '';
                if (minutes > 0) result += '⏳︎ $minutes minute${minutes > 1 ? 's' : ''}';

                if (seconds > 0) {
                  if (minutes > 0) result += ', ';
                  result += '⏳︎ $seconds second${seconds > 1 ? 's' : ''}';
                }
                if (result.isEmpty) result = '';

                return HStack([
                  '${jsonData['ev']}'.text.size(11).minFontSize(11).uppercase.bold.make().w(60),
                  VStack([
                    '🔗 ${jsonData['url']}'.text.size(10).minFontSize(10).ellipsis.make().onInkTap(() {
                      HelperMisc.copyToClipboard(jsonData['url'], showToast: true);

                    }),
                    '📁 ${jsonData['dir']}'.text.size(10).minFontSize(10).make().onInkTap(() {
                      HelperOpener.openFilePath('${jsonData['dir']}/${jsonData['filename']}');
                    }),
                    '📺 ${jsonData['filename']}'.text.size(10).minFontSize(10).make().onInkTap(() {
                      HelperMisc.copyToClipboard(jsonData['filename'], showToast: true);
                    }),
                    '$result'.text.size(10).minFontSize(10).make(),
                  ]).expand(),
                ]).tooltip(item.createdAt ?? '');
              },
            ).expand(),
            ExButtonText(
              width: double.infinity,
              label: 'Clear Log',
              labelColor: Vx.red500,
              onPressed: () async {
                await Overlayment.dismissLast();
                await DBHistory.deleteAll(where: 'type = ?', whereArgs: ['download']);
              },
            ).hide(isVisible: data.isNotEmpty),
          ]).p12(),
        ));
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
