import 'package:dio/dio.dart';

import '../../env.g.dart';

class ChatWebSearch {
  ChatWebSearch({Dio? dio, String? apiKey})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
        _apiKey = (apiKey ?? Env.tavilyApiKey).trim();
  final Dio _dio;
  final String _apiKey;
  bool get configured => _apiKey.isNotEmpty;

  static const tool = {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': 'Search the public web for current facts and sources. Returns excerpts, not full pages. Never send private library data, file paths, credentials or conversation transcripts in a query.',
      'parameters': {
        'type': 'object',
        'properties': {'query': {'type': 'string', 'description': 'A concise public web search query, at most 500 characters.'}},
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  };

  Future<Map<String, dynamic>> search(String query, CancelToken token) async {
    if (token.isCancelled) throw token.cancelError!;
    if (RegExp(r'^\s*(?:```sql\s*)?(?:select|with|insert|update|delete|pragma|attach)\b|\b(?:main|r18)\.', caseSensitive: false).hasMatch(query)) {
      return {'error': 'SQL and local database queries must use query_local, not web_search.'};
    }
    if (!configured) return {'error': 'Web search is not configured. Set TAVILY_API_KEY in .env, run dart run enven, and restart.'};
    if (query.trim().isEmpty || query.length > 500) return {'error': 'Search query must contain 1–500 characters.'};
    try {
      final response = await _dio.post<dynamic>('https://api.tavily.com/search',
        data: {'query': query.trim(), 'search_depth': 'basic', 'max_results': 5, 'include_answer': false, 'include_raw_content': false},
        cancelToken: token,
        options: Options(headers: {'Authorization': 'Bearer $_apiKey'}, followRedirects: false,
          sendTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 20)),
      );
      final data = response.data;
      final rows = data is Map ? data['results'] : null;
      if (rows is! List) return {'error': 'Search provider returned an invalid response.'};
      final results = <Map<String, String>>[];
      for (final row in rows.take(5)) {
        if (row is! Map || row['url'] is! String) continue;
        final uri = Uri.tryParse(row['url']);
        if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
        String limited(Object? value, int length) {
          final text = value is String ? value : '';
          return text.length > length ? text.substring(0, length) : text;
        }
        results.add({'title': limited(row['title'], 200), 'url': uri.toString(),
          'excerpt': limited(row['content'], 1800), 'published_date': limited(row['published_date'], 80)});
      }
      return {'query': query.trim(), 'retrieved_at': DateTime.now().toUtc().toIso8601String(), 'results': results};
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return {'error': switch (error.response?.statusCode) {
        401 || 403 => 'Search provider rejected the API key.',
        429 || 432 || 433 => 'Search rate limit or quota reached. Try again later.',
        _ => 'Web search is unavailable or timed out. Do not invent search results.',
      }};
    }
  }

  void close() => _dio.close(force: true);
}
