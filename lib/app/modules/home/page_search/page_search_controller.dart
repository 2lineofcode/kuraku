import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../utils/helper_tabs.dart';
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
}
