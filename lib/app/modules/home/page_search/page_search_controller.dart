import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_tabs.dart';
import 'page_search_tab.dart';

class PageSearchController extends GetxController {
  final tabs = <PageSearchTab>[].obs;
  final activeTabIndex = 0.obs;
  final tabScrollController = ScrollController();
  int _nextTabId = 0;
  final _dirtyTabs = <int>{};
  Future<List<Videos>>? _collection;
  (int, int) _collectionRevision = (-1, -1);
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
    unawaited(AppPref.setSearchTabs({
      'tabs': tabs.map((tab) => tab.toPreferences()).toList(),
      'activeTab': activeTabIndex.value,
    }).catchError((Object error) {
      AppLog.logW('Saving Search tabs failed: $error');
    }));
  }

  PageSearchTab createTab(int id) => PageSearchTab(id, loadCollection: loadCollection);

  Future<List<Videos>> loadCollection() async {
    final revision = (DBVideos.revision.value, DBVideos.viewCountRevision);
    if (_collectionRevision != revision) {
      _collection = null;
      _collectionRevision = revision;
    }
    final pending = _collection ??= DBVideos.getAll();
    try {
      return List<Videos>.of(await pending);
    } catch (_) {
      if (identical(_collection, pending)) _collection = null;
      rethrow;
    }
  }

  void addTab({bool focusSearch = true}) {
    final tab = createTab(_nextTabId++);
    tab.watchPreferences(_saveTabs);
    tabs.add(tab);
    _dirtyTabs.add(tab.id);
    selectTab(tabs.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && !tab.isClosed && identical(activeTab, tab) && focusSearch) tab.fnSearch.requestFocus();
      if (!isClosed && tabScrollController.hasClients) tabScrollController.jumpTo(tabScrollController.position.maxScrollExtent);
    });
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeTabIndex.value = index;
    if (_dirtyTabs.remove(activeTab.id)) unawaited(activeTab.onRefresh());
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
    _collection = null;
    _dirtyTabs.addAll(tabs.map((tab) => tab.id));
    if (tabs.isEmpty) return;
    _dirtyTabs.remove(activeTab.id);
    await activeTab.onRefresh();
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
}
