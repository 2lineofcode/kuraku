import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/chat_service.dart';
import 'page_sqleditor_tab.dart';

class PageSqleditorController extends GetxController {
  PageSqleditorController({required this.sources, this.loadSchema, this.query, this.createApi,
    Map<String, dynamic>? savedSnippets, Future<void> Function(Map<String, dynamic>)? persistSnippets,
    this.savedTabs = const {}, this.persistTabs}) : snippetStore = SqlSnippetStore(savedSnippets ?? {}, persistSnippets);

  final Map<String, String?> sources;
  final Future<Map<String, List<String>>> Function(String source)? loadSchema;
  final Future<Map<String, dynamic>> Function(String source, Map<String, dynamic> request, CancelToken token)? query;
  final ChatService Function()? createApi;
  final SqlSnippetStore snippetStore;
  final Map<String, dynamic> savedTabs;
  final Future<void> Function(Map<String, dynamic>)? persistTabs;
  final tabs = <PageSqleditorTab>[].obs;
  final activeTabIndex = 0.obs;
  final tabScrollController = ScrollController();
  final _sourceWorkers = <PageSqleditorTab, Worker>{};
  final saveError = ''.obs;
  int _nextTabId = 0;
  Timer? _saveTimer;
  Future<void> _pendingSave = Future.value();
  PageSqleditorTab get activeTab => tabs[activeTabIndex.value];

  @override
  void onInit() {
    super.onInit();
    final entries = savedTabs['tabs'];
    if (entries is List) {
      for (final entry in entries.whereType<Map>()) {
        tabs.add(_createTab(entry));
      }
    }
    if (tabs.isEmpty) tabs.add(_createTab({}));
    final active = savedTabs['activeTab'];
    activeTabIndex.value = active is int ? active.clamp(0, tabs.length - 1) : 0;
  }

  PageSqleditorTab _createTab(Map entry) {
    final tab = PageSqleditorTab(id: _nextTabId++, sources: sources, loadSchema: loadSchema,
      query: query, api: createApi?.call(), snippetStore: snippetStore);
    tab.restorePreferences(entry);
    tab.onStart();
    tab.input.addListener(_scheduleSave);
    tab.parameters.addListener(_scheduleSave);
    tab.aiPrompt.addListener(_scheduleSave);
    _sourceWorkers[tab] = ever(tab.source, (_) => _scheduleSave());
    return tab;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), saveTabs);
  }

  Future<void> saveTabs() {
    _saveTimer?.cancel();
    if (persistTabs == null) return Future.value();
    final value = {'tabs': tabs.map((tab) => tab.toPreferences()).toList(), 'activeTab': activeTabIndex.value};
    _pendingSave = _pendingSave.then((_) => persistTabs!(value)).then((_) { saveError.value = ''; }).catchError((Object _) {
      saveError.value = 'Could not save SQL tabs. Retry to keep your drafts.'.tr;
    });
    return _pendingSave;
  }

  void addTab() {
    tabs.add(_createTab({'source': activeTab.source.value}));
    selectTab(tabs.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && tabScrollController.hasClients) tabScrollController.jumpTo(tabScrollController.position.maxScrollExtent);
    });
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeTabIndex.value = index;
    unawaited(saveTabs());
    final tab = activeTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && !tab.isClosed && identical(activeTab, tab)) tab.focusNode.requestFocus();
    });
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];
    if (tab.committing.value) {
      tab.queryError.value = 'Wait for the write to finish before closing this tab.'.tr;
      return;
    }
    tab.stopQuery();
    tab.stopGeneration();
    tab.input.removeListener(_scheduleSave);
    tab.parameters.removeListener(_scheduleSave);
    tab.aiPrompt.removeListener(_scheduleSave);
    _sourceWorkers.remove(tab)?.dispose();
    tabs.removeAt(index);
    if (tabs.isEmpty) tabs.add(_createTab({}));
    final next = index < activeTabIndex.value ? activeTabIndex.value - 1 : activeTabIndex.value;
    selectTab(next.clamp(0, tabs.length - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.onDelete());
  }

  @override
  void onClose() {
    unawaited(saveTabs());
    _saveTimer?.cancel();
    tabScrollController.dispose();
    for (final worker in _sourceWorkers.values) {
      worker.dispose();
    }
    for (final tab in tabs) {
      tab.onDelete();
    }
    super.onClose();
  }
}
