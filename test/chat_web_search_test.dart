import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/utils/chat_service.dart';
import 'package:kuraku/app/utils/chat_web_search.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }
  @override
  void close({bool force = false}) {}
}

String _event(Map<String, dynamic> delta, [String? reason]) => 'data: ${jsonEncode({'choices': [{'delta': delta, 'finish_reason': reason}]})}\n\n';
String _call({String name = 'web_search', String arguments = '{"query":"Python release"}'}) =>
    [_event({'tool_calls': [{'index': 0, 'id': 'call_1', 'function': {'name': name, 'arguments': arguments}}]}, 'tool_calls'), 'data: [DONE]\n\n'].join();
ResponseBody _stream(String body) => ResponseBody.fromString(body, 200);
ResponseBody _json(Object value, [int code = 200]) => ResponseBody.fromString(jsonEncode(value), code, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

void main() {
  test('Fragmented streaming tool calls execute search and return sources with separate credentials', () async {
    final searchAdapter = _Adapter((_) => _json({'results': [
      {'title': 'Python releases', 'url': 'https://www.python.org/downloads/', 'content': 'Official release information'},
      {'title': 'bad', 'url': 'javascript:alert(1)', 'content': 'ignore'},
    ]}));
    final search = ChatWebSearch(apiKey: 'search-key', dio: Dio()..httpClientAdapter = searchAdapter);
    var count = 0;
    final adapter = _Adapter((_) {
      if (count++ == 0) return _stream([
        _event({'tool_calls': [{'index': 0, 'id': 'call_1', 'function': {'name': 'web_', 'arguments': '{"query":'}}]}),
        _event({'tool_calls': [{'index': 0, 'function': {'name': 'search', 'arguments': '"Python release"}'}}]}, 'tool_calls'), 'data: [DONE]\n\n'].join());
      return _stream([_event({'content': 'Found the official release page.'}, 'stop'), 'data: [DONE]\n\n'].join());
    });
    final api = ChatService(apiKey: 'test-key', webSearch: search, dio: Dio()..httpClientAdapter = adapter);
    addTearDown(api.close);
    final result = await api.reply([{'role': 'user', 'content': 'Search Python releases'}], CancelToken()).join();
    expect(result, contains('**Web sources**'));
    expect(result, contains('[Python releases](https://www.python.org/downloads/)'));
    expect(result, isNot(contains('javascript:')));
    expect(searchAdapter.requests.single.headers['Authorization'], 'Bearer search-key');
    expect(searchAdapter.requests.single.data, isNot(contains('messages')));
    expect(adapter.requests.first.headers['Authorization'], 'Bearer test-key');
    final history = adapter.requests.last.data['messages'] as List;
    expect(history.last['role'], 'tool');
    expect(history.last['tool_call_id'], 'call_1');
    expect(history.last['content'], contains('Official release information'));
  });

  test('Missing key, quota, malformed results and oversized queries report errors', () async {
    final absent = ChatWebSearch(apiKey: '');
    addTearDown(absent.close);
    expect((await absent.search('test', CancelToken()))['error'], contains('TAVILY_API_KEY'));
    var status = 429;
    final adapter = _Adapter((_) => _json({'private': 'server details'}, status));
    final search = ChatWebSearch(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter);
    addTearDown(search.close);
    expect((await search.search('test', CancelToken()))['error'], contains('quota'));
    status = 200;
    expect((await search.search('test', CancelToken()))['error'], contains('invalid response'));
    expect((await search.search('x' * 501, CancelToken()))['error'], contains('500'));
    expect((await search.search('SELECT * FROM main.videos', CancelToken()))['error'], contains('query_local'));
    expect(adapter.requests.length, 2);
    await expectLater(search.search('test', CancelToken()..cancel()), throwsA(isA<DioException>()));
  });

  test('Invalid arguments are returned as tool errors without running a search', () async {
    final searchAdapter = _Adapter((_) => throw StateError('Search must not execute'));
    var count = 0;
    final adapter = _Adapter((_) => count++ == 0 ? _stream(_call(arguments: '{broken')) : _stream(_event({'content': 'Search failed.'}, 'stop')));
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter,
      webSearch: ChatWebSearch(apiKey: 'test', dio: Dio()..httpClientAdapter = searchAdapter));
    addTearDown(api.close);
    expect(await api.reply([{'role': 'user', 'content': 'Search'}], CancelToken()).join(), 'Search failed.');
    expect(adapter.requests.last.data['messages'].last['content'], contains('Invalid search arguments'));
    expect(searchAdapter.requests, isEmpty);
  });

  test('Repeated tool calls stop at the round limit', () async {
    final adapter = _Adapter((_) => _stream(_call()));
    final searchAdapter = _Adapter((_) => _json({'results': []}));
    final api = ChatService(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter,
      webSearch: ChatWebSearch(apiKey: 'test', dio: Dio()..httpClientAdapter = searchAdapter));
    addTearDown(api.close);
    await expectLater(api.reply([{'role': 'user', 'content': 'Search'}], CancelToken()).join(), throwsA(isA<ChatException>()));
    expect(adapter.requests.length, 3);
    expect(adapter.requests.last.data['tool_choice'], 'none');
    expect(searchAdapter.requests.length, 2);
  });

  test('Stop interrupts an in-flight provider request', () async {
    final started = Completer<void>();
    final token = CancelToken();
    final adapter = _Adapter((_) async {
      started.complete();
      await token.whenCancel;
      throw token.cancelError!;
    });
    final search = ChatWebSearch(apiKey: 'test', dio: Dio()..httpClientAdapter = adapter);
    addTearDown(search.close);
    final pending = search.search('test', token);
    await started.future;
    token.cancel();
    await expectLater(pending, throwsA(isA<DioException>()));
  });

  test('Incomplete tool streams never execute a partial call', () async {
    final calls = <Map<String, dynamic>>[];
    final body = [_event({'tool_calls': [{'index': 0, 'id': 'call_1', 'function': {'name': 'web_search', 'arguments': '{"query":'}}]}), 'data: [DONE]\n\n'].join();
    await expectLater(ChatService.decodeEvents(Stream.value(utf8.encode(body)), toolCalls: calls).toList(), throwsA(isA<ChatException>()));
    expect(calls, isEmpty);
  });
}
