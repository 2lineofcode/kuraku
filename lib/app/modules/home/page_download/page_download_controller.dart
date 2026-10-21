import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_dependencies.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_notification.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_setting.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/_init_db.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/models/activity_entity.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_tabs.dart';
import '../home_controller.dart';
import 'page_download_dialog.dart';
import 'page_download_job.dart';
import 'page_download_search_tab.dart';

class PageDownloadController extends GetxController {
  final tabs = <PageDownloadSearchTab>[].obs;
  final activeTabIndex = 0.obs;
  final tabScrollController = ScrollController();
  int _nextTabId = 0;
  final _dirtyTabs = <int>{};
  PageDownloadSearchTab get activeTab => tabs[activeTabIndex.value];

  final downloadStdout = ''.obs;
  final currentProcessDownload = Rx<Process?>(null);
  final appSetting = Get.find<AppSettingService>();

  @override
  void onInit() {
    super.onInit();
    final options = AppPref.getDownloadOptions();
    for (final entry in _downloadOptionFields.entries) {
      final value = options[entry.key];
      if (value is String || value is num) entry.value.text = '$value';
      entry.value.addListener(_scheduleDownloadPreferenceSave);
    }
    if (['extract', 'auto', 'hls', 'file', 'youtube'].contains(options['mode'])) mode.value = options['mode'];
    headless.value = options['headless'] == true;
    allowPopups.value = options['allow_popups'] == true;
    _downloadPreferenceWorker = everAll([mode, headless, allowPopups], (_) => _scheduleDownloadPreferenceSave());
    final saved = AppPref.getDownloadTabs();
    final entries = saved['tabs'];
    if (entries is List) {
      for (final entry in entries.whereType<Map<String, dynamic>>()) {
        final tab = createTab(_nextTabId++);
        tab.restorePreferences(entry);
        tab.watchPreferences(_saveTabs);
        tabs.add(tab);
        _dirtyTabs.add(tab.id);
      }
    }
    if (tabs.isEmpty) {
      addTab(focusSearch: false);
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

  void addTab({bool focusSearch = true}) {
    final tab = createTab(_nextTabId++);
    tab.watchPreferences(_saveTabs);
    tabs.add(tab);
    selectTab(tabs.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && !tab.isClosed && identical(activeTab, tab) && focusSearch) tab.fnSearch.requestFocus();
      if (!isClosed && tabScrollController.hasClients) tabScrollController.jumpTo(tabScrollController.position.maxScrollExtent);
    });
  }

  Future<void> openResultRows(String title, List<Map<String, dynamic>> rows) async {
    if (isClosed || rows.isEmpty) return;
    addTab(focusSearch: false);
    await activeTab.showResultRows(title, rows);
    if (!isClosed) _saveTabs();
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeTabIndex.value = index;
    _saveTabs();
    final tab = activeTab;
    if (_dirtyTabs.remove(tab.id)) unawaited(tab.onRefresh());
  }

  void reorderTab(int oldIndex, int newIndex) {
    activeTabIndex.value = moveTab(tabs, activeTabIndex.value, oldIndex, newIndex, (tab) => tab.isPinned.value);
    _saveTabs();
  }

  void toggleTabPin(int index) {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];
    tab.isPinned.toggle();
    final destination = tabs.where((tab) => tab.isPinned.value).length - (tab.isPinned.value ? 1 : 0);
    activeTabIndex.value = moveTab(tabs, activeTabIndex.value, index, destination, (tab) => tab.isPinned.value);
    _saveTabs();
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length || tabs[index].isPinned.value) return;
    final tab = tabs.removeAt(index);
    _dirtyTabs.remove(tab.id);
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
    _dirtyTabs.addAll(tabs.map((tab) => tab.id));
    if (tabs.isEmpty) return;
    _dirtyTabs.remove(activeTab.id);
    await activeTab.onRefresh();
  }

  @override
  void onClose() {
    _saveTabs();
    _downloadPreferenceTimer?.cancel();
    _downloadPreferenceWorker?.dispose();
    unawaited(_saveDownloadPreferences());
    job.cancel();
    for (final field in [tecUrl, tecDirectory, tecFilename, tecConcurrency, tecRetries, tecTimeout, tecReferer, tecUserAgent, tecCaptureDuration, tecPlaySelector]) {
      field.dispose();
    }
    fnDownloadUrl.dispose();
    tabScrollController.dispose();
    for (final tab in tabs) {
      tab.dispose();
    }
    super.onClose();
  }

  bool _downloadDialogOpen = false;
  bool _historyDialogOpen = false;
  final jobRevision = 0.obs;
  late final PageDownloadJob job = PageDownloadJob(onChanged: () {
    if (isClosed) return;
    jobRevision.value++;
    downloadStdout.value = job.status == 'Ready' ? '' : job.running && job.progressText.isNotEmpty ? job.progressText : job.status.tr;
    currentProcessDownload.value = job.process;
    if (Get.isRegistered<HomeController>() && downloadStdout.value.isNotEmpty) Get.find<HomeController>().footerText.value = downloadStdout.value;
  });
  final history = <Activity>[].obs;
  final formError = ''.obs;
  final mode = 'extract'.obs;
  final headless = false.obs;
  final allowPopups = false.obs;
  final tecUrl = TextEditingController();
  final tecDirectory = TextEditingController(text: AppPref.getDownloadPath());
  final tecFilename = TextEditingController();
  final tecConcurrency = TextEditingController(text: AppPref.getDownloadWorker().clamp(1, 64).toString());
  final tecRetries = TextEditingController(text: '3');
  final tecTimeout = TextEditingController(text: '30');
  final tecReferer = TextEditingController();
  final tecUserAgent = TextEditingController();
  final tecCaptureDuration = TextEditingController(text: '20');
  final tecPlaySelector = TextEditingController();
  final fnDownloadUrl = FocusNode();

  Timer? _downloadPreferenceTimer;
  Worker? _downloadPreferenceWorker;
  late final _downloadOptionFields = <String, TextEditingController>{
    'directory': tecDirectory, 'concurrency': tecConcurrency, 'retries': tecRetries,
    'timeout': tecTimeout, 'referer': tecReferer, 'user_agent': tecUserAgent,
    'capture_duration': tecCaptureDuration, 'play_selector': tecPlaySelector,
  };

  void _scheduleDownloadPreferenceSave() {
    _downloadPreferenceTimer?.cancel();
    _downloadPreferenceTimer = Timer(const Duration(milliseconds: 250), () => unawaited(_saveDownloadPreferences()));
  }

  Future<void> _saveDownloadPreferences() => AppPref.setDownloadOptions({
    for (final entry in _downloadOptionFields.entries) entry.key: entry.value.text,
    'mode': mode.value, 'headless': headless.value, 'allow_popups': allowPopups.value,
  }).catchError((Object error) {
    AppLog.logW('Saving download options failed: $error');
  });

  void clearCompletedDownload() {
    if (job.running || job.status != 'Completed') return;
    tecUrl.clear();
    tecFilename.clear();
    formError.value = '';
    job.reset();
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.isRegistered<DBService>()) unawaited(loadDownloadHistory());
  }

  Future<void> openDialogDownload() async {
    if (_downloadDialogOpen || isClosed) return;
    _downloadDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && _downloadDialogOpen && !job.running) fnDownloadUrl.requestFocus();
    });
    try {
      await Get.dialog<void>(PageDownloadDialog(controller: this));
    } finally {
      _downloadDialogOpen = false;
    }
  }

  void downloadWebsite(String url) {
    if (isClosed) return;
    if (job.running) {
      formError.value = 'A download is already active. Cancel it before starting another.'.tr;
      unawaited(openDialogDownload());
      return;
    }
    mode.value = 'extract';
    tecUrl.text = url;
    tecFilename.clear();
    formError.value = '';
    unawaited(openDialogDownload());
    unawaited(startDownload());
  }

  Future<void> openDownloadLog() async {
    if (_historyDialogOpen || isClosed) return;
    _historyDialogOpen = true;
    try {
      await loadDownloadHistory();
      if (!isClosed) await Get.dialog<void>(PageDownloadHistoryDialog(controller: this));
    } finally {
      _historyDialogOpen = false;
    }
  }

  Future<void> loadDownloadHistory() async {
    try {
      history.assignAll(await DBActivity.getDownloadLogs());
    } catch (e) {
      AppLog.logW('Loading download history failed: $e');
    }
  }

  Future<void> pickDownloadDirectory() async {
    final directory = await FilePicker.getDirectoryPath(initialDirectory: tecDirectory.text.isEmpty ? null : tecDirectory.text);
    if (directory == null || isClosed) return;
    tecDirectory.text = directory;
    AppPref.setDownloadPath(directory);
  }

  DownloadRequest requestFromForm() => DownloadRequest(
    url: tecUrl.text.trim(), directory: tecDirectory.text.trim(), filename: tecFilename.text.trim(), mode: mode.value,
    concurrency: int.tryParse(tecConcurrency.text) ?? 0, retries: int.tryParse(tecRetries.text) ?? -1,
    timeout: int.tryParse(tecTimeout.text) ?? 0, referer: tecReferer.text.trim(), userAgent: tecUserAgent.text.trim(),
    headless: headless.value, captureDuration: int.tryParse(tecCaptureDuration.text) ?? 0,
    playSelector: tecPlaySelector.text.trim(), allowPopups: allowPopups.value,
  );

  Future<void> startDownload() async {
    if (job.running) return;
    final request = requestFromForm();
    formError.value = '';
    try {
      request.validate();
      AppPref.setDownloadPath(request.directory);
      AppPref.setDownloadWorker(request.concurrency);
    } catch (e) {
      formError.value = '$e';
      return;
    }
    Activity? activity;
    String? completedOutput;
    // Reserve the job while preparing the binary and history entry.
    job.cancelled = false;
    job.outputPath = job.error = '';
    job.status = 'Starting';
    job.running = true;
    jobRevision.value++;
    try {
      final downloader = await AppDependencies.shared.downloader(appSetting.bundledAssetsPath);
      if (!downloader.ready) throw StateError(downloader.message);
      final binary = downloader.executable!;
      if (request.mode == 'extract') {
        final browser = await AppDependencies.shared.browser();
        if (!browser.ready) throw StateError(browser.message);
      }
      if (request.mode == 'hls' || request.mode == 'youtube') await AppDependencies.shared.requireTool('ffmpeg');
      if (request.mode == 'youtube') await AppDependencies.shared.requireTool('yt-dlp');
      if (job.cancelled || isClosed) {
        job.status = 'Cancelled';
        return;
      }
      activity = await DBActivity.addDownloadLog(Activity(content: _downloadContent(request, 'start')));
      if (job.cancelled || isClosed) {
        job.status = 'Cancelled';
        if (activity?.id != null) await DBActivity.updateDownloadLog(id: activity!.id!, content: _downloadContent(request, 'cancelled'));
        return;
      }
      job.running = false;
      await job.start(request, binary: binary, cache: p.join(appSetting.appPath, '.dl_tmp'), environment: {
        if (Platform.isMacOS) 'PATH': '/opt/homebrew/bin:/usr/local/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin:/usr/sbin:/sbin'}',
      });
      if (job.status == 'Completed') completedOutput = job.outputPath;
      if (activity?.id != null) {
        try {
          await DBActivity.updateDownloadLog(id: activity!.id!, content: _downloadContent(request, job.status == 'Completed' ? 'finish' : job.status == 'Cancelled' ? 'cancelled' : 'failed'));
        } catch (e) {
          formError.value = 'Download result: @{status}. Saving history failed: @{error}'.trNamed({'status': job.status.tr, 'error': '$e'});
          AppLog.logW(formError.value);
        }
      }
    } catch (e) {
      job.status = 'Failed';
      job.error = '$e';
      if (activity?.id != null) {
        try {
          await DBActivity.updateDownloadLog(id: activity!.id!, content: _downloadContent(request, 'failed'));
        } catch (historyError) {
          AppLog.logW('Saving download result failed: $historyError');
        }
      }
    } finally {
      job.running = false;
      currentProcessDownload.value = null;
      if (!isClosed) clearCompletedDownload();
      jobRevision.value++;
      await loadDownloadHistory();
      if (!job.running && Get.isRegistered<HomeController>()) await Get.find<HomeController>().updateFooterSummary();
    }
    if (completedOutput != null) {
      try {
        await HelperMisc.playSoundDownloadComplate();
        await AppNotification.show(NotificationModel(title: p.basename(completedOutput), body: 'Download finished'.tr, payload: completedOutput));
      } catch (e) {
        AppLog.logW('Download notification failed: $e');
      }
    }
  }

  String _downloadContent(DownloadRequest request, String status) => jsonEncode({
    'ev': status, 'url': request.url, 'dir': request.directory, 'filename': request.filename,
    'mode': request.mode, 'output_path': job.outputPath, 'error': job.error, 'exit_code': job.exitCode,
    'concurrency': request.concurrency, 'retries': request.retries, 'timeout': request.timeout,
    'referer': request.referer, 'user_agent': request.userAgent, 'headless': request.headless,
    'capture_duration': request.captureDuration, 'play_selector': request.playSelector, 'allow_popups': request.allowPopups,
  });

  Map<String, dynamic> historyContent(Activity activity) {
    try {
      final value = jsonDecode(activity.content ?? '{}');
      return value is Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }

  void restoreDownload(Activity activity) {
    if (job.running) return;
    final data = historyContent(activity);
    tecUrl.text = data['url'] as String? ?? '';
    tecDirectory.text = data['dir'] as String? ?? '';
    tecFilename.text = data['filename'] as String? ?? '';
    mode.value = data['mode'] as String? ?? 'extract';
    tecConcurrency.text = '${data['concurrency'] ?? 8}';
    tecRetries.text = '${data['retries'] ?? 3}';
    tecTimeout.text = '${data['timeout'] ?? 30}';
    tecReferer.text = data['referer'] as String? ?? '';
    tecUserAgent.text = data['user_agent'] as String? ?? '';
    headless.value = data['headless'] == true;
    allowPopups.value = data['allow_popups'] == true;
    tecCaptureDuration.text = '${data['capture_duration'] ?? 20}';
    tecPlaySelector.text = data['play_selector'] as String? ?? '';
    formError.value = '';
  }

  Future<void> revealOutput(String path) async {
    if (path.isEmpty) return;
    if (Platform.isMacOS) await Process.run('/usr/bin/open', ['-R', path]);
    else if (Platform.isWindows) await Process.run('explorer.exe', ['/select,', path]);
    else await Process.run('xdg-open', [p.dirname(path)]);
  }

  Future<void> deleteDownloadHistory(Activity activity) async {
    await DBActivity.deleteAll(where: 'id = ? AND type = ?', whereArgs: [activity.id, kActivityTypeDownload]);
    await loadDownloadHistory();
  }

  Future<void> killProcessDownload() async => job.cancel();
}
