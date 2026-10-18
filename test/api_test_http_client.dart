import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiTestHttpClient implements HttpClient {
  Map<String, Object?> response = {'code': 200, 'result': []};
  int statusCode = 200;
  Completer<void>? pendingResponse;
  final requests = <Uri>[];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requests.add(url);
    return _Request(response, statusCode, pendingResponse);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  void forEach(void Function(String, List<String>) action) => action('content-type', ['application/json']);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.response, this.statusCode, this.pendingResponse);

  final Map<String, Object?> response;
  final int statusCode;
  final Completer<void>? pendingResponse;

  @override
  final headers = _Headers();

  @override
  Future<HttpClientResponse> close() async {
    await pendingResponse?.future;
    return _Response(response, statusCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.response, this.statusCode);

  final Map<String, Object?> response;

  @override
  final headers = _Headers();
  @override
  final int statusCode;
  @override
  String get reasonPhrase => 'OK';
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => [];

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
    Stream.value(utf8.encode(jsonEncode(response))).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
