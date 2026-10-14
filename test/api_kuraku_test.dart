import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/data/api/api_kuraku.dart';

void main() {
  test('metadata lookups are rejected before any request when the code is invalid', () async {
    for (final code in ['', '   ', 'not-a-code', 'ABP', '12345', 'holiday.mp4']) {
      await expectLater(
        ApiKuraku.getMetadata(code: code),
        throwsA(isA<Exception>()),
        reason: 'code "$code" should never reach the network',
      );
    }
  });

  test('provider identifiers match the backend routes', () {
    expect(kProviderR18, 'r18');
    expect(kProviderNJav, 'njav');
  });
}
