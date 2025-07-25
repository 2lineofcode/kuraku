import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:process_run/process_run.dart' as shell;
import 'package:process_run/stdio.dart';

import '../../../core/app_logging.dart';
import '../../../data/api/api_javit.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/__javit_search_entity.dart';
import '../../../utils/helper_toast.dart';

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

      ExLoading.show(paddingSymmetric: 230);
      response.value = await api.search(s: s, lang: currentLang.value, page: currentPage.value);
      hasNextPage.value = response.value.hasNextPage ?? false;
      currentPage.value = response.value.page ?? 1;
      videos.value = response.value.result ?? [];
      fnSearch.requestFocus();
      ExLoading.dismiss();

      await scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    } catch (_) {}
  }

  Future<void> onNextPage() async {
    currentPage.value++;
    await onSearch(tecSearch.text);
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
    hasNextPage.value = false;
    videos.value = [];
    fnSearch.requestFocus();
  }

  // ~ Download ────────────────────────────────────────────────────────────────
  Future<void> openDialogDownload() async {
    final tecUrl = TextEditingController();
    final fnUrl = FocusNode();
    final tecFilename = TextEditingController();

    fnUrl.requestFocus();

    ExAlert.adaptive(
      title: Text('Download', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: VStack(
        [
          CupertinoTextField(
            controller: tecUrl,
            focusNode: fnUrl,
            placeholder: 'Url',
            style: TextStyle(fontSize: 12, color: Vx.white),
          ).pOnly(bottom: 12),
          CupertinoTextField(
            controller: tecFilename,
            placeholder: 'Filename',
            style: TextStyle(fontSize: 12, color: Vx.white),
          ).pOnly(bottom: 12),
          Text('* (NEW) Support HLS(.m3u8)', style: TextStyle(fontSize: 10)),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Start Download', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            await startProcessDownload('hls', tecUrl.text, tecFilename.text);
            Get.back();
          },
        ),
      ],
    );
  }

  Future<void> startProcessDownload(String type, String url, String filename) async {
    try {
      await shell.run(
        'dl $type -u "$url" -o "$filename"',
        commandVerbose: true,
        verbose: true,
        onProcess: (process) async {
          cProcessDownload.value = process;
          // listen stdout
          process.outLines.listen((s) {
            downloadStdout.value = s;
          }).onError((e) {
            AppLog.logE('listen stdout e -> $e');
            downloadStdout.value = '$e';
          });

          await process.exitCode.then((code) async {
            AppLog.logD('code -> $code');
            if (code == 1) {
              downloadStdout.value = 'Download Failed 🔴';
              await HelperToast.error('Download Failed 🔴');
            }

            if (code == 0) {
              downloadStdout.value = 'Download Finished ✅';
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
