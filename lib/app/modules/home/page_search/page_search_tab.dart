import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/db_historical.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/local_semantic_worker.dart';
import '../../../utils/semantic_search_service.dart';
import '../local_video_selection.dart';

class PageSearchTab with LocalVideoSelection {
  PageSearchTab(this.id) {
    fnSearch.addListener(_onSearchFocusChanged);
  }

  final int id;
  final isPinned = false.obs;
  final title = 'New search'.obs;
  final error = ''.obs;
  final isLoading = false.obs;
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final scrollGridController = ScrollController();
  final isListView = false.obs;
  final isSearchMode = false.obs;
  final isSemanticMode = false.obs;
  final isSemanticBusy = false.obs;
  final historySuggestions = <String>[].obs;
  final selectedHistoryIndex = (-1).obs;
  int _historyRequest = 0;
  final phSearch = 'Video Code or Title or Path...'.tr.obs;
  final semanticResultLabel = ''.obs;
  final semanticCoverage = ''.obs;
  final visualSensitivity = 'Balanced'.obs;
  final semanticReasonByVideoId = <String, String>{}.obs;
  final semanticScoreByVideoId = <String, double>{}.obs;
  final sortBy = 'Random'.obs;
  final qualityFilter = 'All qualities'.obs;
  final filter = VideoFilterState();
  final videos = <Videos>[].obs;
  final allVideos = <Videos>[].obs;
  final isFresh = true.obs;
  int _request = 0;
  bool _closed = false;
  final _hasSort = false.obs;
  Worker? _preferenceWorker;
  int get searchRevision => _request;
  @override
  bool get isClosed => _closed;
  @override
  int get selectionRevision => searchRevision;
  @override
  Iterable<Videos> get selectionSource => videos;
  @override
  Future<void> refreshSelectionFiles() async { videos.refresh(); }

  Map<String, dynamic> toPreferences() => {
    'pinned': isPinned.value,
    'query': tecSearch.text,
    'listView': isListView.value,
    'semantic': isSemanticMode.value,
    'visualSensitivity': visualSensitivity.value,
    'sort': sortBy.value,
    'quality': qualityFilter.value,
    'hasSort': _hasSort.value,
    'filtered': filter.isFiltered.value,
    'videoCode': filter.tecVideoCode.text,
    'actress': filter.tecActressName.text,
    'categoryDraft': filter.tecCategory.text,
    'categories': filter.categoriesSelected.toList(),
    'yearStart': filter.currentRange.value.start,
    'yearEnd': filter.currentRange.value.end,
    'durationMin': filter.durationMin.value,
    'durationMax': filter.durationMax.value,
    'blacklist': filter.blacklistPreferences,
  };

  void restorePreferences(Map<String, dynamic> value) {
    isPinned.value = value['pinned'] == true;
    tecSearch.text = value['query'] is String ? value['query'] : '';
    isListView.value = value['listView'] == true;
    isSemanticMode.value = value['semantic'] == true;
    if (['Strict', 'Balanced', 'Broad'].contains(value['visualSensitivity'])) visualSensitivity.value = value['visualSensitivity'];
    _updatePlaceholder();
    if (['Relevance', 'Random', 'Release Date', 'View Count', 'File Size'].contains(value['sort'])) sortBy.value = value['sort'];
    _hasSort.value = value['hasSort'] == true;
    if (isSemanticMode.value && !_hasSort.value) sortBy.value = 'Relevance';
    if (['All qualities', 'FHD only', 'HD only'].contains(value['quality'])) qualityFilter.value = value['quality'];
    filter.isFiltered.value = value['filtered'] == true;
    filter.restoreBlacklist(value['blacklist']);
    filter.tecVideoCode.text = value['videoCode'] is String ? value['videoCode'] : '';
    filter.tecActressName.text = value['actress'] is String ? value['actress'] : '';
    filter.tecCategory.text = value['categoryDraft'] is String ? value['categoryDraft'] : '';
    if (value['categories'] is List) filter.categoriesSelected.assignAll((value['categories'] as List).whereType<String>().toSet());
    filter.durationMin.value = value['durationMin'] is int && value['durationMin'] >= 0 ? value['durationMin'] : null;
    filter.durationMax.value = value['durationMax'] is int && value['durationMax'] > 0 ? value['durationMax'] : null;
    if (filter.durationMin.value != null && filter.durationMax.value != null && filter.durationMin.value! > filter.durationMax.value!) {
      filter.durationMin.value = null;
      filter.durationMax.value = null;
    }
    final start = value['yearStart'];
    final end = value['yearEnd'];
    final year = DateTime.now().year.toDouble();
    if (start is num && end is num && start.isFinite && end.isFinite && start <= end) {
      filter.currentRange.value = RangeValues(start.toDouble().clamp(2000, year), end.toDouble().clamp(2000, year));
    }
  }

  void watchPreferences(VoidCallback onChanged) {
    for (final field in [tecSearch, filter.tecVideoCode, filter.tecActressName, filter.tecCategory]) {
      field.addListener(onChanged);
    }
    _preferenceWorker = everAll([
      isListView, isSemanticMode, visualSensitivity, sortBy, qualityFilter, _hasSort, filter.isFiltered, filter.categoriesSelected, filter.currentRange, filter.durationMin, filter.durationMax, filter.blacklist,
    ], (_) => onChanged());
  }

  void close() {
    LocalSemanticWorker.cancelRequests(this);
    selectedVideos.clear();
    _closed = true;
    _historyRequest++;
    _request++;
    _preferenceWorker?.dispose();
  }

  void dispose() {
    close();
    tecSearch.dispose();
    fnSearch.dispose();
    scrollGridController.dispose();
    filter.tecVideoCode.dispose();
    filter.tecActressName.dispose();
    filter.tecCategory.dispose();
  }

  Future<List<Videos>> loadVideos(String query) => query.isEmpty ? DBVideos.getAll() : DBVideos.search(query);
  Future<List<SemanticSearchHit>> loadSemanticResults(String query) {
    final request = _request;
    final minimum = visualSensitivity.value == 'Strict' ? .28 : visualSensitivity.value == 'Broad' ? .20 : .24;
    return SemanticSearchService.search(query, owner: this, minimum: minimum, onCoverage: (indexed, total) {
      if (_closed || request != _request) return;
      semanticCoverage.value = '@{indexed} of @{total} videos have a visual index@{metadata}'.trNamed({'indexed': '$indexed', 'total': '$total', 'metadata': '${indexed < total ? ' · Other matches use metadata'.tr : ''}'});
    });
  }

  Future<void> setVisualSensitivity(String value) async {
    if (_closed || !['Strict', 'Balanced', 'Broad'].contains(value)) return;
    visualSensitivity.value = value;
    await onSearch();
  }


  Future<List<String>> loadHistory(String query) => DBHistorical.search(kHistoricalTypeSearch, query);
  Future<void> saveHistory(String query) => DBHistorical.save(kHistoricalTypeSearch, query);
  Future<void> clearHistory() => DBHistorical.clear(kHistoricalTypeSearch);
  Future<void> deleteHistory(String query) => DBHistorical.delete(kHistoricalTypeSearch, query);

  Future<void> _recordHistory(String query) async {
    try {
      await saveHistory(query);
    } catch (e) {
      AppLog.logW('Saving Search history failed: $e');
    }
  }

  void _onSearchFocusChanged() {
    if (fnSearch.hasFocus) {
      unawaited(showHistory());
    } else {
      hideSuggestions();
    }
  }

  void hideSuggestions() {
    _historyRequest++;
    historySuggestions.clear();
    selectedHistoryIndex.value = -1;
  }

  Future<void> showHistory() async {
    if (_closed || !fnSearch.hasFocus) return;
    final query = tecSearch.text;
    if (query.trim().isEmpty) {
      hideSuggestions();
      return;
    }
    final request = ++_historyRequest;
    try {
      final items = await loadHistory(query);
      if (_closed || request != _historyRequest || !fnSearch.hasFocus || query != tecSearch.text) return;
      historySuggestions.assignAll(items);
      selectedHistoryIndex.value = -1;
    } catch (e) {
      AppLog.logW('Loading Search history failed: $e');
    }
  }

  Future<void> onPickHistory(String query) async {
    if (_closed) return;
    hideSuggestions();
    tecSearch.value = TextEditingValue(text: query, selection: TextSelection.collapsed(offset: query.length));
    await submitSearch();
  }

  Future<void> onClearHistory() async {
    if (_closed) return;
    try {
      await clearHistory();
      if (!_closed) hideSuggestions();
    } catch (e) {
      AppLog.logW('Clearing Search history failed: $e');
    }
  }

  Future<void> onDeleteHistory(String query) async {
    try {
      await deleteHistory(query);
      if (_closed) return;
      await showHistory();
    } catch (e) {
      AppLog.logW('Deleting Search history failed: $e');
    }
  }

  void onSearchTextChanged(String value) {
    if (_closed) return;
    hideSuggestions();
    unawaited(showHistory());
  }

  void onHistoryArrowDown() {
    if (historySuggestions.isNotEmpty) selectedHistoryIndex.value = (selectedHistoryIndex.value + 1) % historySuggestions.length;
  }

  void onHistoryArrowUp() {
    if (historySuggestions.isNotEmpty) selectedHistoryIndex.value = selectedHistoryIndex.value <= 0 ? historySuggestions.length - 1 : selectedHistoryIndex.value - 1;
  }

  Future<void> submitSearch() async {
    if (_closed) return;
    final index = selectedHistoryIndex.value;
    if (index >= 0 && index < historySuggestions.length) {
      final query = historySuggestions[index];
      tecSearch.value = TextEditingValue(text: query, selection: TextSelection.collapsed(offset: query.length));
    }
    hideSuggestions();
    final query = tecSearch.text.trim();
    if (query.isNotEmpty) unawaited(_recordHistory(query));
    await onSearch();
  }

  Future<void> onRefresh() => onSearch();

  void toggleViewMode() {
    if (_closed) return;
    if (scrollGridController.hasClients) scrollGridController.jumpTo(0);
    isListView.toggle();
  }

  Future<void> onReset() async {
    if (_closed) return;
    tecSearch.clear();
    sortBy.value = isSemanticMode.value ? 'Relevance' : 'Random';
    qualityFilter.value = 'All qualities';
    _hasSort.value = false;
    filter.reset();
    await onSearch();
  }

  Future<void> onSearch() async {
    if (_closed) return;
    hideSuggestions();
    LocalSemanticWorker.cancelRequests(this);
    final request = ++_request;
    final query = tecSearch.text.trim();
    final semantic = isSemanticMode.value && query.isNotEmpty;
    title.value = query.isEmpty ? 'New search' : query;
    isLoading.value = true;
    isSemanticBusy.value = semantic;
    error.value = '';
    semanticResultLabel.value = '';
    semanticScoreByVideoId.clear();
    semanticReasonByVideoId.clear();
    semanticCoverage.value = '';
    isSearchMode.value = query.isNotEmpty;
    selectedVideos.clear();
    videos.clear();
    allVideos.clear();

    try {
      final List<Videos> result;
      final scores = <String, double>{};
      final reasons = <String, String>{};
      if (semantic) {
        final hits = await loadSemanticResults(query);
        result = hits.map((hit) => hit.video).toList();
        for (final hit in hits) {
          final id = (hit.video.id ?? '').trim();
          if (id.isNotEmpty) { scores[id] = hit.score; reasons[id] = hit.reason; }
        }
      } else {
        result = await loadVideos(query);
      }
      if (_closed || request != _request) return;
      if (query.isEmpty) result.shuffle();
      isFresh.value = query.isEmpty && result.isEmpty;
      semanticScoreByVideoId.assignAll(scores);
      semanticReasonByVideoId.assignAll(reasons);
      semanticResultLabel.value = semantic ? 'Visual Search' : '';
      allVideos.assignAll(result);
      _applyView();
    } catch (e) {
      if (_closed || request != _request) return;
      error.value = e is SemanticSearchException ? e.message : 'Search failed. Please try again.'.tr;
      AppLog.logE('Local search failed: $e');
    } finally {
      if (!_closed && request == _request) {
        isLoading.value = false;
        isSemanticBusy.value = false;
      }
    }
  }

  void showResults(String query, List<Videos> result) {
    LocalSemanticWorker.cancelRequests(this);
    if (_closed) return;
    selectedVideos.clear();
    hideSuggestions();
    _request++;
    tecSearch.text = query;
    title.value = query;
    filter.reset();
    sortBy.value = 'Random';
    qualityFilter.value = 'All qualities';
    _hasSort.value = false;
    isSemanticMode.value = false;
    _updatePlaceholder();
    isSemanticBusy.value = false;
    isLoading.value = false;
    error.value = '';
    semanticResultLabel.value = '';
    semanticScoreByVideoId.clear();
    semanticReasonByVideoId.clear();
    semanticCoverage.value = '';
    isFresh.value = false;
    isSearchMode.value = true;
    allVideos.assignAll(result);
    videos.assignAll(result);
  }

  Future<void> toggleSemanticMode() async {
    isSemanticMode.toggle();
    sortBy.value = isSemanticMode.value ? 'Relevance' : 'Random';
    _hasSort.value = false;
    _updatePlaceholder();
    await onSearch();
  }

  Future<void> onSortByChange(String value) async {
    if (_closed) return;
    sortBy.value = value;
    _hasSort.value = true;
    _applyView();
    fnSearch.requestFocus();
  }

  void onQualityFilterChange(String value) {
    if (_closed || !['All qualities', 'FHD only', 'HD only'].contains(value)) return;
    qualityFilter.value = value;
    _applyView();
  }

  void _applyView() {
    final next = filter.isFiltered.value ? filter.apply(allVideos.toList(), _filterAdapter) : allVideos.toList();
    if (qualityFilter.value != 'All qualities') {
      final prefix = qualityFilter.value == 'FHD only' ? 'FHD' : 'HD';
      next.removeWhere((video) => !HelperMisc.formatVideoQuality(video.quality ?? '', localized: false).startsWith(prefix));
    }
    if (_hasSort.value) {
      switch (sortBy.value.toLowerCase()) {
        case 'relevance': break;
        case 'random': next.shuffle(); break;
        case 'release date':
          next.removeWhere((video) => (video.videoCode ?? '').isEmpty);
          next.sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
          break;
        case 'view count': next.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0)); break;
        case 'file size': next.sort((a, b) => (b.filesize ?? 0).compareTo(a.filesize ?? 0)); break;
      }
    }
    selectedVideos.retainAll(next.toSet());
    videos.assignAll(next);
  }

  final _filterAdapter = VideoFilterAdapter<Videos>(
    videoCode: (video) => video.videoCode ?? '',
    title: (video) => video.title,
    actresses: (video) => (video.actress ?? []).map((actress) => actress.nameRomaji ?? ''),
    categories: (video) => (video.category ?? []).map((category) => category.category ?? ''),
    releaseDate: (video) => video.releaseDate,
    durationMinutes: (video) => video.duration,
  );

  Future<void> openDialogFilter({bool Function()? isAvailable}) async {
    final request = _request;
    await HelperOpener.openFilterDialog<Videos>(
      state: filter,
      allVideos: allVideos.toList(),
      videos: videos,
      adapter: _filterAdapter,
      applyLocalFilter: false,
      isAvailable: () => !_closed && request == _request && (isAvailable?.call() ?? true),
      onApplied: (_) async { if (!_closed && request == _request) _applyView(); },
      onReset: () async { if (!_closed && request == _request) _applyView(); },
    );
  }

  void _updatePlaceholder() {
    phSearch.value = isSemanticMode.value ? 'Visual Search... e.g. a bright room, outdoors'.tr : 'Video Code or Title or Path...'.tr;
  }
}
