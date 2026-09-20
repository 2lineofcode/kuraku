import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_logging.dart';
import '../../../data/database/db_historical.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../../../utils/semantic_search_service.dart';
import '../../player/player_multi_view.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_playlist.dart';

class PageSearchTab {
  PageSearchTab(this.id) {
    fnSearch.addListener(_onSearchFocusChanged);
  }

  final int id;
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
  final phSearch = 'Video Code or Title or Path...'.obs;
  final semanticResultLabel = ''.obs;
  final semanticScoreByVideoId = <String, double>{}.obs;
  final sortBy = 'Random'.obs;
  final qualityFilter = 'All qualities'.obs;
  final filter = VideoFilterState();
  final videos = <Videos>[].obs;
  final selectedVideos = <Videos>{}.obs;
  final allVideos = <Videos>[].obs;
  final isFresh = true.obs;
  int _request = 0;
  bool _closed = false;
  final _hasSort = false.obs;
  Worker? _preferenceWorker;
  int get searchRevision => _request;
  bool get isClosed => _closed;

  void toggleSelection(Videos video) {
    if (_closed || !videos.contains(video)) return;
    if (!selectedVideos.remove(video)) selectedVideos.add(video);
  }

  Future<void> performSelectionAction(String action, List<Videos> selected) async {
    if (_closed || selected.isEmpty) return;
    switch (action) {
      case 'play':
        await HelperOpener.openVideoFile(selected.first, playlist: selected);
        break;
      case 'playMulti':
        await Get.to(() => const PlayerMultiView(), arguments: selected);
        break;
      case 'cart':
        final home = Get.find<HomeController>();
        for (final video in selected) { home.addToCart(video); }
        await HelperToast.success('Selected videos are in cart');
        break;
      case 'playlist':
        await HomePanelPlaylist.showDialogAddToPlaylistItem(selected);
        break;
      case 'favorite':
        for (final video in selected) { await DBVideos.addToFavorite(video); }
        await HelperToast.success('Added ${selected.length} video(s) to favorite');
        break;
    }
  }

  Future<void> applyFileMoves(Map<String, Videos> files, Map<String, String> paths, List<String> missing) async {
    if (paths.isEmpty && missing.isEmpty) return;
    final libraries = await DBLibrary.getAll();
    final roots = libraries.map((library) => library.rootFolder ?? '').where((root) => root.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final moves = <Map<String, String>>[];
    for (final entry in paths.entries) {
      final existing = await DBVideos.getByVideoPath(entry.value);
      if (existing != null && existing.id != files[entry.key]?.id) {
        throw StateError('The destination is already in the library: ${entry.value}');
      }
      moves.add({
        'oldPath': entry.key,
        'newPath': entry.value,
        'newRoot': roots.firstWhere((root) => p.isWithin(root, entry.value), orElse: () => p.dirname(entry.value)),
      });
    }
    await DBVideos.moveVideoPaths(moves);
    for (final move in moves) {
      final video = files[move['oldPath']]!;
      video.videoPath = move['newPath'];
      video.rootPath = move['newRoot'];
    }
    for (final library in libraries) {
      final previous = library.videos ?? <String>[];
      final next = previous.where((path) => !paths.containsKey(path) && !missing.contains(path)).toSet();
      next.addAll(moves.where((move) => move['newRoot'] == library.rootFolder).map((move) => move['newPath']!));
      if (next.length == previous.length && next.containsAll(previous)) continue;
      library.videos = next.toList();
      library.totalVideo = next.length;
      await DBLibrary.update(library);
    }
    if (!_closed) videos.refresh();
  }

  Map<String, dynamic> toPreferences() => {
    'query': tecSearch.text,
    'listView': isListView.value,
    'semantic': isSemanticMode.value,
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
  };

  void restorePreferences(Map<String, dynamic> value) {
    tecSearch.text = value['query'] is String ? value['query'] : '';
    isListView.value = value['listView'] == true;
    isSemanticMode.value = value['semantic'] == true;
    _updatePlaceholder();
    if (['Random', 'Release Date', 'View Count', 'File Size'].contains(value['sort'])) sortBy.value = value['sort'];
    _hasSort.value = value['hasSort'] == true;
    if (['All qualities', 'FHD only', 'HD only'].contains(value['quality'])) qualityFilter.value = value['quality'];
    filter.isFiltered.value = value['filtered'] == true;
    filter.tecVideoCode.text = value['videoCode'] is String ? value['videoCode'] : '';
    filter.tecActressName.text = value['actress'] is String ? value['actress'] : '';
    filter.tecCategory.text = value['categoryDraft'] is String ? value['categoryDraft'] : '';
    if (value['categories'] is List) filter.categoriesSelected.assignAll((value['categories'] as List).whereType<String>().toSet());
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
      isListView, isSemanticMode, sortBy, qualityFilter, _hasSort, filter.isFiltered, filter.categoriesSelected, filter.currentRange,
    ], (_) => onChanged());
  }

  void close() {
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
  Future<List<SemanticSearchHit>> loadSemanticResults(String query) => SemanticSearchService.search(query);

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
    sortBy.value = 'Random';
    qualityFilter.value = 'All qualities';
    _hasSort.value = false;
    filter.reset();
    await onSearch();
  }

  Future<void> onSearch() async {
    if (_closed) return;
    hideSuggestions();
    final request = ++_request;
    final query = tecSearch.text.trim();
    final semantic = isSemanticMode.value && query.isNotEmpty;
    title.value = query.isEmpty ? 'New search' : query;
    isLoading.value = true;
    isSemanticBusy.value = semantic;
    error.value = '';
    semanticResultLabel.value = '';
    semanticScoreByVideoId.clear();
    isSearchMode.value = query.isNotEmpty;
    selectedVideos.clear();
    videos.clear();
    allVideos.clear();

    try {
      final List<Videos> result;
      final scores = <String, double>{};
      if (semantic) {
        final hits = await loadSemanticResults(query);
        result = hits.map((hit) => hit.video).toList();
        for (final hit in hits) {
          final id = (hit.video.id ?? '').trim();
          if (id.isNotEmpty) scores[id] = hit.score;
        }
      } else {
        result = await loadVideos(query);
      }
      if (_closed || request != _request) return;
      if (query.isEmpty) result.shuffle();
      isFresh.value = query.isEmpty && result.isEmpty;
      semanticScoreByVideoId.assignAll(scores);
      semanticResultLabel.value = semantic ? 'AI Search' : '';
      allVideos.assignAll(result);
      _applyView();
    } catch (e) {
      if (_closed || request != _request) return;
      error.value = 'Search failed. Please try again.';
      AppLog.logE('Local search failed: $e');
    } finally {
      if (!_closed && request == _request) {
        isLoading.value = false;
        isSemanticBusy.value = false;
      }
    }
  }

  void showResults(String query, List<Videos> result) {
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
    isFresh.value = false;
    isSearchMode.value = true;
    allVideos.assignAll(result);
    videos.assignAll(result);
  }

  Future<void> toggleSemanticMode() async {
    isSemanticMode.toggle();
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
      next.removeWhere((video) => !HelperMisc.formatVideoQuality(video.quality ?? '').startsWith(prefix));
    }
    if (_hasSort.value) {
      switch (sortBy.value.toLowerCase()) {
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
    actresses: (video) => (video.actress ?? []).map((actress) => actress.nameRomaji ?? ''),
    categories: (video) => (video.category ?? []).map((category) => category.category ?? ''),
    releaseDate: (video) => video.releaseDate,
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
    phSearch.value = isSemanticMode.value ? 'Local AI Search... ex: subtitle indo outdoor' : 'Video Code or Title or Path...';
  }
}
