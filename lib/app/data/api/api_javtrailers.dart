import 'dart:convert';
import 'dart:io';

mixin ApiJavTrailers {
  static const headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    'Referer': 'https://javtrailers.com/',
  };

  static Future<String> _getPage(String url) async {
    // Cloudflare challenges Dart's TLS client and curl's HTTP/2 requests.
    final result = await Process.run(Platform.isWindows ? 'curl.exe' : 'curl', [
      '--http1.1', '--fail', '--silent', '--show-error', '--location', '--max-time', '20',
      '--user-agent', headers['User-Agent']!, '--referer', headers['Referer']!, url,
    ]);
    if (result.exitCode != 0) throw HttpException('Unable to load JavTrailers: ${result.stderr}', uri: Uri.parse(url));
    return result.stdout as String;
  }

  static Map<String, String>? parseVideo(String html, String code) {
    final match = RegExp(r'''<script\b[^>]*\bid=["']__NUXT_DATA__["'][^>]*>([\s\S]*?)</script>''', caseSensitive: false).firstMatch(html);
    if (match == null) throw const FormatException('JavTrailers page data not found');
    final data = jsonDecode(match.group(1)!);
    if (data is! List) throw const FormatException('Invalid JavTrailers page data');

    String value(dynamic index) => index is int && index >= 0 && index < data.length && data[index] is String ? data[index] as String : '';
    for (final item in data) {
      if (item is! Map || value(item['dvdId']).toUpperCase() != code.trim().toUpperCase()) continue;
      final id = value(item['contentId']);
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) continue;
      return {'content_id': id, 'trailer': value(item['trailerG'])};
    }
    return null;
  }

  static Future<String> getTrailer(String code) async {
    code = code.trim().toUpperCase();
    if (code.isEmpty) throw ArgumentError('Video code is required to find a trailer');
    final search = await _getPage('https://javtrailers.com/search/${Uri.encodeComponent(code)}');
    final result = parseVideo(search, code);
    if (result == null) throw StateError('Trailer not found for $code');
    final page = await _getPage('https://javtrailers.com/video/${result['content_id']}');
    final video = parseVideo(page, code);
    final url = video?['trailer'] ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'media.javtrailers.com' || uri.userInfo.isNotEmpty || !RegExp(r'\.(mp4|m3u8)$', caseSensitive: false).hasMatch(uri.path)) {
      throw StateError('No playable trailer found on JavTrailers for $code');
    }
    return url;
  }
}
