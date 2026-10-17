import 'package:ex_kit/ex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/data/api/api_javhey.dart';
import 'package:kuraku/app/data/models/__kuraku_search_entity.dart';
import 'package:kuraku/app/utils/helper_opener.dart';

String card({String title = 'JAV Subtitle Indonesia - ABC-001 A &amp; B', String url = '/video/100/abc-001-title', String image = '//cdn.example.com/cover.webp'}) =>
    '<article class="item"><div class="item_header"><img src="$image"></div><div class="item_content"><h3><a href="$url">$title</a></h3></div></article>';
String page(String contents) => '<html><title>JAVHEY</title><div class="main_content">$contents</div></html>';

void main() {
  test('parses HTML cards, entities, relative URLs and catalogue pagination', () {
    final data = ApiJavHey.parsePage(page('${card(title: 'ABC-001 A &amp; B')}<a class="next page-numbers" href="/videos/jav-sub-indo/page=257">Last</a>'));
    final video = data.result!.single;
    expect([data.page, data.total, data.hasNextPage], [1, null, true]);
    expect([video.videoId, video.videoCode, video.title], ['100', 'ABC-001', 'ABC-001 A & B']);
    expect(video.fanArt, 'https://cdn.example.com/cover.webp');
    expect(video.poster, video.fanArt);
    expect(video.sourceUrl, 'https://javhey.com/video/100/abc-001-title');
    final restored = KurakuSearchResult.fromJson(video.toJson());
    expect(HelperOpener.downloadUrlForVideo(video.videoCode!, sourceUrl: restored.sourceUrl), video.sourceUrl);
    expect(video.releaseDate, isNull);
    expect(video.duration, isNull);
    expect(ApiJavHey.parsePage(page(card())).hasNextPage, isFalse);
  });

  test('explicit engine overrides the source URL', () {
    final urls = {
      'NJAV': 'https://njavtv.com/en/ABC-001-uncensored-leak',
      'MISSAV': 'https://missav.live/en/ABC-001-uncensored-leak',
      'JAVMOST': 'https://www.javmost.ws/ABC-001',
      'SEXTB': 'https://sextb.net/ABC-001',
      'JAVGURU': 'https://jav.guru/?s=ABC-001',
    };
    for (final entry in urls.entries) {
      expect(HelperOpener.downloadUrlForVideo('ABC-001', sourceUrl: 'https://javhey.com/video/100/abc-001-title', searchEngine: entry.key), entry.value);
    }
  });

  test('search excludes non-Indonesian entries and matches complete video codes exactly', () {
    final html = page('${card()}${card(title: 'JAV Subtitle English - ABC-001', url: '/video/101/english')}${card(title: 'JAV Subtitle Indonesia - ABC-002', url: '/video/102/abc-002')}');
    final exact = ApiJavHey.parsePage(html, query: 'abc-001');
    expect(exact.result, hasLength(1));
    expect(exact.result!.single.videoCode, 'ABC-001');
    final titles = ApiJavHey.parsePage(html, query: 'subtitle');
    expect(titles.result!.map((video) => video.videoCode), ['ABC-001', 'ABC-002']);
  });

  test('search pagination follows only the current query, including empty filtered pages', () {
    final html = page('${card(title: 'JAV Subtitle Indonesia - OTHER-001')}<a class="page-numbers" href="/search?s=ABC-001&amp;page=2">2</a><a class="page-numbers" href="/search?s=OTHER&amp;page=99">99</a>');
    final first = ApiJavHey.parsePage(html, query: 'ABC-001');
    expect(first.result, isEmpty);
    expect(first.hasNextPage, isTrue);
    expect(ApiJavHey.parsePage(html, query: 'ABC-001', page: 2).hasNextPage, isFalse);
    expect(ApiJavHey.parsePage(page('<div class="page_404">No videos found for: missing</div>'), query: 'missing').result, isEmpty);
  });

  test('deduplicates links and excludes non-video or unsafe source and cover URLs', () {
    final html = page('${card()}${card()}${card(url: 'https://javhey.com.evil.test/video/100/title')}${card(url: 'https://user:password@javhey.com/video/100/title')}${card(url: 'javascript:alert(1)')}${card(url: '/search?s=ABC-001')}${card(title: 'Announcement', url: '/video/100/announcement')}${card(url: '/video/101/abc-001', image: 'javascript:alert(1)')}');
    final videos = ApiJavHey.parsePage(html).result!;
    expect(videos, hasLength(2));
    expect(videos.last.fanArt, isEmpty);
    for (final url in ['javascript:alert(1)', 'file:///tmp/video.mp4', 'https://user:password@javhey.com/video/100/title']) {
      expect(() => HelperOpener.downloadUrlForVideo('ABC-001', sourceUrl: url), throwsArgumentError);
    }
  });

  test('rejects blocked and changed layouts, and wraps client failures', () async {
    for (final data in [null, {'code': 'error'}, '<html>Verify you are human</html>', page('<p>Unexpected layout</p>')]) {
      expect(() => ApiJavHey.parsePage(data), throwsFormatException);
    }
    await expectLater(ApiJavHey.search(s: 'ABC-001'), throwsA(isA<ApiException>()));
  });
}
