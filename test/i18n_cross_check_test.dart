import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/home_view.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_tab.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_view.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_view.dart';
import 'package:kuraku/app/utils/chat_knowledge.dart';
import 'package:kuraku/app/utils/helper_misc.dart';
import 'package:kuraku/app/utils/local_semantic_worker.dart';

const _translated = {
  'FHD (1080p)': 'Localized full resolution',
  'HD (720p)': 'Localized lower resolution',
  'Idle | Total Video: @{value}': 'Total @{value} · resting',
  'Stopping… Saved results will be kept.': 'Keeping your progress',
  'Scan failed. Saved results are kept. Please retry.': 'Please try again',
  'Stopping…': 'Wait',
  'Image': 'Picture', 'Code': 'Identifier', 'Title': 'Caption', 'Actions': 'Options',
  'Preparing local runtime...': 'Preparing translated runtime',
  'image search model': 'translated image model',
  'Downloading @{resource}: @{amount}': '@{amount} · downloading @{resource}',
};

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  void onReady() {}
}

class _Tools extends PageToolsController {
  @override
  Future<void> onRefresh() async {}
}

class _Settings extends PageSettingsController {
  @override
  Future<void> onRefresh() async {}
  @override
  Future<void> onRefreshStorage() async {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations({...AppTranslations().keys, 'test': _translated});
    Get.locale = const Locale('test');
    Get.fallbackLocale = AppTranslations.fallbackLocale;
  });
  tearDown(() {
    Get.reset();
    Get.clearTranslations();
    Get.locale = null;
    Get.fallbackLocale = null;
  });

  test('Translated labels preserve filters, table data and worker progress', () {
    expect(HelperMisc.formatVideoQuality('1920x1080'), 'Localized full resolution');
    expect(HelperMisc.formatVideoQuality('1920x1080', localized: false), 'FHD (1080p)');
    final tab = PageSearchTab(0);
    addTearDown(tab.dispose);
    tab.showResults('Title', [
      Videos(id: 'fhd', title: 'Title', quality: '1920x1080'),
      Videos(id: 'hd', title: 'Title', quality: '1280x720'),
    ]);
    tab.onQualityFilterChange('FHD only');
    expect(tab.videos.map((video) => video.id), ['fhd']);
    tab.onQualityFilterChange('HD only');
    expect(tab.videos.map((video) => video.id), ['hd']);
    expect(tab.qualityFilter.value, 'HD only');
    final table = ChatKnowledge.render({
      'columns': ['video_code', 'title'], 'rows': [['ABP-001', 'Title']],
      'sources': ['library'], 'elapsed_ms': 1,
    });
    expect(table, contains('| Picture | Identifier | Caption | Options |'));
    expect(table, contains('| [ABP-001](kuraku-video:ABP-001) | Title |'));
    expect(table, contains('kuraku-similar:ABP-001'));
    expect(LocalSemanticWorker.translateSetupProgress('Preparing local runtime...'), 'Preparing translated runtime');
    expect(LocalSemanticWorker.translateSetupProgress('Downloading image search model: 20%'), '20% · downloading translated image model');
    expect(LocalSemanticWorker.translateSetupProgress('Downloading text search model: 7 MB'), '7 MB · downloading text search model');
    expect(LocalSemanticWorker.translateSetupProgress('Unknown worker output'), 'Unknown worker output');
  });

  testWidgets('Footer and scan controls use state independently of status wording', (tester) async {
    Get.put<AppSettingService>(AppSettingService()..pref = _Preferences());
    final home = Get.put<HomeController>(_Home());
    final tools = Get.put<PageToolsController>(_Tools());
    final settings = Get.put<PageSettingsController>(_Settings());
    home.totalVideo.value = 2;
    home.footerText.value = home.idleFooterText;
    home.footerStorageText.value = '50 GB available';
    tools.qualityScanRunning.value = true;
    tools.qualityScanStopping.value = true;
    tools.qualityScanStatus.value = 'Stopping… Saved results will be kept.'.tr;
    settings.semanticStatus.value = 'Localized success with no Finished prefix';
    settings.semanticStatusIsRoutine.value = true;
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('test'), fallbackLocale: AppTranslations.fallbackLocale,
      translations: AppTranslations(),
      home: Scaffold(body: Column(children: [
        const HomeView().footerStatusText(),
        const PageToolsView().buildResolutionScan(),
        const PageSettingsView().buildVisualSearchSettings(),
      ])),
    ));
    await tester.pump();
    expect(find.textContaining('Total 2 · resting', findRichText: true), findsOneWidget);
    expect(find.textContaining('50 GB available', findRichText: true), findsOneWidget);
    final stop = find.widgetWithText(TextButton, 'Wait');
    expect(stop, findsOneWidget);
    expect(tester.widget<TextButton>(stop).onPressed, isNull);
    expect(find.text(settings.semanticStatus.value), findsNothing);
    tools.qualityScanRunning.value = false;
    tools.qualityScanFailed.value = true;
    tools.qualityScanStatus.value = 'Scan failed. Saved results are kept. Please retry.'.tr;
    settings.semanticStatusIsRoutine.value = false;
    settings.semanticStatus.value = 'Localized warning';
    await tester.pump();
    expect(find.byTooltip('Please try again'), findsOneWidget);
    expect(find.text('Scan (0)'), findsOneWidget);
    expect(find.text('Localized warning'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
