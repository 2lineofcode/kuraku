import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sql_formatter/sql_formatter.dart' as sql_formatter;

import '../../../core/app_logging.dart';
import '../../../core/app_translations.dart';
import '../../../utils/chat_service.dart';

class PageSqleditorTab extends GetxController {
  
  PageSqleditorTab({
    required this.sources,
    this.loadSchema,
    this.query,
    this.api,
    Map<String, dynamic>? savedSnippets,
    Future<void> Function(Map<String, dynamic>)? persistSnippets,
    SqlSnippetStore? snippetStore,
    this.id = 0,
  }) : snippetStore = snippetStore ?? SqlSnippetStore(savedSnippets ?? {}, persistSnippets);

  final int id;
  final isPinned = false.obs;
  final SqlSnippetStore snippetStore;

  final Map<String, String?> sources;
  final Future<Map<String, List<String>>> Function(String source)? loadSchema;
  final Future<Map<String, dynamic>> Function(String source, Map<String, dynamic> request, CancelToken token)? query;
  final ChatService? api;
  Map<String, String> snippetsFor(String source) => snippetStore.snippetsFor(source);

  final _loadedSnippets = <String, ({String name, String prefix})>{};

  String? get loadedSnippetName {
    final loaded = _loadedSnippets[source.value];
    return loaded != null && input.text.startsWith(loaded.prefix) && snippetsFor(source.value).containsKey(loaded.name) ? loaded.name : null;
  }

  String? get loadedSnippetSql => loadedSnippetName == null ? null : input.text.substring(_loadedSnippets[source.value]!.prefix.length);

  Future<void> saveSnippet(String source, String name, String? sql, {bool update = false}) => snippetStore.saveSnippet(source, name, sql, update: update);

  String get title {
    revision.value;
    return loadedSnippetName ?? 'Query @{number} · @{source}'.trNamed({'number': '${id + 1}', 'source': source.value});
  }

  Map<String, dynamic> toPreferences() => {
    'pinned': isPinned.value,
    'source': source.value,
    'drafts': {..._drafts.map((key, value) => MapEntry(key, value.text)), source.value: input.text},
    'parameters': {..._parameterDrafts, source.value: parameters.text},
    'loaded': _loadedSnippets.map((key, value) => MapEntry(key, {'name': value.name, 'prefix': value.prefix})),
    'aiPrompt': aiPrompt.text,
  };

  void restorePreferences(Map entry) {
    isPinned.value = entry['pinned'] == true;
    if (sources.containsKey(entry['source'])) source.value = entry['source'] as String;
    final drafts = entry['drafts'];
    if (drafts is Map) {
      for (final key in sources.keys) {
        if (drafts[key] is String) _drafts[key] = TextEditingValue(text: drafts[key] as String);
      }
    }
    final args = entry['parameters'];
    if (args is Map) {
      for (final key in sources.keys) {
        if (args[key] is String) _parameterDrafts[key] = args[key] as String;
      }
    }
    final loaded = entry['loaded'];
    if (loaded is Map) {
      for (final key in sources.keys) {
        final value = loaded[key];
        if (value is Map && value['name'] is String && value['prefix'] is String) {
          _loadedSnippets[key] = (name: value['name'] as String, prefix: value['prefix'] as String);
        }
      }
    }
    input.value = _drafts[source.value] ?? TextEditingValue.empty;
    parameters.text = _parameterDrafts[source.value] ?? '{}';
    if (entry['aiPrompt'] is String) aiPrompt.text = entry['aiPrompt'] as String;
  }

  final parameters = TextEditingController(text: '{}');
  final running = false.obs;
  final committing = false.obs;
  final queryError = ''.obs;
  final result = Rxn<Map<String, dynamic>>();
  final resultsExpanded = false.obs;
  final resultSource = ''.obs;
  final resultSql = ''.obs;
  final generating = false.obs;
  final aiError = ''.obs;
  final aiSql = ''.obs;
  CancelToken? _queryToken;
  CancelToken? _aiToken;
  String? _aiSource;
  final schemaLoading = false.obs;
  final schemaError = ''.obs;
  Map<String, List<String>> _schema = {};
  int _schemaRequest = 0;
  final source = 'javit.db'.obs;
  final input = TextEditingController();
  final aiPrompt = TextEditingController();
  final focusNode = FocusNode();
  final suggestions = <String>[].obs;
  final completionPopup = SuggestionsController<String>();
  final revision = 0.obs;
  final _drafts = <String, TextEditingValue>{};
  final _parameterDrafts = <String, String>{};
  int _start = 0;
  int _end = 0;

  List<String> get schemaTables => _schema.keys.toList();

  static const snippetActions = ['SELECT', 'INSERT', 'UPDATE', 'DELETE'];

  String buildSnippet(String action, String table) {
    String quote(String name) => '"${name.replaceAll('"', '""')}"';
    final columns = _schema[table] ?? ['column_name'];
    final column = columns.firstWhere((name) => name.toLowerCase() != 'id', orElse: () => columns.isEmpty ? 'column_name' : columns.first);
    final target = quote(table);
    return switch (action) {
      'SELECT' => 'SELECT *\nFROM $target\nLIMIT 100;',
      'INSERT' => 'INSERT INTO $target (${quote(column)})\nVALUES (:value);',
      'UPDATE' => 'UPDATE $target\nSET ${quote(column)} = :value\nWHERE /* replace with your condition */ 1 = 0;',
      'DELETE' => 'DELETE FROM $target\nWHERE /* replace with your condition */ 1 = 0;',
      _ => throw ArgumentError.value(action, 'action'),
    };
  }

  void appendSnippet(String sql, {String? name}) {
    final separator = input.text.trim().isEmpty ? '' : '\n\n';
    final start = input.text.length + separator.length;
    _loadedSnippets.remove(source.value);
    if (name != null) _loadedSnippets[source.value] = (name: name, prefix: '${input.text}$separator');
    input.value = TextEditingValue(
      text: '${input.text}$separator$sql',
      selection: TextSelection(baseOffset: start, extentOffset: start + sql.length),
    );
    dismissSuggestions();
    focusNode.requestFocus();
  }

  void formatQuery() {
    final value = input.value;
    if (!value.composing.isCollapsed) return;
    final selected = value.selection.isValid && !value.selection.isCollapsed;
    final start = selected ? value.selection.start : 0;
    final end = selected ? value.selection.end : value.text.length;
    final sql = value.text.substring(start, end);
    if (sql.trim().isEmpty) return;
    if (sql.length > 32000) { queryError.value = 'Format up to 32000 characters at a time.'.tr; return; }
    try {
      // sql_formatter 0.1.0 splits SQLite BLOB literals and JSON arrow operators.
      var prefix = ':__javit_format_';
      while (sql.contains(prefix)) { prefix += '_'; }
      final preserved = <String, String>{};
      final tokens = RegExp(r"""--[^\n]*|/\*[\s\S]*?(?:\*/|$)|"(?:""|[^"])*"|`(?:``|[^`])*`|\[[^\]]*\]|[xX]'[0-9a-fA-F]*'|'(?:''|[^'])*'|->>?""");
      final protected = sql.replaceAllMapped(tokens, (match) {
        final token = match.group(0)!;
        if (!token.startsWith('->') && !RegExp(r"^[xX]'").hasMatch(token)) return token;
        final key = '$prefix${preserved.length}';
        preserved[key] = token;
        return key;
      });
      var formatted = sql_formatter.format(protected, dialect: sql_formatter.SqlDialect.sqlite).trim();
      formatted = formatted.replaceAllMapped(RegExp('$prefix[0-9]+'), (match) => preserved[match.group(0)]!);
      if (selected) formatted = '${RegExp(r'^\s*').stringMatch(sql)}$formatted${RegExp(r'\s*$').firstMatch(sql)!.group(0)}';
      input.value = TextEditingValue(
        text: value.text.replaceRange(start, end, formatted),
        selection: selected ? TextSelection(baseOffset: start, extentOffset: start + formatted.length)
            : TextSelection.collapsed(offset: value.selection.isValid ? value.selection.extentOffset.clamp(0, formatted.length) : formatted.length),
      );
      dismissSuggestions();
      queryError.value = '';
      focusNode.requestFocus();
    } catch (_) {
      queryError.value = 'Could not format this SQL. Your query was kept unchanged.'.tr;
    }
  }

  String _message(Object error) => error is ChatException ? error.message.tr
      : error is StateError ? error.message.toString().tr
      : error is FormatException ? 'Parameters must be a JSON array or object.'.tr
      : 'The operation could not be completed. Please retry.'.tr;

  void stopQuery() {
    if (committing.value) return;
    _queryToken?.cancel();
  }

  Future<void> runQuery(Future<bool> Function(String sql, String source, String parameters) confirmWrite) async {
    if (running.value || query == null) return;
    final selectedSource = source.value;
    final selection = input.selection;
    final sql = (selection.isValid && !selection.isCollapsed ? selection.textInside(input.text) : input.text).trim();
    if (sql.isEmpty) { queryError.value = 'Write or select a query first.'.tr; return; }
    final token = CancelToken();
    _queryToken = token;
    running.value = true;
    queryError.value = '';
    result.value = null;
    resultSource.value = selectedSource;
    resultSql.value = sql;
    try {
      final args = jsonDecode(parameters.text.trim().isEmpty ? '{}' : parameters.text);
      if (args is! Map && args is! List) throw const FormatException();
      final request = <String, dynamic>{'sql': sql, 'args': args};
      var data = await query!(selectedSource, request, token);
      if (token.isCancelled || isClosed || selectedSource != source.value) return;
      if (data['requires_confirmation'] == true) {
        if (!await confirmWrite(sql, selectedSource, jsonEncode(args)) || token.isCancelled || isClosed || selectedSource != source.value) {
          if (!isClosed && selectedSource == source.value) queryError.value = 'Write cancelled. No changes were made.'.tr;
          return;
        }
        committing.value = true;
        data = await query!(selectedSource, {...request, 'confirm_write': true}, token);
      }
      if (!token.isCancelled && !isClosed && selectedSource == source.value) result.value = data;
    } catch (error) {
      if (!token.isCancelled) AppLog.logW('SQL query failed for $selectedSource: $error');
      if (!isClosed && selectedSource == source.value) {
        queryError.value = token.isCancelled ? 'Query stopped.'.tr : _message(error);
        if (committing.value) queryError.value += ' If completion is uncertain, check the database before retrying the write.'.tr;
      }
    } finally {
      if (!isClosed) {
        running.value = false;
        committing.value = false;
        if (token.isCancelled && selectedSource == source.value && queryError.value.isEmpty) queryError.value = 'Query stopped.'.tr;
      }
      _queryToken = null;
    }
  }

  void stopGeneration() => _aiToken?.cancel();

  Future<void> generateSql() async {
    if (generating.value) return;
    aiError.value = '';
    aiSql.value = '';
    if (api == null || query == null) { aiError.value = 'AI generation is unavailable.'.tr; return; }
    if (schemaLoading.value || schemaError.value.isNotEmpty || _schema.isEmpty) {
      aiError.value = 'Load the database schema first, then retry.'.tr;
      return;
    }
    final selectedSource = source.value;
    final prompt = aiPrompt.text;
    final token = CancelToken();
    _aiToken = token;
    generating.value = true;
    final timer = Timer(const Duration(seconds: 90), () => token.cancel('Generation timed out'.tr));
    try {
      final sql = await api!.generateSql(prompt, Map.of(_schema), token);
      if (token.isCancelled) return;
      await query!(selectedSource, {'operation': 'validate', 'sql': sql}, token);
      if (!isClosed && !token.isCancelled && selectedSource == source.value && aiPrompt.text == prompt) {
        _aiSource = selectedSource;
        aiSql.value = sql;
      }
    } catch (error) {
      if (!token.isCancelled) AppLog.logW('SQL generation failed for $selectedSource: $error');
      if (!isClosed && selectedSource == source.value) aiError.value = token.isCancelled ? 'Generation stopped or timed out. You can retry.'.tr : _message(error);
    } finally {
      timer.cancel();
      if (!isClosed) {
        generating.value = false;
        if (token.isCancelled && selectedSource == source.value && aiError.value.isEmpty) aiError.value = 'Generation stopped or timed out. You can retry.'.tr;
      }
      _aiToken = null;
    }
  }

  void insertGeneratedSql() {
    if (generating.value || aiSql.value.isEmpty || _aiSource != source.value) return;
    appendSnippet(aiSql.value);
  }

  static const keywords = [
    'SELECT', 'FROM', 'WHERE', 'LIMIT', 'OFFSET', 'ORDER BY', 'GROUP BY',
    'HAVING', 'DISTINCT', 'AS', 'ASC', 'DESC', 'AND', 'OR', 'NOT', 'NULL',
    'IS NULL', 'IS NOT NULL', 'IN', 'LIKE', 'BETWEEN', 'EXISTS', 'JOIN',
    'LEFT JOIN', 'INNER JOIN', 'ON', 'UNION', 'UNION ALL', 'WITH',
    'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE', 'CASE', 'WHEN',
    'THEN', 'ELSE', 'END', 'INSERT INTO', 'VALUES', 'UPDATE', 'SET',
    'DELETE FROM', 'CREATE TABLE', 'ALTER TABLE', 'DROP TABLE', 'PRAGMA',
  ];

  @override
  void onInit() {
    super.onInit();
    input.addListener(_updateSuggestions);
    unawaited(refreshSchema());
  }

  void selectSource(String value) {
    if (!sources.containsKey(value) || value == source.value) return;
    if (committing.value) return;
    stopQuery();
    stopGeneration();
    aiSql.value = '';
    result.value = null;
    queryError.value = '';
    _parameterDrafts[source.value] = parameters.text;
    parameters.text = _parameterDrafts[value] ?? '{}';
    _drafts[source.value] = input.value;
    source.value = value;
    _schema = {};
    input.value = _drafts[value] ?? TextEditingValue.empty;
    dismissSuggestions();
    unawaited(refreshSchema());
  }

  void dismissSuggestions() {
    suggestions.clear();
    completionPopup.close(retainFocus: true);
  }

  void _updateSuggestions({bool force = false}) {
    revision.value++;
    _buildSuggestions(force: force);
    completionPopup.refresh();
    if (suggestions.isEmpty) {
      completionPopup.close(retainFocus: true);
    } else if (focusNode.hasFocus) {
      completionPopup.open(gainFocus: false);
    }
  }

  void _buildSuggestions({bool force = false}) {
    suggestions.clear();
    final value = input.value;
    if (!value.selection.isValid || !value.selection.isCollapsed || !value.composing.isCollapsed) return;
    final cursor = value.selection.extentOffset;
    // Mask comments and literals without changing cursor offsets.
    final ignored = RegExp(r"--[^\n]*|/\*[\s\S]*?(?:\*/|$)|'(?:''|[^'])*(?:'|$)");
    for (final match in ignored.allMatches(value.text)) {
      final text = match.group(0)!;
      final closed = text.startsWith('/*') ? text.endsWith('*/')
          : text.startsWith('--') ? false : RegExp(r"^'(?:''|[^'])*'$").hasMatch(text);
      if (cursor > match.start && (cursor < match.end || cursor == match.end && !closed)) return;
    }
    final sql = value.text.replaceAllMapped(ignored, (match) => ' ' * match.group(0)!.length);
    final statementStart = sql.substring(0, cursor).lastIndexOf(';') + 1;
    final nextStatement = sql.indexOf(';', cursor);
    final statement = sql.substring(statementStart, nextStatement < 0 ? sql.length : nextStatement);
    final before = sql.substring(statementStart, cursor);
    final prefix = RegExp(r'[A-Za-z_][A-Za-z_0-9]*$').firstMatch(before);
    _start = prefix == null ? cursor : statementStart + prefix.start;
    _end = cursor;
    while (_end < value.text.length && RegExp(r'[A-Za-z_0-9]').hasMatch(value.text[_end])) {
      _end++;
    }
    final word = prefix?.group(0)?.toLowerCase() ?? '';
    final context = sql.substring(statementStart, _start);
    final tables = {for (final table in _schema.keys) table.toLowerCase(): table};
    final aliases = <String, String>{};
    final referenced = <String>{};
    const identifier = r'(?:(?:"(?:""|[^"])+")|(?:`[^`]+`)|(?:\[[^\]]+\])|(?:[A-Za-z_][A-Za-z_0-9]*))';
    String unquote(String name) => name.startsWith('"') ? name.substring(1, name.length - 1).replaceAll('""', '"')
        : name.startsWith('`') || name.startsWith('[') ? name.substring(1, name.length - 1) : name;
    final reserved = {...keywords.expand((keyword) => keyword.split(' ')), 'OUTER', 'CROSS', 'NATURAL', 'USING', 'RETURNING'};
    // ponytail: flat SQL table/alias context; use a parser for nested scopes and CTE output columns.
    for (final match in RegExp('\\b(?:FROM|JOIN|UPDATE|INTO)\\s+($identifier)(?:\\s+(?:AS\\s+)?((?!(?:${reserved.join('|')})\\b)$identifier))?', caseSensitive: false).allMatches(statement)) {
      final table = tables[unquote(match.group(1)!).toLowerCase()];
      if (table == null) continue;
      referenced.add(table);
      aliases[table.toLowerCase()] = table;
      final alias = match.group(2);
      if (alias != null && !reserved.contains(alias.toUpperCase())) aliases[unquote(alias).toLowerCase()] = table;
    }
    final qualifier = RegExp('($identifier)\\s*\\.\\s*\$', caseSensitive: false).firstMatch(context);
    final tableContext = RegExp(r'\b(?:FROM|JOIN|UPDATE|INTO)\s*$', caseSensitive: false).hasMatch(context);
    Iterable<String> candidates;
    if (qualifier != null) {
      final name = unquote(qualifier.group(1)!).toLowerCase();
      candidates = name == 'main' ? _schema.keys : _schema[aliases[name] ?? tables[name]] ?? <String>[];
    } else if (tableContext) {
      candidates = _schema.keys;
    } else {
      final columnContext = RegExp(r'(?:\b(?:SELECT|WHERE|ON|AND|OR|BY|SET)|,)\s*$', caseSensitive: false).hasMatch(context);
      if (!force && word.isEmpty && (!columnContext || referenced.isEmpty)) return;
      candidates = [
        for (final table in referenced) ..._schema[table]!,
        if (referenced.isEmpty) ...[..._schema.keys, ..._schema.values.expand((columns) => columns)],
        if (force || word.isNotEmpty) ...keywords,
      ];
    }
    final matches = <({String name, List<int> positions, int rank})>[];
    for (final name in candidates.toSet()) {
      final lower = name.toLowerCase();
      if (lower == word || keywords.contains(name) && !lower.startsWith(word)) continue;
      final positions = completionMatch(name, word);
      if (positions == null) continue;
      matches.add((name: name, positions: positions, rank: lower.startsWith(word) ? 0 : lower.contains(word) ? 1 : 2));
    }
    if (word.isNotEmpty) matches.sort((a, b) {
      final rank = a.rank.compareTo(b.rank);
      if (rank != 0) return rank;
      final gaps = (a.positions.last - a.positions.first).compareTo(b.positions.last - b.positions.first);
      if (gaps != 0) return gaps;
      final length = a.name.length.compareTo(b.name.length);
      return length != 0 ? length : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    suggestions.assignAll(matches.map((match) => match.name));
  }

  static List<int>? completionMatch(String name, String query) {
    final text = name.toLowerCase();
    final word = query.toLowerCase();
    if (word.isEmpty) return [];
    final start = text.indexOf(word);
    if (start >= 0) return List.generate(word.length, (index) => start + index);
    final positions = <int>[];
    var cursor = 0;
    for (final character in word.split('')) {
      final index = text.indexOf(character, cursor);
      if (index < 0) return null;
      positions.add(index);
      cursor = index + 1;
    }
    return positions;
  }

  static Future<Map<String, List<String>>> readSchema(Database? db) async {
    if (db == null) return {};
    final rows = await db.rawQuery('''
      SELECT s.name AS table_name, c.name AS column_name
      FROM sqlite_master AS s LEFT JOIN pragma_table_xinfo(s.name) AS c
      WHERE s.type IN ('table', 'view')
      ORDER BY s.name, c.cid
    ''');
    final schema = <String, List<String>>{};
    for (final row in rows) {
      final columns = schema.putIfAbsent(row['table_name'] as String, () => []);
      if (row['column_name'] != null) columns.add(row['column_name'] as String);
    }
    return schema;
  }

  Future<void> refreshSchema() async {
    final request = ++_schemaRequest;
    schemaLoading.value = true;
    schemaError.value = '';
    try {
      final schema = await loadSchema?.call(source.value) ?? <String, List<String>>{};
      if (isClosed || request != _schemaRequest) return;
      _schema = schema;
    } catch (error) {
      if (isClosed || request != _schemaRequest) return;
      AppLog.logW('SQL schema load failed for ${source.value}: $error');
      _schema = {};
      schemaError.value = 'Could not load schema. Click to retry.'.tr;
    } finally {
      if (!isClosed && request == _schemaRequest) {
        schemaLoading.value = false;
        _updateSuggestions();
      }
    }
  }

  void complete(String keyword) {
    if (!suggestions.contains(keyword)) return;
    final completion = keywords.contains(keyword) || RegExp(r'^[A-Za-z_][A-Za-z_0-9]*$').hasMatch(keyword)
        ? keyword : '"${keyword.replaceAll('"', '""')}"';
    input.value = TextEditingValue(
      text: input.text.replaceRange(_start, _end, completion),
      selection: TextSelection.collapsed(offset: _start + completion.length),
    );
    dismissSuggestions();
    focusNode.requestFocus();
  }

  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !input.value.composing.isCollapsed) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space && HardwareKeyboard.instance.isControlPressed
        && !HardwareKeyboard.instance.isMetaPressed && !HardwareKeyboard.instance.isAltPressed && !HardwareKeyboard.instance.isShiftPressed) {
      _updateSuggestions(force: true);
      return KeyEventResult.handled;
    }
    if (suggestions.isEmpty || !completionPopup.isOpen) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isAltPressed || HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      dismissSuggestions();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final delta = (event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)
          * (completionPopup.effectiveDirection == VerticalDirection.down ? 1 : -1);
      completionPopup.highlighted = ((completionPopup.highlighted ?? (delta > 0 ? -1 : 0)) + delta) % suggestions.length;
    } else if (event.logicalKey == LogicalKeyboardKey.tab || event.logicalKey == LogicalKeyboardKey.enter) {
      complete(suggestions[(completionPopup.highlighted ?? 0).clamp(0, suggestions.length - 1)]);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void onClose() {
    _queryToken?.cancel();
    _aiToken?.cancel();
    api?.close();
    completionPopup.dispose();
    parameters.dispose();
    input.dispose();
    aiPrompt.dispose();
    focusNode.dispose();
    super.onClose();
  }
}

class SqlSnippetStore {
  SqlSnippetStore(Map<String, dynamic> initial, this.persistSnippets) : savedSnippets = Map<String, dynamic>.from(initial);
  final Map<String, dynamic> savedSnippets;
  final Future<void> Function(Map<String, dynamic>)? persistSnippets;
  Future<void> _pending = Future.value();

  Map<String, String> snippetsFor(String source) => Map<String, String>.from(savedSnippets[source] as Map? ?? {});

  Future<void> saveSnippet(String source, String name, String? sql, {bool update = false}) {
    final operation = _pending.then((_) => _save(source, name, sql, update));
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _save(String source, String name, String? sql, bool update) async {
    name = name.trim();
    if (name.isEmpty) throw StateError('Enter a snippet name.'.tr);
    if (sql != null && sql.trim().isEmpty) throw StateError('Write or select a query first.'.tr);
    final entries = snippetsFor(source);
    if (sql == null) {
      entries.remove(name);
    } else {
      if (update && !entries.containsKey(name)) throw StateError('This snippet no longer exists. Save it as a new snippet.'.tr);
      if (!update && entries.containsKey(name)) throw StateError('This name already exists. Use a different name.'.tr);
      entries[name] = sql.trim();
    }
    if (persistSnippets == null) throw StateError('Snippet storage is unavailable.'.tr);
    final next = {...savedSnippets, source: entries};
    await persistSnippets!(next);
    savedSnippets..clear()..addAll(next);
  }

}
