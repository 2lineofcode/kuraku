import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/utils/chat_service.dart';

class _Adapter implements HttpClientAdapter {
  int status = 200;
  RequestOptions? request;
  String body = 'data: {"choices":[{"delta":{"content":"Halo 👋"},"finish_reason":null}]}\r\n\r\ndata: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n';
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody(Stream.fromIterable(utf8.encode(body).map((byte) => Uint8List.fromList([byte]))), status,
      headers: {Headers.contentTypeHeader: ['text/event-stream']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  test('Chat sends the configured authenticated request and decodes fragmented UTF-8 SSE', () async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = ChatService(dio: dio, apiKey: 'test-key', baseUrl: 'https://provider.example/v1/', model: 'test-model', provider: ' Example provider ');
    addTearDown(api.close);
    final text = await api.reply([{'role': 'user', 'content': 'Hello'}], CancelToken()).join();
    expect(text, 'Halo 👋');
    expect(api.provider, 'Example provider');
    expect(adapter.request!.uri.toString(), 'https://provider.example/v1/chat/completions');
    expect(adapter.request!.headers['Authorization'], 'Bearer test-key');
    expect(adapter.request!.data['model'], 'test-model');
    expect(adapter.request!.data['stream'], isTrue);
    expect(adapter.request!.data['messages'].first['content'], contains('Format responses using Markdown'));
    expect(adapter.request!.data['messages'].last, {'role': 'user', 'content': 'Hello'});
    adapter.status = 401;
    adapter.body = 'private server details';
    await expectLater(api.reply([], CancelToken()).toList(), throwsA(isA<ChatException>().having((e) => e.message, 'safe error', allOf(contains('API key'), isNot(contains('private'))))));
  });

  test('Title translation sends isolated text without tools and validates input', () async {
    final adapter = _Adapter()..body = 'data: {"choices":[{"delta":{"content":"Berjalan di tengah hujan"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n';
    final api = ChatService(dio: Dio()..httpClientAdapter = adapter, apiKey: 'test-key');
    addTearDown(api.close);
    expect(await api.translateTitle('雨の散歩', CancelToken()), 'Berjalan di tengah hujan');
    expect(adapter.request!.data['messages'].last['content'], '雨の散歩');
    expect(adapter.request!.data['tools'], isNull);
    await expectLater(api.translateTitle('', CancelToken()), throwsA(isA<ChatException>()));
    adapter.status = 500;
    await expectLater(api.translateTitle('雨', CancelToken()), throwsA(isA<ChatException>()));
  });

  test('SQL generation sends schema only, no tools, and unwraps fenced SQL', () async {
    final adapter = _Adapter()..body = 'data: ${jsonEncode({'choices': [{'delta': {'content': '```sql\nSELECT id FROM videos LIMIT 10;\n```'}, 'finish_reason': 'stop'}]})}\n\ndata: [DONE]\n\n';
    final api = ChatService(dio: Dio()..httpClientAdapter = adapter, apiKey: 'test-key');
    addTearDown(api.close);
    expect(await api.generateSql('List ten videos', {'videos': ['id', 'title']}, CancelToken()), 'SELECT id FROM videos LIMIT 10;');
    expect(adapter.request!.data['tools'], isNull);
    expect(adapter.request!.data['messages'].first['content'], contains('Never generate DELETE'));
    expect(adapter.request!.data['messages'].first['content'], contains('"videos":["id","title"]'));
    expect(adapter.request!.data['messages'].last['content'], 'List ten videos');
    await expectLater(api.generateSql('', {'videos': ['id']}, CancelToken()), throwsA(isA<ChatException>()));
    await expectLater(api.generateSql('Read', {}, CancelToken()), throwsA(isA<ChatException>()));
    adapter.status = 429;
    adapter.body = 'private error';
    await expectLater(api.generateSql('Read', {'videos': ['id']}, CancelToken()), throwsA(isA<ChatException>().having((e) => e.message, 'safe error', isNot(contains('private error')))));
  });

  test('Protocol tags split across content chunks are not exposed as answers', () async {
    final output = StringBuffer();
    final events = ['<to', 'ol_', 'call>', '<function=web_search>'].map((part) =>
      'data: ${jsonEncode({'choices': [{'delta': {'content': part}}]})}\n\n').join();
    await expectLater(() async {
      await for (final chunk in ChatService.decodeEvents(Stream.value(utf8.encode(events)))) { output.write(chunk); }
    }(), throwsFormatException);
    expect(output.toString(), isEmpty);
    final calls = <Map<String, dynamic>>[];
    final event = 'data: ${jsonEncode({'choices': [{'delta': {'tool_calls': [{'id': 'local_1', 'function': {'name': 'query_local', 'arguments': '{"sql":"SELECT 1"}'}}]}, 'finish_reason': 'tool_calls'}]})}\n\n';
    expect(await ChatService.decodeEvents(Stream.value(utf8.encode(event)), toolCalls: calls).toList(), isEmpty);
    expect(calls.single['function']['name'], 'query_local');
  });

  test('Missing configuration, cancellation and incomplete or malformed streams fail clearly', () async {
    final unnamed = ChatService(apiKey: 'test-key', provider: ' ');
    addTearDown(unnamed.close);
    expect(unnamed.configurationError, contains('provider in AI settings'));
    final api = ChatService(apiKey: '');
    addTearDown(api.close);
    await expectLater(api.reply([], CancelToken()).toList(), throwsA(isA<ChatException>()));
    final configured = ChatService(dio: Dio()..httpClientAdapter = _Adapter(), apiKey: 'test-key');
    addTearDown(configured.close);
    await expectLater(configured.reply([], CancelToken()..cancel()).toList(), throwsA(isA<ChatException>()));
    for (final payload in [
      'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
      'data: {"error":{"message":"private server detail"}}\n\n',
      'data: [DONE]\n\n',
      'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}\n\n',
    ]) {
      await expectLater(ChatService.decodeEvents(Stream.value(utf8.encode(payload))).toList(), throwsA(isA<ChatException>()));
    }
  });
}
