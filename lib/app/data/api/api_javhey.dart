import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart';

import '../../core/app_network.dart';
import '../../utils/helper_misc.dart';
import '../models/__kuraku_search_entity.dart';

mixin ApiJavHey {
  static final _baseUrl = Uri.parse('https://javhey.com');

  static Future<KurakuSearch> search({String s = '', int page = 1}) async {
    if (page < 1) page = 1;
    final query = s.trim();
    final url = query.isEmpty
        ? _baseUrl.resolve('/videos/jav-sub-indo${page > 1 ? '/page=$page' : ''}')
        : _baseUrl.resolve('/search').replace(queryParameters: {'s': query, 'page': '$page'});
    try {
      final response = await Api.get(url.toString(), withCache: false);
      return parsePage(response.data, query: query, page: page);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  static KurakuSearch parsePage(dynamic data, {String query = '', int page = 1}) {
    if (data is! String) throw FormatException('Invalid JavHey response'.tr);
    final document = parse(data);
    final main = document.querySelector('.main_content');
    if (main == null) throw FormatException('JavHey catalogue not found'.tr);
    final cards = main.querySelectorAll('article.item');
    if (cards.isEmpty && !(main.querySelector('.page_404')?.text.contains('No videos found') ?? false)) {
      throw FormatException('JavHey catalogue not found'.tr);
    }
    query = query.trim();
    final exactCode = query.toUpperCase().isValidVideoCode() ? query.getVideoCode() : '';
    final results = <KurakuSearchResult>[];
    final seen = <String>{};
    for (final card in cards) {
      final link = card.querySelector('h3 a');
      final title = link?.text.trim() ?? '';
      if (query.isNotEmpty && !RegExp(r'JAV Subtitle Indonesia|Sub Indo', caseSensitive: false).hasMatch(title)) continue;
      final code = title.getVideoCode();
      if (!code.isValidVideoCode() || exactCode.isNotEmpty && code != exactCode) continue;
      final href = Uri.tryParse(link?.attributes['href'] ?? '');
      if (href == null) continue;
      final url = _baseUrl.resolveUri(href);
      final id = RegExp(r'^/video/(\d+)/[^/]+/?$').firstMatch(url.path)?.group(1);
      if (url.scheme != 'https' || !['javhey.com', 'www.javhey.com'].contains(url.host) || url.userInfo.isNotEmpty || id == null || !seen.add(url.toString())) continue;
      final image = Uri.tryParse(card.querySelector('img')?.attributes['src'] ?? '');
      final cover = image == null || image.toString().isEmpty ? null : _baseUrl.resolveUri(image);
      final safeCover = cover != null && ['https', 'http'].contains(cover.scheme) && cover.host.isNotEmpty && cover.userInfo.isEmpty ? cover.toString() : '';
      results.add(KurakuSearchResult(videoId: id, videoCode: code, title: title, sourceUrl: url.toString(), fanArt: safeCover, poster: safeCover));
    }
    final hasNextPage = main.querySelectorAll('a.page-numbers').any((link) {
      final href = Uri.tryParse(link.attributes['href'] ?? '');
      if (href == null) return false;
      final url = _baseUrl.resolveUri(href);
      if (url.host != _baseUrl.host || url.userInfo.isNotEmpty) return false;
      final matchesQuery = query.isEmpty ? url.path.startsWith('/videos/jav-sub-indo/page=') : url.path == '/search' && url.queryParameters['s'] == query;
      final next = int.tryParse(url.queryParameters['page'] ?? RegExp(r'/page=(\d+)/?$').firstMatch(url.path)?.group(1) ?? '') ?? 0;
      return matchesQuery && next > page;
    });
    return KurakuSearch(code: 200, page: page, hasNextPage: hasNextPage, result: results);
  }
}
