import 'package:ex_kit/ex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/data/api/api_javmost.dart';
import 'package:kuraku/app/data/api/api_kuraku.dart';
import 'package:kuraku/app/data/models/__javmost_new_release.dart';

void main() {
  group('JavMost catalogue requests', () {
    // Without the app settings service there is no HTTP client, so every
    // endpoint must fail as a wrapped ApiException instead of leaking the
    // internal dependency error.
    test('all list endpoints fail as ApiException when the client cannot be built', () async {
      final requests = <String, Future<JavMostModel> Function()>{
        'new release': () => ApiJavMost.getNewRelease(),
        'top monthly': () => ApiJavMost.getTopMonthly(page: 2),
        'top weekly': () => ApiJavMost.getTopWeekly(page: 0),
        'top daily': () => ApiJavMost.getTopDaily(),
        'best rating': () => ApiJavMost.getBestRating(page: -3),
        'search': () => ApiJavMost.search(s: ' cosplay nurse '),
        'empty search': () => ApiJavMost.search(),
      };

      for (final entry in requests.entries) {
        await expectLater(entry.value(), throwsA(isA<ApiException>()), reason: entry.key);
      }
    });

    test('the Kuraku search endpoint wraps its failures the same way', () async {
      await expectLater(ApiKuraku.search(s: 'abp'), throwsA(isA<ApiException>()));
      await expectLater(ApiKuraku.search(s: 'abp', provider: kProviderR18, lang: '', page: 0), throwsA(isA<ApiException>()));
      await expectLater(ApiKuraku.getMetadata(code: 'abp-001'), throwsA(isA<ApiException>()));
    });
  });

  group('JavMost payload', () {
    test('parses a full list payload', () {
      final model = JavMostModel.fromJson({
        'success': true,
        'total': 2,
        'result': [
          {'url': 'https://www.javmost.ws/ABP-001/', 'name': 'ABP-001', 'full_name': 'ABP-001 Title', 'cover': 'https://img/abp001.jpg', 'release': '2026-01-02', 'rate': '4.5', 'length': '120', 'maker': 'Prestige'},
          {'name': 'ABP-002'},
        ],
      });

      expect(model.success, isTrue);
      expect(model.total, 2);
      expect(model.result, hasLength(2));
      expect(model.result!.first.name, 'ABP-001');
      expect(model.result!.first.fullName, 'ABP-001 Title');
      expect(model.result!.first.maker, 'Prestige');
      expect(model.result!.last.cover, isNull);
    });

    test('tolerates a missing result list and survives a round trip', () {
      final empty = JavMostModel.fromJson({'success': false, 'total': 0});
      expect(empty.result, isNull);
      expect(empty.toJson().containsKey('result'), isFalse);
      expect(empty.toJson()['success'], isFalse);

      final model = JavMostModel.fromJson({'success': true, 'total': 1, 'result': [{'name': 'ABP-003', 'star': 'Yua'}]});
      final restored = JavMostModel.fromJson(model.toJson());
      expect(restored.result!.single.name, 'ABP-003');
      expect(restored.result!.single.star, 'Yua');
      expect(restored.toJson(), model.toJson());
    });
  });
}
