import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/utils/chat_knowledge.dart';
import 'package:javit/app/utils/chat_service.dart';

class _Knowledge extends ChatKnowledge {
  _Knowledge() : super(mainPath: '/local/javit.db', r18Path: '/local/r18_test.db');
  final queries = <Map<String, dynamic>>[];
  bool fail = false;
  Map<String, dynamic>? result;
  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> query, CancelToken token) async {
    if (token.isCancelled) throw token.cancelError!;
    queries.add(query);
    if (fail) throw StateError('Local query unavailable');
    if (query['operation'] == 'video_reference') return {'reference': {'code': query['code'], 'title_ja': '雨の散歩', 'comment_en': 'Walking outside in the rain'}};
    if (query['schema'] == true) return {'schema': {'main.videos': ['video_code', 'title']}};
    return result ?? {'columns': ['total'], 'rows': [[42]], 'sources': ['javit.db'], 'elapsed_ms': 1, 'truncated': false};
  }
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final answers = <String>['{"sql":"SELECT COUNT(*) AS total FROM main.videos"}', 'You have **42** records.'];
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
  test('Bundled worker reads a real database and cancels a running query', () async {
    final folder = await Directory.systemTemp.createTemp('javit-knowledge-test-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/javit.db';
    final setup = await Process.run('python3', ['-B', '-c',
      'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE videos (video_code TEXT)"); c.executemany("INSERT INTO videos VALUES (?)", [("TEST-001",)]*100); c.commit(); c.close()', path]);
    expect(setup.exitCode, 0);
    final knowledge = ChatKnowledge(mainPath: path, loadScript: () => rootBundle.loadString('assets/chat_knowledge.py'));
    final result = await knowledge.request({'sql': 'SELECT COUNT(*) AS total FROM main.videos'}, CancelToken());
    expect(result['rows'], [[100]]);
    final token = CancelToken();
    final timer = Timer(const Duration(milliseconds: 150), () => token.cancel());
    addTearDown(timer.cancel);
    await expectLater(knowledge.request({'sql': 'SELECT count(*) FROM main.videos a, main.videos b, main.videos c, main.videos d, main.videos e'}, token), throwsA(isA<DioException>()));
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
    expect(result, contains('javit.db'));
    expect(knowledge.queries.single['sql'], contains('COUNT(*)'));
    expect(knowledge.directQuery('berapa video saya dengan kualitas 4K'), isNull);
    expect(knowledge.directQuery('jelaskan TEST-123 dibandingkan TEST-456'), isNull);
    expect(knowledge.directQuery('cek kode test-123')!['args'], ['TEST-123', 'TEST-123']);
    expect(knowledge.directQuery('coba check video eyan-181')!['args'], ['EYAN-181', 'EYAN-181']);
    expect(knowledge.directQuery("TEST-123'; DROP TABLE videos"), isNull);
    expect(ChatKnowledge(mainPath: '/local/db').directQuery('TEST-123')!['args'], ['TEST-123']);
    final cover = ChatKnowledge.render({
      'columns': ['title', 'source', 'code'], 'rows': [['Sample', 'R18', 'TEST-001']],
      'covers': {'TEST-001': 'https://example.com/cover.jpg?size=large&n=(1)'},
      'sources': ['db'], 'elapsed_ms': 1, 'truncated': false,
    });
    expect(cover, contains('| Image | Code | Title | source |'));
    expect(cover, contains('![TEST-001](javit-cover:https%3A%2F%2Fexample.com'));
    final rendered = ChatKnowledge.render({'columns': ['title'], 'rows': [['[link](https://example.com)|**text**']], 'sources': ['db'], 'elapsed_ms': 1, 'truncated': true});
    expect(rendered, contains(r'\[link]'));
    expect(rendered, contains(r'\|'));
    expect(rendered, contains('limited result'));
  });

  test('Complex questions use a bounded query, then stream a grounded answer', () async {
    final knowledge = _Knowledge();
    final adapter = _Adapter();
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter, knowledge: knowledge);
    addTearDown(api.close);
    final messages = [{'role': 'user', 'content': 'Count my 4K favorites'}];
    final result = await api.reply(messages, CancelToken()).join();
    expect(adapter.requests.length, 2);
    expect(knowledge.queries.last['sql'], 'SELECT COUNT(*) AS total FROM main.videos');
    expect(result, contains('**42**'));
    expect(result, contains('javit.db'));
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
    expect(result, contains('| TEST-200 | Sample title 200 |'));
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
    final output = await api.reply([{'role': 'user', 'content': 'Cari judul tentang hujan yang belum ada English-nya'}], CancelToken()).join();
    expect(adapter.requests, hasLength(1));
    expect((adapter.requests.first.data['tools'] as List).any((tool) => tool['function']['name'] == 'search_local_titles'), isTrue);
    expect(knowledge.queries.last, {'terms': ['rain', '雨'], 'source': 'r18', 'missing_english': true, 'limit': 25, 'operation': 'search_titles'});
    expect(output, contains('Cross-language title search · rain, 雨'));
    expect(output, contains('Japanese title'));
    expect(output, contains('Matched in'));
    expect(search?['terms'], ['rain', '雨']);
    expect(search?['limit'], 25);
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
    expect(result, contains('javit-translate:'));
    expect(result, contains('javit-similar:TEST-002'));
    expect(saved?['required_terms'], [['outdoor', '屋外']]);
    expect(saved?['unowned'], true);
    expect(saved?['has_more'], true);
    expect(adapter.requests, hasLength(2));
  });

  test('Textual tool markup is hidden and retried using the local tool', () async {
    final knowledge = _Knowledge();
    final adapter = _Adapter()..answers.insert(0, '<tool_call>\n<function=web_search>\n<parameter=query>SELECT * FROM main.videos</parameter>\n</function>\n</tool_call>');
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
