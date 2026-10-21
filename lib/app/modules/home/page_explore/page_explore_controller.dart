import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../utils/helper_tabs.dart';
import 'page_explore_tab.dart';

export 'page_explore_tab.dart';

class PageExploreController extends GetxController {
  final tabs = <PageExploreTab>[].obs;
  final activeTabIndex = 0.obs;
  final tabScrollController = ScrollController();
  int _nextTabId = 0;
  final _dirtyTabs = <int>{};
  late final _pins = AppPref.getExplorePins().toSet().obs;
  final _savingPin = false.obs;
  PageExploreTab get activeTab => tabs[activeTabIndex.value];

  @override
  void onInit() {
    super.onInit();
    final saved = AppPref.getExploreTabs();
    final entries = saved['tabs'];
    if (entries is List) {
      for (final entry in entries.whereType<Map<String, dynamic>>()) {
        final tab = createTab(_nextTabId++);
        tab.restorePreferences(entry);
        tabs.add(tab);
        _dirtyTabs.add(tab.id);
      }
    }
    for (final tab in tabs) {
      _watchTab(tab);
    }
    if (tabs.isEmpty) {
      addTab();
    } else {
      final active = saved['activeTab'];
      selectTab(active is int ? active.clamp(0, tabs.length - 1) : 0);
    }
  }

  void _saveTabs() {
    unawaited(AppPref.setExploreTabs({
      'tabs': tabs.map((tab) => tab.toPreferences()).toList(),
      'activeTab': activeTabIndex.value,
    }).catchError((Object error) {
      AppLog.logW('Saving Explore tabs failed: $error');
    }));
  }

  PageExploreTab createTab(int id) => PageExploreTab(id, pins: _pins, savingPin: _savingPin);

  void _watchTab(PageExploreTab tab) {
    tab.isActive = () => !isClosed && tabs.isNotEmpty && identical(activeTab, tab);
    tab.watchPreferences(_saveTabs);
  }

  static bool get isNewTabModifierPressed => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

  Future<void> openSelection(String menu, String name, {bool newTab = false}) {
    if (newTab) addTab();
    return activeTab.openSelection(menu, name);
  }

  void addTab() {
    final tab = createTab(_nextTabId++);
    _watchTab(tab);
    tabs.add(tab);
    _dirtyTabs.add(tab.id);
    selectTab(tabs.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && tabScrollController.hasClients) tabScrollController.jumpTo(tabScrollController.position.maxScrollExtent);
    });
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeTabIndex.value = index;
    _saveTabs();
    final tab = activeTab;
    if (_dirtyTabs.remove(tab.id)) unawaited(tab.onRefresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && !tab.isClosed && identical(activeTab, tab)) tab.fnSearchLeft.requestFocus();
    });
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
    tabScrollController.dispose();
    for (final tab in tabs) {
      tab.dispose();
    }
    super.onClose();
  }

}
