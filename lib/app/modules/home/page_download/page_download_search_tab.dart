import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../data/api/api_javhey.dart';
import '../../../data/api/api_javmost.dart';
import '../../../data/database/db_historical.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/__javit_search_entity.dart';
import '../../../data/models/__javmost_new_release.dart';
import '../../../utils/helper_decensor.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_opener.dart';
import 'page_download_helper.dart';

typedef _DownloadQuery = ({
  String query,
  PageDownloadQueryRoute route,
  String? videoCode,
  String? actressName,
  List<String>? categories,
  int? yearStart,
  int? yearEnd,
  int? durationMin,
  int? durationMax,
  ActressMode actressMode,
  bool onlySeries,
});

class PageDownloadSearchTab {
  PageDownloadSearchTab(this.id) {
    scrollController.addListener(_onScroll);
    fnSearch.addListener(_onSearchFocusChanged);
  }

  final int id;
  final isPinned = false.obs;
  final title = 'New search'.obs;
  final error = ''.obs;
  int _searchRequest = 0;
  int get searchRevision => _searchRequest;
  _DownloadQuery? _query;
  bool _closed = false;
  bool get isClosed => _closed;
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearch = 'Video Code or Title...'.obs;
  final scrollController = ScrollController();
  final searchCommands = PageDownloadCommandEngine.commands.map((e) => e.value).toList(growable: false);
  final commandSuggestions = <PageDownloadCommand>[].obs;
  final isCommandSuggestionVisible = false.obs;
  final selectedCommandIndex = (-1).obs;
  final historySuggestions = <String>[].obs;
  final selectedHistoryIndex = (-1).obs;
  int _historyRequest = 0;

  final response = JavitSearch().obs;
  final hasNextPage = false.obs;
  final currentPage = 0.obs;
  final videos = <JavitSearchResult>[].obs;
  final allVideos = <JavitSearchResult>[].obs;
  final havingVideos = 0.obs;
  final havingOnly = false.obs;
  final totalResults = 0.obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;

  final filter = VideoFilterState();

  final _perPage = 200;
  String _lastQuery = '';
  Set<String> _existingVideoCodes = {};
  static const _defaultYearStart = 2000;
  Worker? _preferenceWorker;

  Map<String, dynamic> toPreferences() => {
    'pinned': isPinned.value,
    'query': tecSearch.text,
    'havingOnly': havingOnly.value,
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
    'filterActressMode': filter.actressMode.value.name,
    'onlySeries': filter.onlySeries.value,
  };

  void restorePreferences(Map<String, dynamic> value) {
    isPinned.value = value['pinned'] == true;
    tecSearch.text = value['query'] is String ? PageDownloadCommandEngine.normalizeQuery(value['query']) : '';
    havingOnly.value = value['havingOnly'] == true;
    filter.isFiltered.value = value['filtered'] == true;
    filter.restoreBlacklist(value['blacklist']);
    filter.actressMode.value = ActressMode.values.firstWhereOrNull((mode) => mode.name == value['filterActressMode']) ?? ActressMode.all;
    filter.onlySeries.value = value['onlySeries'] == true;
    if (filter.actressMode.value != ActressMode.all || filter.onlySeries.value) filter.isFiltered.value = true;
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

  Future<void> restoreSearch() async {
    _lastQuery = tecSearch.text.trim();
    if (_lastQuery.isEmpty && !_hasAnyFilter()) return;
    await _refreshSearchWithFilters(preserveHaving: true);
  }

  Future<void> onRefresh() async {
    if (_closed) return;
    _existingVideoCodes = {};
    if (_lastQuery.isEmpty && !_hasAnyFilter()) return;
    await _refreshSearchWithFilters(preserveHaving: true);
  }

  void watchPreferences(VoidCallback onChanged) {
    for (final field in [tecSearch, filter.tecVideoCode, filter.tecActressName, filter.tecCategory]) {
      field.addListener(onChanged);
    }
    _preferenceWorker = everAll([
      havingOnly, filter.isFiltered, filter.categoriesSelected, filter.currentRange, filter.durationMin, filter.durationMax, filter.blacklist, filter.actressMode, filter.onlySeries,
    ], (_) => onChanged());
  }

  void close() {
    _closed = true;
    _historyRequest++;
    _searchRequest++;
    _preferenceWorker?.dispose();
  }

  void dispose() {
    close();
    scrollController.dispose();
    tecSearch.dispose();
    fnSearch.dispose();
    filter.tecVideoCode.dispose();
    filter.tecActressName.dispose();
    filter.tecCategory.dispose();
  }

  Future<void> onSearch(String s) async {
    if (_closed) return;
    hideSuggestions();
    _lastQuery = PageDownloadCommandEngine.normalizeQuery(s);
    if (_lastQuery != s.trim()) tecSearch.text = _lastQuery;
    if (_lastQuery.isNotEmpty && _lastQuery != '/search') unawaited(_recordHistory(_lastQuery));
    await _refreshSearchWithFilters();
  }

  Future<List<String>> loadHistory(String query) => DBHistorical.search(kHistoricalTypeDownload, query);
  Future<void> saveHistory(String query) => DBHistorical.save(kHistoricalTypeDownload, query);
  Future<void> clearHistory() => DBHistorical.clear(kHistoricalTypeDownload);
  Future<void> deleteHistory(String query) => DBHistorical.delete(kHistoricalTypeDownload, query);

  Future<void> _recordHistory(String query) async {
    try {
      await saveHistory(query);
    } catch (e) {
      AppLog.logW('Saving Download history failed: $e');
    }
  }

  void _onSearchFocusChanged() {
    if (fnSearch.hasFocus) {
      unawaited(showHistory());
    } else {
      hideSuggestions();
    }
  }

  void _hideHistorySuggestions() {
    _historyRequest++;
    historySuggestions.clear();
    selectedHistoryIndex.value = -1;
  }

  void hideSuggestions() {
    _hideCommandSuggestions();
    _hideHistorySuggestions();
  }

  Future<void> showHistory() async {
    if (_closed || !fnSearch.hasFocus || isCommandSuggestionVisible.value) return;
    final query = tecSearch.text;
    if (query.trim().isEmpty) {
      _hideHistorySuggestions();
      return;
    }
    if (PageDownloadCommandEngine.byPrefix(query).isNotEmpty) {
      if (query == query.trimRight()) onSearchTextChanged(query);
      return;
    }
    final request = ++_historyRequest;
    try {
      final items = await loadHistory(query);
      if (_closed || request != _historyRequest || !fnSearch.hasFocus || query != tecSearch.text) return;
      historySuggestions.assignAll(items);
      selectedHistoryIndex.value = -1;
    } catch (e) {
      AppLog.logW('Loading Download history failed: $e');
    }
  }

  Future<void> onPickHistory(String query) async {
    if (_closed) return;
    tecSearch.value = TextEditingValue(text: query, selection: TextSelection.collapsed(offset: query.length));
    await onSearch(query);
  }

  Future<void> onClearHistory() async {
    if (_closed) return;
    try {
      await clearHistory();
      if (!_closed) _hideHistorySuggestions();
    } catch (e) {
      AppLog.logW('Clearing Download history failed: $e');
    }
  }

  Future<void> onDeleteHistory(String query) async {
    try {
      await deleteHistory(query);
      if (_closed) return;
      await showHistory();
    } catch (e) {
      AppLog.logW('Deleting Download history failed: $e');
    }
  }

  Future<void> onReset() async {
    if (_closed) return;
    _searchRequest++;
    _query = null;
    title.value = 'New search';
    error.value = '';
    response.value = JavitSearch();
    currentPage.value = 0;
    hasNextPage.value = false;
    videos.value = [];
    allVideos.value = [];
    havingVideos.value = 0;
    havingOnly.value = false;
    totalResults.value = 0;
    tecSearch.text = '';
    fnSearch.requestFocus();
    filter.reset();
    _lastQuery = '';
    _existingVideoCodes = {};
    isLoading.value = false;
    isLoadingMore.value = false;
    hideSuggestions();
  }

  void onSearchTextChanged(String s) {
    if (_closed) return;
    _hideHistorySuggestions();
    final value = s.trim();
    if (value.startsWith('/')) {
      commandSuggestions.value = PageDownloadCommandEngine.byPrefix(value);
      isCommandSuggestionVisible.value = commandSuggestions.isNotEmpty;
      selectedCommandIndex.value = commandSuggestions.isEmpty ? -1 : 0;
      if (isCommandSuggestionVisible.value) return;
    }

    _hideCommandSuggestions();
    unawaited(showHistory());
  }

  Future<void> onPickSearchCommand(String command) async {
    if (_closed) return;
    hideSuggestions();
    if (command == '/search') {
      tecSearch.text = '/search ';
      tecSearch.selection = TextSelection.fromPosition(TextPosition(offset: tecSearch.text.length));
      _hideCommandSuggestions();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_closed && fnSearch.context != null && ModalRoute.of(fnSearch.context!)?.isCurrent != false) {
          fnSearch.requestFocus();
        }
      });
      return;
    }

    tecSearch.text = command;
    tecSearch.selection = TextSelection.fromPosition(TextPosition(offset: command.length));
    await onSearch(command);
  }

  void _hideCommandSuggestions() {
    isCommandSuggestionVisible.value = false;
    selectedCommandIndex.value = -1;
    commandSuggestions.clear();
  }

  void onCommandArrowDown() {
    if (isCommandSuggestionVisible.isFalse || commandSuggestions.isEmpty) {
      if (historySuggestions.isNotEmpty) selectedHistoryIndex.value = (selectedHistoryIndex.value + 1) % historySuggestions.length;
      return;
    }
    selectedCommandIndex.value = (selectedCommandIndex.value + 1) % commandSuggestions.length;
  }

  void onCommandArrowUp() {
    if (isCommandSuggestionVisible.isFalse || commandSuggestions.isEmpty) {
      if (historySuggestions.isNotEmpty) selectedHistoryIndex.value = selectedHistoryIndex.value <= 0 ? historySuggestions.length - 1 : selectedHistoryIndex.value - 1;
      return;
    }
    selectedCommandIndex.value = (selectedCommandIndex.value - 1 + commandSuggestions.length) % commandSuggestions.length;
  }

  Future<void> onCommandEnterOrSearch(String input) async {
    final idx = selectedCommandIndex.value;
    if (isCommandSuggestionVisible.isTrue && idx >= 0 && idx < commandSuggestions.length) {
      await onPickSearchCommand(commandSuggestions[idx].value);
      return;
    }
    final historyIndex = selectedHistoryIndex.value;
    if (historyIndex >= 0 && historyIndex < historySuggestions.length) {
      await onPickHistory(historySuggestions[historyIndex]);
      return;
    }
    await onSearch(input.trim());
  }

  bool get _hasCustomYearRange {
    final startYear = filter.currentRange.value.start.toInt();
    final endYear = filter.currentRange.value.end.toInt();
    final currentYear = DateTime.now().year;
    return startYear > _defaultYearStart || endYear < currentYear;
  }

  String? _filterVideoCode() {
    final value = filter.tecVideoCode.text.trim();
    return value.isEmpty ? null : value;
  }

  String? _filterActressName() {
    final value = filter.tecActressName.text.trim();
    return value.isEmpty ? null : value;
  }

  List<String>? _filterCategories() {
    return filter.categoriesSelected.isEmpty ? null : filter.categoriesSelected.toList();
  }

  int? _filterYearStart() {
    if (_hasCustomYearRange == false) return null;
    return filter.currentRange.value.start.toInt();
  }

  int? _filterYearEnd() {
    if (_hasCustomYearRange == false) return null;
    return filter.currentRange.value.end.toInt();
  }

  Future<void> _refreshSearchWithFilters({bool preserveHaving = false}) async {
    if (_closed) return;
    final query = _lastQuery;
    final route = PageDownloadQueryPlanner.decide(
      query: query,
      hasFilter: _hasAnyFilter(),
      isApiCommand: _isApiCommand(query),
    );
    if (route == PageDownloadQueryRoute.none) {
      await onReset();
      return;
    }

    final request = ++_searchRequest;
    if (!preserveHaving) havingOnly.value = false;
    title.value = query.isEmpty ? 'Filtered search' : query;
    isLoading.value = true;
    isLoadingMore.value = false;
    error.value = '';
    currentPage.value = 0;
    hasNextPage.value = false;
    allVideos.clear();
    videos.clear();
    havingVideos.value = 0;
    totalResults.value = 0;
    final videoCode = _filterVideoCode();
    final actressName = _filterActressName();
    final categories = _filterCategories();
    final yearStart = _filterYearStart();
    final yearEnd = _filterYearEnd();
    final durationMin = filter.durationMin.value;
    final durationMax = filter.durationMax.value;
    final actressMode = filter.actressMode.value;
    final onlySeries = filter.onlySeries.value;
    _query = (query: query, route: route, videoCode: videoCode, actressName: actressName,
      categories: categories, yearStart: yearStart, yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax,
      actressMode: actressMode, onlySeries: onlySeries);

    try {
      final int total;
      switch (route) {
        case PageDownloadQueryRoute.dbFilterOnly:
          total = await DBR18.getByFilterCount(
            matchAllCategories: true,
            videoCode: videoCode, actressName: actressName, categories: categories,
            yearStart: yearStart, yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries,
          );
          break;
        case PageDownloadQueryRoute.dbSearch:
          total = await DBR18.getSearchCount(
            query, matchAllCategories: true, videoCode: videoCode, actressName: actressName, categories: categories,
            yearStart: yearStart, yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries,
          );
          break;
        default:
          total = 0;
      }
      if (_closed || request != _searchRequest) return;
      totalResults.value = total;
      await _loadPage(isLoadMore: false, request: request, page: 1);
      if (_closed || request != _searchRequest) return;
      if (scrollController.hasClients) scrollController.jumpTo(0);
    } catch (e) {
      if (_closed || request != _searchRequest) return;
      error.value = 'Search failed. Please try again.'.tr;
      AppLog.logE('Download search failed: $e');
    } finally {
      if (!_closed && request == _searchRequest) isLoading.value = false;
    }
  }

  // ~ Filters ────────────────────────────────────────────────────────────────
  final _filterAdapter = VideoFilterAdapter<JavitSearchResult>(
    videoCode: (video) => video.videoCode ?? '',
    title: (video) => video.title,
    actresses: (video) => video.actresses ?? <String>[],
    categories: (video) => video.categories ?? <String>[],
    releaseDate: (video) => video.releaseDate,
    durationMinutes: (video) => video.duration,
    actressCount: (video) => video.actressCount,
    series: (video) => video.series,
  );

  void showHavingOnly(bool value) {
    if (_closed) return;
    havingOnly.value = value;
    _applyHavingFilter();
    if (scrollController.hasClients) scrollController.jumpTo(0);
  }

  void _applyHavingFilter() {
    final visible = filter.applyBlacklist(allVideos.toList(), _filterAdapter);
    havingVideos.value = visible.where((video) => video.match == true).length;
    videos.value = havingOnly.isTrue
        ? visible.where((video) => video.match == true).toList()
        : visible;
  }

  Future<void> _loadPage({required bool isLoadMore, required int request, required int page}) async {
    if (_closed || request != _searchRequest) return;
    final snapshot = _query;
    if (snapshot == null) return;
    final query = snapshot.query;
    final route = snapshot.route;
    if (isLoadMore && hasNextPage.isFalse) return;
    if (isLoadMore) isLoadingMore.value = true;

    try {
      final sw = Stopwatch()..start();
      final videoCode = snapshot.videoCode;
      final actressName = snapshot.actressName;
      final categories = snapshot.categories;
      final yearStart = snapshot.yearStart;
      final yearEnd = snapshot.yearEnd;
      final durationMin = snapshot.durationMin;
      final durationMax = snapshot.durationMax;
      final actressMode = snapshot.actressMode;
      final onlySeries = snapshot.onlySeries;

      final List<Map<String, dynamic>> r18videos;
      final isOnlineApi = route == PageDownloadQueryRoute.apiCommand;
      int? apiTotal;
      bool? apiHasNextPage;

      switch (route) {
        case PageDownloadQueryRoute.apiCommand:
          final List<Map<String, dynamic>> rows;
          if (_isJavHeyQuery(query)) {
            final apiData = await fetchJavHey(query, page);
            apiTotal = apiData.total?.toInt();
            apiHasNextPage = apiData.hasNextPage ?? false;
            rows = (apiData.result ?? []).map((item) => {
              ...item.toJson(), 'id': item.videoId,
              'actresses': (item.actresses ?? []).join(', '), 'categories': (item.categories ?? []).join(', '),
            }).toList();
          } else {
            final apiData = await fetchJavMostByCommand(query, page);
            if (apiData.success == false) throw StateError('Online search failed'.tr);
            apiTotal = apiData.total ?? 0;
            rows = (apiData.result ?? []).map((item) => {
              'id': item.url ?? item.name, 'video_code': item.name ?? '', 'title': item.fullName ?? item.name ?? '',
              'release_date': item.release ?? '', 'actresses': item.star ?? '', 'categories': item.genre ?? '',
              'duration': int.tryParse((item.length ?? '').replaceAll(RegExp(r'[^0-9]'), '')),
              'trailer': item.dataPreview ?? '', 'fan_art': item.cover ?? '', 'poster': item.cover ?? '',
            }).toList();
          }
          r18videos = _filterOnlineRows(
            rows,
            videoCode: videoCode,
            actressName: actressName,
            categories: categories,
            yearStart: yearStart,
            yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries,
          );
          break;
        case PageDownloadQueryRoute.dbFilterOnly:
          r18videos = await DBR18.getByFilter(
            matchAllCategories: true,
            page: page,
            perPage: _perPage + 1,
            videoCode: videoCode,
            actressName: actressName,
            categories: categories,
            yearStart: yearStart,
            yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries,
          );
          break;
        case PageDownloadQueryRoute.dbSearch:
          r18videos = await DBR18.search(
            query, matchAllCategories: true,
            page: page,
            perPage: _perPage + 1,
            videoCode: videoCode,
            actressName: actressName,
            categories: categories,
            yearStart: yearStart,
            yearEnd: yearEnd, durationMin: durationMin, durationMax: durationMax, actressMode: actressMode, onlySeries: onlySeries,
          );
          break;
        case PageDownloadQueryRoute.none:
          r18videos = [];
          break;
      }

      if (_closed || request != _searchRequest) return;
      if (_existingVideoCodes.isEmpty) {
        final codes = await loadExistingVideoCodes();
        if (_closed || request != _searchRequest) return;
        _existingVideoCodes = codes;
      }
      final pageItems = isOnlineApi ? r18videos : r18videos.take(_perPage).toList();
      final currentLoaded = isLoadMore ? allVideos.length : 0;
      final hasMore = isOnlineApi ? apiHasNextPage ?? (apiTotal ?? 0) > currentLoaded + pageItems.length : r18videos.length > _perPage;

      final output = <JavitSearchResult>[];
      for (var i = 0; i < pageItems.length; i++) {
        final videoCode = pageItems[i]['video_code'].toString();
        if (videoCode.isValidVideoCode() == false) continue;
        final hasMatch = _existingVideoCodes.contains(videoCode);

        final actresses = (pageItems[i]['actresses'] ?? '').toString().split(RegExp(r',|/')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final categories = pageItems[i]['categories'].toString().split(',').map((e) => e.trim()).toList();

        output.add(
          JavitSearchResult(
            videoId: pageItems[i]['id'],
            videoCode: pageItems[i]['video_code'],
            duration: pageItems[i]['duration'],
            releaseDate: pageItems[i]['release_date'],
            title: pageItems[i]['title'],
            fanArt: pageItems[i]['fan_art'].toString().genImageUrl(),
            poster: pageItems[i]['poster'],
            trailer: pageItems[i]['trailer'],
            sourceUrl: pageItems[i]['source_url'],
            match: hasMatch,
            isReleased: DateTime.tryParse(pageItems[i]['release_date'] ?? '')?.isBefore(DateTime.now()),
            actresses: actresses,
            categories: categories,
            series: pageItems[i]['series'],
            actressCount: pageItems[i]['actress_count'],
          ),
        );
      }

      currentPage.value = page;
      hasNextPage.value = hasMore;
      if (isOnlineApi) totalResults.value = apiTotal ?? currentLoaded + output.length;
      if (isLoadMore) {
        allVideos.addAll(output);
      } else {
        allVideos.value = output;
      }

      _applyHavingFilter();
      _scheduleLoadMoreIfNeeded();
      sw.stop();
      AppLog.logD('download_query route=$route page=${currentPage.value} items=${pageItems.length} in ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      if (_closed || request != _searchRequest) return;
      error.value = 'Search failed. Please try again.'.tr;
      AppLog.logE('_loadPage e -> $e');
    } finally {
      if (!_closed && request == _searchRequest && isLoadMore) isLoadingMore.value = false;
    }
  }

  bool _isApiCommand(String query) {
    final q = query.trim().toLowerCase();
    return PageDownloadCommandEngine.isCommand(q) || _isOnlineSearchQuery(q) || _isJavHeyQuery(q);
  }

  bool _isJavHeyQuery(String query) {
    final value = query.trim().toLowerCase();
    return value == '/javhey' || value.startsWith('/javhey ');
  }

  Future<JavitSearch> fetchJavHey(String query, int page) => ApiJavHey.search(s: query.trim().substring('/javhey'.length).trim(), page: page);

  bool _isOnlineSearchQuery(String query) {
    return query.startsWith('/search ');
  }

  String _extractOnlineSearchKeyword(String query) {
    final q = query.trim();
    if (_isOnlineSearchQuery(q) == false) return '';
    return q.substring('/search '.length).trim();
  }

  bool _hasAnyFilter() {
    return filter.hasFilters;
  }

  Future<Set<String>> loadExistingVideoCodes() async => (await DBVideos.getAll()).map((video) => video.videoCode ?? '').toSet();

  Future<JavMostModel> fetchJavMostByCommand(String command, int page) async {
    final normalized = command.trim().toLowerCase();
    if (_isOnlineSearchQuery(normalized)) {
      final keyword = _extractOnlineSearchKeyword(normalized);
      if (keyword.isEmpty) return JavMostModel(result: [], success: true, total: 0);
      return ApiJavMost.search(s: keyword, page: page);
    }

    switch (normalized) {
      case '/new-release':
        return ApiJavMost.getNewRelease(page: page);
      case '/top-monthly':
        return ApiJavMost.getTopMonthly(page: page);
      case '/top-weekly':
        return ApiJavMost.getTopWeekly(page: page);
      case '/top-daily':
        return ApiJavMost.getTopDaily(page: page);
      case '/best-rated':
        return ApiJavMost.getBestRating(page: page);
      case '/search':
        return JavMostModel(result: [], success: true, total: 0);
      default:
        return ApiJavMost.getNewRelease(page: page);
    }
  }

  List<Map<String, dynamic>> _filterOnlineRows(
    List<Map<String, dynamic>> items, {
    String? videoCode,
    String? actressName,
    List<String>? categories,
    int? yearStart,
    int? yearEnd,
    int? durationMin,
    int? durationMax,
    ActressMode actressMode = ActressMode.all,
    bool onlySeries = false,
  }) {
    final output = <Map<String, dynamic>>[];

    final qVideoCode = videoCode?.trim().toLowerCase();
    final qActress = actressName?.trim().toLowerCase();
    final qCategories = categories?.map((e) => HelperDecensor.decensor(e).trim().toLowerCase()).where((e) => e.isNotEmpty).toList() ?? const <String>[];

    for (final item in items) {
      final rawCode = (item['video_code'] ?? '').toString().trim();
      final rawTitle = (item['title'] ?? item['video_code'] ?? '').toString();
      final rawRelease = (item['release_date'] ?? '').toString();
      final rawActresses = (item['actresses'] ?? '').toString();
      final rawCategories = (item['categories'] ?? '').toString();

      final actresses = rawActresses
          .split(RegExp(r',|/'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final categoryList = rawCategories
          .split(RegExp(r',|/'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final count = item['actress_count'] is int ? item['actress_count'] as int
        : actresses.map((name) => name.toLowerCase()).toSet().length;
      if (actressMode == ActressMode.single && count != 1 || actressMode == ActressMode.multi && count <= 1) continue;
      if (onlySeries && '${item['series'] ?? ''}'.trim().isEmpty) continue;

      if (qVideoCode != null && qVideoCode.isNotEmpty) {
        if (rawCode.toLowerCase().contains(qVideoCode) == false) continue;
      }

      if (qActress != null && qActress.isNotEmpty) {
        final hasActress = actresses.any((e) => e.toLowerCase().contains(qActress));
        if (hasActress == false) continue;
      }

      if (qCategories.isNotEmpty) {
        final lowerCategories = categoryList.map((e) => HelperDecensor.decensor(e).toLowerCase()).toSet();
        final hasAllCategories = qCategories.every((e) => lowerCategories.contains(e));
        if (hasAllCategories == false) continue;
      }

      if (yearStart != null && yearEnd != null) {
        final date = DateTime.tryParse(rawRelease);
        final year = date?.year;
        if (year == null || year < yearStart || year > yearEnd) continue;
      }

      final duration = int.tryParse((item['duration'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), ''));
      if (durationMin != null || durationMax != null) {
        if (duration == null || duration <= 0 || (durationMin != null && duration < durationMin) || (durationMax != null && duration > durationMax)) continue;
      }
      output.add({...item, 'video_code': rawCode, 'title': rawTitle, 'release_date': rawRelease,
        'duration': duration, 'categories': categoryList.join(', '), 'actresses': actresses.join(', ')});
    }

    return output;
  }

  void _onScroll() {
    _triggerLoadMoreIfNeeded();
  }

  void onViewportMetricsChanged() {
    _scheduleLoadMoreIfNeeded();
  }

  void _scheduleLoadMoreIfNeeded() {
    final request = _searchRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_closed || request != _searchRequest) return;
      _triggerLoadMoreIfNeeded();
    });
  }

  void _triggerLoadMoreIfNeeded() {
    if (_closed || error.value.isNotEmpty || scrollController.hasClients == false) return;
    if (hasNextPage.isFalse || isLoadingMore.isTrue || isLoading.isTrue) return;

    final position = scrollController.position;
    final isNearBottom = position.pixels >= position.maxScrollExtent - 240;
    final isNotScrollableYet = position.maxScrollExtent <= 0;
    if (isNearBottom || isNotScrollableYet) {
      _loadPage(isLoadMore: true, request: _searchRequest, page: currentPage.value + 1);
    }
  }

  Future<void> openDialogFilter({bool Function()? isAvailable}) async {
    await HelperOpener.openFilterDialog<JavitSearchResult>(
      state: filter,
      allVideos: allVideos.toList(),
      videos: videos,
      adapter: _filterAdapter,
      applyLocalFilter: false,
      matchAllCategories: true,
      isAvailable: () => !_closed && (isAvailable?.call() ?? true),
      onApplied: (_) async { unawaited(_refreshSearchWithFilters()); },
      onReset: () async { unawaited(_refreshSearchWithFilters()); },
    );
  }

}
