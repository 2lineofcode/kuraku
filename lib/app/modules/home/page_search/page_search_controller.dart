import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_translations.dart';
import '../../../data/api/api_kuraku.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_tabs.dart';
import '../../../utils/helper_toast.dart';
import 'page_search_tab.dart';

class PageSearchController extends GetxController {
  final tabs = <PageSearchTab>[].obs;
  final activeTabIndex = 0.obs;
  final tabScrollController = ScrollController();
  int _nextTabId = 0;
  PageSearchTab get activeTab => tabs[activeTabIndex.value];

  @override
  void onInit() {
    super.onInit();
    final saved = AppPref.getSearchTabs();
    final entries = saved['tabs'];
    if (entries is List) {
      for (final entry in entries.whereType<Map<String, dynamic>>()) {
        final tab = createTab(_nextTabId++);
        tab.restorePreferences(entry);
        tab.watchPreferences(_saveTabs);
        tabs.add(tab);
        unawaited(tab.onSearch());
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
    unawaited(AppPref.setSearchTabs({
      'tabs': tabs.map((tab) => tab.toPreferences()).toList(),
      'activeTab': activeTabIndex.value,
    }).catchError((Object error) {
      AppLog.logW('Saving Search tabs failed: $error');
    }));
  }

  PageSearchTab createTab(int id) => PageSearchTab(id);

  void addTab({bool focusSearch = true}) {
    final tab = createTab(_nextTabId++);
    tab.watchPreferences(_saveTabs);
    tabs.add(tab);
    unawaited(tab.onRefresh());
    selectTab(tabs.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && !tab.isClosed && identical(activeTab, tab) && focusSearch) tab.fnSearch.requestFocus();
      if (!isClosed && tabScrollController.hasClients) tabScrollController.jumpTo(tabScrollController.position.maxScrollExtent);
    });
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeTabIndex.value = index;
    _saveTabs();
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

  Future<void> renewMetadata(Videos videos) async {
    await Overlayment.dismissLast();
    HelperLoading.show();

    final vidCode = HelperMisc.resolveVideoCode(videoCode: videos.videoCode, videoPath: videos.videoPath, title: videos.title);

    await ApiKuraku.getMetadata(code: vidCode).then((resp) async {
      HelperLoading.dismiss();
      final newVideos = videos;
      newVideos.videoCode = HelperMisc.resolveVideoCode(videoCode: resp.videoCode, title: vidCode);
      newVideos.title = resp.title;
      newVideos.titleJa = resp.titleJa;

      newVideos.description = resp.description;
      newVideos.fanArt = resp.fanArt?.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideos.poster = resp.poster?.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideos.trailer = resp.trailer;
      newVideos.site = 'R18';

      // ** only apply if actress is null
      if (videos.actress.isEmptyOrNull) {
        if (!resp.actress.isEmptyOrNull) {
          newVideos.actress = <VideoActress>[];
          for (var i = 0; i < resp.actress!.length; i++) {
            newVideos.actress?.add(VideoActress(
              id: resp.actress![i].castId,
              nameRomaji: resp.actress![i].castNames,
              imageUrl: resp.actress![i].castImage,
            ));
          }
        }
      }

      newVideos.category = <VideoCategory>[];
      if (resp.genre != null) {
        for (var i = 0; i < resp.genre!.length; i++) {
          newVideos.category?.add(VideoCategory(id: i, category: resp.genre![i]));
        }
      }

      newVideos.releaseDate = resp.releaseDate;
      newVideos.releaseDateFormated = resp.releaseDateFormated;
      newVideos.duration = resp.duration;
      newVideos.durationFormated = resp.durationFormated;

      newVideos.studio = resp.studio;
      newVideos.label = resp.label;
      newVideos.director = resp.director;
      newVideos.series = resp.series;

      newVideos.screenshot = <String>[];
      if (resp.screenshot != null) {
        for (var i = 0; i < resp.screenshot!.length; i++) {
          if (resp.screenshot![i].toString().contains('jp-')) {
            newVideos.screenshot?.add(resp.screenshot![i].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', ''));
          } else {
            newVideos.screenshot?.add(resp.screenshot![i].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '').replaceAll('-', 'jp-'));
          }
        }
      }

      await DBVideos.update(newVideos);
      await HelperToast.success('@{videoCode} metadata updated'.trNamed({'videoCode': '${newVideos.videoCode}'}));
    }).catchError((e) {
      HelperLoading.dismiss();
      HelperToast.error(e.toString());
      logE('renewMetadata error: $e');
    });
  }

}
