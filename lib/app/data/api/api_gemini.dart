import 'package:dio/dio.dart';

import '../../core/app_pref.dart';

mixin ApiGemini {
  static final _dio = Dio(
    BaseOptions(
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<List<double>> embedText(String content) async {
    final apiKey = AppPref.getGeminiApiKey();
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key is empty');
    }

    final response = await _dio.post(
      '/models/${AppPref.getSemanticSearchModel()}:embedContent',
      data: {
        'model': 'models/${AppPref.getSemanticSearchModel()}',
        'content': {
          'parts': [
            {'text': content}
          ]
        }
      },
      options: Options(
        headers: {
          'x-goog-api-key': apiKey,
          'Content-Type': 'application/json',
        },
      ),
    );

    final data = response.data;
    final vector = _extractEmbeddingValues(data);
    if (vector.isEmpty) {
      throw Exception('Gemini embedding response is empty');
    }
    return vector;
  }

  static List<double> _extractEmbeddingValues(dynamic data) {
    if (data is Map<String, dynamic>) {
      final direct = data['embedding'];
      final directValues = _valuesFromNode(direct);
      if (directValues.isNotEmpty) return directValues;

      final many = data['embeddings'];
      if (many is List && many.isNotEmpty) {
        for (final item in many) {
          final values = _valuesFromNode(item);
          if (values.isNotEmpty) return values;
        }
      }
    }
    return <double>[];
  }

  static List<double> _valuesFromNode(dynamic node) {
    if (node is Map<String, dynamic>) {
      final values = node['values'];
      if (values is List) {
        return values.map((e) => (e as num).toDouble()).toList();
      }

      final nested = node['embedding'];
      if (nested != null) return _valuesFromNode(nested);
    }
    return <double>[];
  }
}
