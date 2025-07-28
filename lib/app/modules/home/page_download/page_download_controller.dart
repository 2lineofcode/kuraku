import 'package:ex_kit/ex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:process_run/process_run.dart' as shell;
import 'package:process_run/stdio.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_setting.dart';
import '../../../core/const.dart';
import '../../../data/api/api_javit.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/__javit_search_entity.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';

class PageDownloadController extends GetxController {
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearch = ''.obs;
  final currentLang = 'en'.obs;
  final scrollController = ScrollController();

  final api = Get.find<ApiJavit>();
  final response = JavitSearch().obs;
  final hasNextPage = false.obs;
  final currentPage = 0.obs;
  final videos = <JavitSearchResult>[].obs;

  // downloader
  final downloadStdout = ''.obs;
  final cProcessDownload = Rx<Process?>(null);
  final retryC = 0.obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page download ==> onInit called');
    phSearch.value = await DBVideos.getRandomVideoCode();
    await onReset();
  }

  Future<void> onSearch(String s) async {
    try {
      if (s.isEmpty) {
        await onReset();
        return;
      }

      ExLoading.show(paddingSymmetric: Get.width * 30 / 100);
      response.value = await api.search(s: s, lang: currentLang.value, page: currentPage.value);

      if (response.value.result == null || response.value.result!.isEmpty) {
        if (retryC.value < 2) {
          retryC.value++;
          AppLog.logD('retryC.value++; -> ${retryC.value}');
          await 1.seconds.delay();
          await onSearch(s);
        }
      }

      hasNextPage.value = response.value.hasNextPage ?? false;
      currentPage.value = response.value.page ?? 1;
      videos.value = response.value.result ?? [];
      retryC.value = 0;
      fnSearch.requestFocus();
      ExLoading.dismiss();

      await scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    } catch (_) {}
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
    fnSearch.requestFocus();
  }

  Future<void> onItemTap(JavitSearchResult item) async {
    await launchUrlString('https://njavtv.com/${currentLang.value}/${item.videoCode}');
  }

  // ~ Download ────────────────────────────────────────────────────────────────
  Future<void> openDialogDownload() async {
    final tecUrl = TextEditingController();
    final tecDir = TextEditingController();
    final fnUrl = FocusNode();
    final tecFilename = TextEditingController(text: tecSearch.text);
    
    tecDir.text = Get.find<AppSettingService>().pref.read(kDownloadDir);
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
                  Get.find<AppSettingService>().pref.write(kDownloadDir, dir);
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
          child: Text('Start Download', style: TextStyle(fontSize: 13)),
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
        await shell.run('chmod +x "${Get.find<AppSettingService>().appPath}/dl"');
      } catch (e) {
        await HelperToast.error('${e.toString()}');
        return;
      }

      await shell.run(
        '${Get.find<AppSettingService>().appPath}/dl $type -u "$url" -d "$dir" -o "$filename"',
        commandVerbose: true,
        verbose: true,
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
            AppLog.logD('code -> $code');
            if (code == 1) {
              downloadStdout.value = 'Download Failed 🔴';
              Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
              await HelperToast.error('Download Failed 🔴');
            }

            if (code == 0) {
              downloadStdout.value = 'Download Finished ✅';
              Get.find<HomeController>().footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
              await HelperToast.success('Download Finished ✅');
            }

            process.kill();
          });

          // listen stderr
          process.errLines.listen((s) => AppLog.logE('process.errLines e -> $s'));
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

  void killProcessDownload() {
    try {
      cProcessDownload.value?.kill(ProcessSignal.sigkill);
      cProcessDownload.value = null;
      downloadStdout.value = '';
      AppLog.logD('process killed');
    } catch (e) {
      AppLog.logD('killProcessDownload e -> $e');
    }
  }
}
