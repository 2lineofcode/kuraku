import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/utils/chat_knowledge.dart';
import 'package:kuraku/app/utils/chat_service.dart';

class _Knowledge extends ChatKnowledge {
  _Knowledge() : super(mainPath: '/local/kuraku.db', r18Path: '/local/r18_test.db');
  final queries = <Map<String, dynamic>>[];
  bool fail = false;
  Map<String, dynamic>? result;
  final searchResults = <Map<String, dynamic>>[];
  int rejectedSearches = 0;
  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> query, CancelToken token) async {
    if (token.isCancelled) throw token.cancelError!;
    queries.add(query);
    if (fail) throw StateError('Local query unavailable');
    if (query['operation'] == 'video_reference') return {'reference': {'code': query['code'], 'title_ja': '雨の散歩', 'comment_en': 'Walking outside in the rain'}};
    if (query['schema'] == true) return {'schema': {'temp.videos': ['video_code', 'title']}, 'r18_code_column': 'video_code'};
    if (query['operation'] == 'search_titles') {
      if (rejectedSearches > 0) { rejectedSearches--; throw StateError('Invalid concept plan'); }
      if (searchResults.isNotEmpty) return searchResults.removeAt(0);
    }
    return result ?? {'columns': ['total'], 'rows': [[42]], 'sources': ['kuraku.db'], 'elapsed_ms': 1, 'truncated': false};
  }
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final answers = <String>['{"sql":"SELECT COUNT(*) AS total FROM temp.videos"}', 'You have **42** records.'];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final text = answers.removeAt(0);
    final titleSearch = text.startsWith('{"terms"');
    final reference = text.startsWith('{"code"');
    final query = reference || titleSearch || text.startsWith('{"sql"');
    final delta = query ? {'tool_calls': [{'index': 0, 'id': 'local_1', 'function': {'name': reference ? 'get_video_reference' : titleSearch ? 'search_local_titles' : 'query_local', 'arguments': text}}]} : {'content': text};
    final event = jsonEncode({'choices': [{'delta': delta, 'finish_reason': query ? 'tool_calls' : 'stop'}]});
    return ResponseBody.fromString('data: $event\n\ndata: [DONE]\n\n', 200);
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Chat knowledge follows the active R18 database after install and update', () async {
    String? path;
    final knowledge = ChatKnowledge(mainPath: '/main.db', resolveR18Path: () => path,
      loadScript: () async => 'import json,sys; print(json.dumps({"r18": json.load(sys.stdin)["r18"]}))');
    expect(knowledge.directQuery('ABP-001'), {'operation': 'video_lookup', 'code': 'ABP-001'});
    for (final next in ['/r18_old.db', '/r18_new.db', null]) {
      path = next;
      expect((await knowledge.request({}, CancelToken()))['r18'], next);
      expect(knowledge.directQuery('ABP-001'), {'operation': 'video_lookup', 'code': 'ABP-001'});
    }
  });
  test('Python workers exchange Unicode in UTF-8 mode on every desktop', () async {
    final knowledge = ChatKnowledge(mainPath: '/unused.db', loadScript: () async =>
      'import json,sys; request=json.load(sys.stdin); print(json.dumps({"text": request["text"], "utf8": sys.flags.utf8_mode}, ensure_ascii=False))');
    final result = await knowledge.request({'text': '日本語 — Indonesia'}, CancelToken());
    expect(result, {'text': '日本語 — Indonesia', 'utf8': 1});
  });
  test('Bundled worker reads a real database and cancels a running query', () async {
    final folder = await Directory.systemTemp.createTemp('kuraku-knowledge-test-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/kuraku.db';
    final setup = await Process.run(Platform.isWindows ? 'python' : 'python3', ['-X', 'utf8', '-B', '-c',
      'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE videos (video_code TEXT)"); c.executemany("INSERT INTO videos VALUES (?)", [("TEST-001",)]*100); c.commit(); c.close()', path]);
    expect(setup.exitCode, 0);
    final knowledge = ChatKnowledge(mainPath: path, loadScript: () => rootBundle.loadString('assets/python/chat_database_worker.py'));
    final result = await knowledge.request({'sql': 'SELECT COUNT(*) AS total FROM temp.videos'}, CancelToken());
    expect(result['rows'], [[100]]);
    final token = CancelToken();
    final timer = Timer(const Duration(milliseconds: 150), () => token.cancel());
    addTearDown(timer.cancel);
    await expectLater(knowledge.request({'sql': 'SELECT count(*) FROM temp.videos a, temp.videos b, temp.videos c, temp.videos d, temp.videos e'}, token), throwsA(isA<DioException>()));
  });
  test('Code headers normalize aliases and old Markdown without rewriting values or code blocks', () {
    for (final header in ['dvd_id', 'DVD ID', r'dvd\_id', '`dvd_id`', '**DVD ID**', 'video code']) {
      final markdown = '| $header | Title |\n| --- | --- |\n| dvd_id | Sample |';
      expect(ChatKnowledge.normalizeTableHeaders(markdown), '| Code | Title |\n| --- | --- |\n| dvd_id | Sample |');
    }
    const code = '```sql\n| dvd_id | Title |\n| --- | --- |\n```';
    expect(ChatKnowledge.normalizeTableHeaders(code), code);
    expect(ChatKnowledge.displayColumn('DVD ID'), 'Code');
  });

  test('Exact local intents bypass API even without an API key; complex filters do not', () async {
    final knowledge = _Knowledge();
    final api = ChatService(apiKey: '', knowledge: knowledge);
    addTearDown(api.close);
    final result = await api.reply([{'role': 'user', 'content': 'Berapa jumlah video saya?'}], CancelToken()).join();
    expect(result, contains('| 42 |'));
    expect(result, contains('kuraku.db'));
    expect(knowledge.queries.single['sql'], contains('COUNT(*)'));
    expect(knowledge.directQuery('berapa video saya dengan kualitas 4K'), isNull);
    expect(knowledge.directQuery('Koleksi gue ada berapa video?')!['sql'], contains('COUNT(*)'));
    expect(knowledge.directQuery('Tampilkan favorit gue')!['sql'], contains('is_favorite = 1'));
    expect(knowledge.directQuery('Bandingin koleksi gue sama katalog R18'), {'operation': 'compare_catalog'});
    expect(knowledge.directQuery('total video r18'), {'operation': 'catalog_count'});
    expect(knowledge.directQuery('jelaskan TEST-123 dibandingkan TEST-456'), isNull);
    expect(knowledge.directQuery('cek kode test-123'), {'operation': 'video_lookup', 'code': 'TEST-123'});
    expect(knowledge.directQuery('coba check video eyan-181'), {'operation': 'video_lookup', 'code': 'EYAN-181'});
    expect(knowledge.directQuery("TEST-123'; DROP TABLE videos"), isNull);
    expect(ChatKnowledge(mainPath: '/local/db').directQuery('TEST-123'), {'operation': 'video_lookup', 'code': 'TEST-123'});
    final cover = ChatKnowledge.render({
      'columns': ['title', 'source', 'code'], 'rows': [['Sample', 'R18', 'TEST-001']],
      'covers': {'TEST-001': 'https://example.com/cover.jpg?size=large&n=(1)'},
      'sources': ['db'], 'elapsed_ms': 1, 'truncated': false,
    });
    expect(cover, contains('| Image | Code | Title | source |'));
    expect(cover, contains('![TEST-001](kuraku-cover:https%3A%2F%2Fexample.com'));
    final rendered = ChatKnowledge.render({'columns': ['title'], 'rows': [['[link](https://example.com)|**text**']], 'sources': ['db'], 'elapsed_ms': 1, 'truncated': true});
    expect(rendered, contains(r'\[link]'));
    expect(rendered, contains(r'\|'));
    expect(rendered, contains('limited result'));
  });

  test('Complex questions use a bounded query, then stream a grounded answer', () async {
    final knowledge = _Knowledge();
    final adapter = _Adapter()..answers[0] = '{"sql":"SELECT COUNT(*) AS total FROM temp.videos WHERE title = ?","args":["Rain"]}';
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    final messages = [{'role': 'user', 'content': 'Count my 4K favorites'}];
    final result = await api.reply(messages, CancelToken()).join();
    expect(adapter.requests.length, 2);
    expect(knowledge.queries.last['sql'], 'SELECT COUNT(*) AS total FROM temp.videos WHERE title = ?');
    expect(knowledge.queries.last['args'], ['Rain']);
    expect(result, contains('**42**'));
    expect(result, contains('kuraku.db'));
    expect(adapter.requests.last.data['messages'].last['content'], contains('"rows":[[42]]'));
    expect(adapter.requests.first.data['messages'].last, messages.last);
    expect(jsonEncode(adapter.requests.first.data), isNot(contains('/local/')));
  });

  test('Large video lists render locally with Code and never resend hundreds of rows to the model', () async {
    final knowledge = _Knowledge()..result = {
      'columns': ['dvd_id', 'title_en'],
      'rows': List.generate(200, (i) => ['TEST-${i + 1}', 'Sample title ${i + 1}']),
      'sources': ['r18_test.db'], 'elapsed_ms': 1, 'truncated': false,
    };
    final adapter = _Adapter()..answers[0] = '{"sql":"SELECT dvd_id AS code, title_en FROM r18.derived_video ORDER BY dvd_id LIMIT 200"}';
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    final result = await api.reply([{'role': 'user', 'content': 'Show 200 matching videos'}], CancelToken()).join();
    expect(adapter.requests, hasLength(1));
    expect(result, contains('| Image | Code | Title |'));
    expect(result, contains('| [TEST-200](kuraku-video:TEST-200) | Sample title 200 |'));
    expect(result, contains('200 records'));
    expect(result, isNot(contains('dvd_id')));
    expect(result, isNot(contains('limited result')));
    adapter.answers..clear()..add('Done.');
    await api.reply([
      {'role': 'user', 'content': 'Show 200 matching videos'},
      {'role': 'assistant', 'content': result},
      {'role': 'user', 'content': 'How many did you show?'},
    ], CancelToken()).join();
    final context = adapter.requests.last.data['messages'] as List;
    final previous = context.firstWhere((message) => message['role'] == 'assistant')['content'] as String;
    expect(previous, contains('200 records'));
    expect(previous, contains('abbreviated'));
    expect(previous, isNot(contains('Sample title 200')));
    expect(context.last['content'], 'How many did you show?');
  });

  test('Translated title terms execute locally and display Japanese match evidence', () async {
    final knowledge = _Knowledge()..result = {
      'columns': ['code', 'title', 'title_ja', 'matched_in'],
      'rows': [['TEST-001', '雨の散歩', '雨の散歩', 'Japanese title']],
      'search_terms': ['rain', '雨'], 'sources': ['r18_test.db'], 'elapsed_ms': 1, 'truncated': false,
    };
    final adapter = _Adapter()..answers[0] = '{"terms":["rain","雨"],"source":"r18","missing_english":true,"limit":200}';
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    Map<String, dynamic>? search;
    api.onTitleSearch = (value) => search = value;
    Map<String, dynamic>? snapshot;
    api.onLocalResult = (value) => snapshot = value;
    final output = await api.reply([{'role': 'user', 'content': 'Cari judul tentang hujan yang belum ada English-nya'}], CancelToken()).join();
    expect(adapter.requests, hasLength(1));
    expect((adapter.requests.first.data['tools'] as List).any((tool) => tool['function']['name'] == 'search_local_titles'), isTrue);
    expect(knowledge.queries.last, {'terms': ['rain', '雨'], 'source': 'r18', 'missing_english': true, 'limit': 500, 'operation': 'search_titles'});
    expect(output, contains('Cross-language title search · rain, 雨'));
    expect(output, contains('Japanese title'));
    expect(output, contains('Matched in'));
    expect(search?['terms'], ['rain', '雨']);
    expect(search?['limit'], 500);
    expect(snapshot, same(knowledge.result));
    expect(search?['has_more'], false);
    expect(output, contains('雨の散歩'));
  });

  test('Similarity reads reference metadata before searching themes and retains filters for pagination', () async {
    final knowledge = _Knowledge()..result = {
      'columns': ['code', 'title', 'title_ja', 'matched_in'],
      'rows': [['TEST-002', 'Morning walk', '雨の散歩', 'Description']],
      'search_terms': ['rain', '雨'], 'similar_to': 'TEST-001', 'required_terms': [['outdoor', '屋外']],
      'exclude_terms': ['compilation'], 'unowned': true, 'sources': ['r18_test.db'], 'elapsed_ms': 1, 'has_more': true,
    };
    final adapter = _Adapter()..answers.clear()..answers.addAll([
      '{"code":"TEST-001"}',
      '{"terms":["rain","雨"],"source":"r18","similar_to":"TEST-001","required_terms":[["outdoor","屋外"]],"exclude_terms":["compilation"],"unowned":true,"limit":25}',
    ]);
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    Map<String, dynamic>? saved;
    api.onTitleSearch = (query) => saved = query;
    final result = await api.reply([{'role': 'user', 'content': 'Find similar themes to TEST-001, outdoors, no compilations, not owned'}], CancelToken()).join();
    expect(knowledge.queries[1], {'operation': 'video_reference', 'code': 'TEST-001'});
    expect(jsonEncode(adapter.requests.last.data['messages']), contains('Walking outside in the rain'));
    expect(result, contains('Similar themes to TEST-001'));
    expect(result, contains('Description'));
    expect(result, contains('kuraku-translate:'));
    expect(result, contains('kuraku-similar:TEST-002'));
    expect(saved?['required_terms'], [['outdoor', '屋外']]);
    expect(saved?['unowned'], true);
    expect(saved?['has_more'], true);
    expect(adapter.requests, hasLength(2));
  });

  test('Similarity rejects searches that skip reading the reference metadata', () async {
    final knowledge = _Knowledge();
    final adapter = _Adapter()..answers.clear()..answers.addAll([
      '{"terms":["rain"],"source":"r18","similar_to":"TEST-001","limit":25}',
      'The reference metadata must be read before searching.',
    ]);
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    await api.reply([{'role': 'user', 'content': 'Find similar themes to TEST-001'}], CancelToken()).join();
    expect(knowledge.queries.where((query) => query['operation'] == 'search_titles'), isEmpty);
    expect(jsonEncode(adapter.requests.last.data['messages']), contains('Read the reference metadata'));
  });

  test('Ranked results show reference context and exact evidence without duplicate Japanese columns', () {
    final output = ChatKnowledge.render({
      'columns': ['code', 'title', 'title_ja', 'matched_in', 'release_date', 'match_evidence'],
      'rows': [['TEST-002', '雨の散歩', '雨の散歩', 'Japanese title', '2026-10-01', 'Japanese title: 雨 — 雨の散歩 <script>']],
      'search_terms': ['rain', '雨'], 'similar_to': 'TEST-001',
      'reference': {'title_en': 'An outdoor walk in the rain'},
      'related_terms': [['outdoor', '屋外']], 'sort': 'relevance', 'missing_english': true,
      'sources': ['fixture.db'], 'elapsed_ms': 1,
    });
    expect(output, contains('Reference: An outdoor walk in the rain'));
    expect(output, contains('Related themes: outdoor / 屋外'));
    expect(output, contains('Sorted by relevance, then release date'));
    expect(output, contains('Without an English title'));
    expect(output, contains('| Image | Code | Title | Why it matches | Release date | Actions |'));
    expect(output, isNot(contains('| Matched in |')));
    expect(output, contains('Japanese title: 雨 — 雨の散歩 &lt;script>'));
    expect(output, contains('kuraku-translate:'));
    expect(output, contains('kuraku-similar:TEST-002'));
  });

  test('Empty discovery retries translations once while preserving every original constraint', () async {
    final empty = <String, dynamic>{
      'columns': ['code', 'title'], 'rows': [], 'search_terms': ['rain'],
      'sources': ['fixture.db'], 'elapsed_ms': 1,
    };
    final knowledge = _Knowledge()..searchResults.addAll([
      empty,
      {...empty, 'rows': [['TEST-002', '雨の散歩']], 'search_terms': ['rain', '雨'], 'sort': 'relevance'},
    ]);
    final adapter = _Adapter()..answers.clear()..answers.addAll([
      '{"terms":["rain"],"source":"r18","required_terms":[["outdoor"]],"related_terms":[["walk","散歩"]],"exclude_terms":["compilation"],"unowned":true,"missing_english":true,"sort":"relevance","limit":25}',
      '{"terms":["雨"],"source":"library","required_terms":[["outdoor","屋外"],["unrelated"]],"sort":"newest","limit":100}',
    ]);
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    Map<String, dynamic>? saved;
    api.onTitleSearch = (query) => saved = query;
    final output = await api.reply([{'role': 'user', 'content': 'Cari tema hujan di luar ruangan, belum punya, tanpa kompilasi, belum ada English'}], CancelToken()).join();
    final queries = knowledge.queries.where((query) => query['operation'] == 'search_titles').toList();
    expect(queries, hasLength(2));
    expect(queries.last, {...queries.first, 'terms': ['rain', '雨'], 'required_terms': [['outdoor', '屋外']]});
    expect(saved?['required_terms'], [['outdoor', '屋外']]);
    expect(saved?['unowned'], true);
    expect(saved?['sort'], 'relevance');
    expect(output, contains('TEST-002'));
    expect(output, isNot(contains('No matches.')));
    expect(jsonEncode(adapter.requests.last.data['messages']), contains('Do not broaden the meaning'));
  });

  test('Empty-search retries cannot mix anchors from separate concepts', () async {
    final empty = <String, dynamic>{
      'columns': ['code', 'title'], 'rows': [], 'search_terms': ['rain'],
      'sources': ['fixture.db'], 'elapsed_ms': 1,
    };
    for (final primary in [['雨'], ['rain', 'outdoor'], ['rain', 'walk']]) {
      final knowledge = _Knowledge()..searchResults.addAll([empty, empty]);
      final adapter = _Adapter()..answers.clear()..answers.addAll([
        jsonEncode({'terms': ['rain'], 'source': 'r18', 'required_terms': [['outdoor'], ['park']], 'related_terms': [['walk']], 'limit': 25}),
        jsonEncode({'terms': primary, 'source': 'r18', 'required_terms': [['outdoor', 'park', '屋外', '公園']], 'related_terms': [['walk', 'park', '散歩']], 'limit': 25}),
      ]);
      final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
      addTearDown(api.close);
      await api.reply([{'role': 'user', 'content': 'Find rain outdoors in a park, prefer walks'}], CancelToken()).join();
      final retry = knowledge.queries.last;
      expect(retry['terms'], primary.contains('雨') ? ['rain', '雨'] : ['rain']);
      expect(retry['required_terms'], [['outdoor'], ['park']]);
      expect(retry['related_terms'], [['walk']]);
    }
  });

  test('Two empty concept searches finish with an honest metadata limitation', () async {
    final knowledge = _Knowledge()..result = {
      'columns': ['code', 'title'], 'rows': [], 'search_terms': ['rain'],
      'sources': ['fixture.db'], 'elapsed_ms': 1,
    };
    final adapter = _Adapter()..answers.clear()..answers.addAll([
      '{"terms":["rain"],"source":"r18","limit":25}',
      '{"terms":["rain","雨"],"source":"r18","limit":25}',
    ]);
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    final output = await api.reply([{'role': 'user', 'content': 'Find rain videos'}], CancelToken()).join();
    expect(output, contains('No matches for these concepts and filters in the available metadata'));
    expect(adapter.requests, hasLength(2));
  });

  test('A failed search after reading a reference can recover within the tool budget', () async {
    final knowledge = _Knowledge()
      ..rejectedSearches = 1
      ..result = {
      'columns': ['code', 'title'], 'rows': [['TEST-002', 'Rain walk']],
      'search_terms': ['rain'], 'sources': ['fixture.db'], 'elapsed_ms': 1,
    };
    final adapter = _Adapter()..answers.clear()..answers.addAll([
      '{"code":"TEST-001"}',
      '{"terms":["rain"],"source":"r18","similar_to":"TEST-001","limit":25}',
      '{"terms":["rain","雨"],"source":"r18","similar_to":"TEST-001","related_terms":[["outdoor","屋外"]],"limit":25}',
    ]);
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    final output = await api.reply([{'role': 'user', 'content': 'Find similar videos to TEST-001'}], CancelToken()).join();
    expect(output, contains('TEST-002'));
    expect(adapter.requests, hasLength(3));
    expect(adapter.requests.last.data['tool_choice'], 'auto');
    expect(knowledge.queries.last['related_terms'], [['outdoor', '屋外']]);
  });

  test('Structured follow-up context reaches the model without unsupported message fields', () async {
    final adapter = _Adapter()..answers.clear()..answers.add('Please choose the next theme.');
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: _Knowledge());
    addTearDown(api.close);
    final context = jsonEncode({'terms': ['rain', '雨'], 'required_terms': [['outdoor']], 'unowned': true, 'sort': 'relevance'});
    await api.reply([
      {'role': 'user', 'content': 'Search for outdoor rain'},
      {'role': 'assistant', 'content': 'Previous matches', 'search_context': context},
      {'role': 'user', 'content': 'Add another theme'},
    ], CancelToken()).join();
    final messages = adapter.requests.single.data['messages'] as List;
    expect(messages.every((message) => !message.containsKey('search_context')), isTrue);
    expect(messages.any((message) => message['role'] == 'system' && (message['content'] as String).contains(context)), isTrue);
    expect(jsonEncode(messages), contains('R18 canonical code column is video_code'));
    expect(messages.last, {'role': 'user', 'content': 'Add another theme'});
  });

  test('Textual tool markup is hidden and retried using the local tool', () async {
    final knowledge = _Knowledge();
    final adapter = _Adapter()..answers.insert(0, '<tool_call>\n<function=web_search>\n<parameter=query>SELECT * FROM temp.videos</parameter>\n</function>\n</tool_call>');
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    final activities = <String>[];
    api.onActivity = activities.add;
    final result = await api.reply([{'role': 'user', 'content': 'Count my favorites'}], CancelToken()).join();
    expect(result, contains('**42**'));
    expect(result, isNot(contains('<tool_call>')));
    expect(result, isNot(contains('SELECT')));
    expect(activities, contains('Retrying an unreadable tool response'));
    expect(adapter.requests.length, 3);
    expect(knowledge.queries.length, 2);
  });

  test('General chat needs no SQL; rejected queries and cancellation cannot produce a fabricated result', () async {
    final knowledge = _Knowledge();
    final adapter = _Adapter()..answers.clear()..answers.add('Hello!');
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    expect(await api.reply([{'role': 'user', 'content': 'Hello'}], CancelToken()).join(), 'Hello!');
    expect(knowledge.queries.length, 1);
    knowledge.fail = true;
    await expectLater(api.reply([{'role': 'user', 'content': 'total video saya'}], CancelToken()).join(), throwsA(isA<ChatException>()));
    await expectLater(api.reply([{'role': 'user', 'content': 'total video saya'}], CancelToken()..cancel()).join(), throwsA(isA<ChatException>()));
    expect(adapter.requests.length, 1);
  });
}
