import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/utils/helper_misc.dart';
import 'package:javit/env.g.dart';

void main() {
  test('manual cover URLs are preserved while legacy DMM paths still resolve', () {
    const cover = 'https://cdn.javmiku.com/wp-content/uploads/2026/05/mida601pl.jpg';
    expect(cover.genImageUrl(), cover);
    expect('  $cover\n'.genImageUrl(), cover);
    expect('https://example.com/coverps.jpg?size=large&token=123'.genImageUrl(), 'https://example.com/coverps.jpg?size=large&token=123');
    expect('https://example.com/coverps.jpg'.genImageUrl(), 'https://example.com/coverps.jpg');
    expect('HTTP://example.com/cover.jpg'.genImageUrl(), 'HTTP://example.com/cover.jpg');
    expect('digital/video/test/testps'.genImageUrl(), '${Env.imgUrl}https://pics.dmm.co.jp/digital/video/test/testpl.jpg');
    expect('digital/video/test/testps.jpg'.genImageUrl(), '${Env.imgUrl}https://pics.dmm.co.jp/digital/video/test/testpl.jpg');
    expect(' '.genImageUrl(), '');
  });

  test('resolves codes from metadata, filename, then title without using parent folders', () {
    expect(HelperMisc.resolveVideoCode(videoCode: ' naac-072 ', videoPath: '/DVES-050.mp4'), 'NAAC-072');
    expect(HelperMisc.resolveVideoCode(videoCode: '', videoPath: '/ABP-001/DVES-050.mp4', title: 'REBD-1062'), 'DVES-050');
    expect(HelperMisc.resolveVideoCode(videoPath: r'C:\ABP-001\MMR-AZ090.mp4'), 'MMR-AZ090');
    expect(HelperMisc.resolveVideoCode(videoPath: '/ABP-001/holiday.mp4'), '');
    expect(HelperMisc.resolveVideoCode(videoCode: 'invalid', title: 'MBDD-2177 title'), 'MBDD-2177');
    expect(HelperMisc.resolveVideoCode(), '');
  });

  test('extracts and validates standard and alphanumeric video codes', () {
    final cases = {
      'MMR-AZ090': 'MMR-AZ090',
      'MBDD-2177': 'MBDD-2177',
      'NAAC-072': 'NAAC-072',
      'REBD-1062': 'REBD-1062',
      'DVES-050': 'DVES-050',
      'dves-050.mp4': 'DVES-050',
      '/Volumes/Movies/DVES-050-en.mp4': 'DVES-050',
      'DVES-050 [Short Video] I ll cum just from my nipples.mp4': 'DVES-050',
      'mmr-az090.mp4': 'MMR-AZ090',
      '[1080p] MBDD-2177-en.mkv': 'MBDD-2177',
      '/Volumes/Movies/NAAC-072-id.mp4': 'NAAC-072',
      r'D:\Movies\REBD-1062-un.mp4': 'REBD-1062',
      'MMR-AZ090-sub.mp4': 'MMR-AZ090',
      'Title_MMR-AZ090_1080p.mp4': 'MMR-AZ090',
      'ABP-001': 'ABP-001',
      'ABP-12345': 'ABP-12345',
    };
    for (final entry in cases.entries) {
      final code = entry.key.getVideoCode();
      expect(code, entry.value, reason: entry.key);
      expect(code.isValidVideoCode(), isTrue, reason: code);
    }
  });

  test('rejects missing codes and invalid digit counts without partial matches', () {
    for (final input in ['', 'holiday.mp4', 'MMR-AZ', 'ABP-1', 'ABP-123456', 'MMR-AZ123456']) {
      expect(input.getVideoCode(), isEmpty, reason: input);
      expect(input.isValidVideoCode(), isFalse, reason: input);
    }
    expect('prefix ABP-001'.isValidVideoCode(), isFalse);
    expect('ABP-001.mp4'.isValidVideoCode(), isFalse);
    expect('mmr-az090'.isValidVideoCode(), isTrue);
    expect('MMR-AZ090-en'.isValidVideoCode(), isTrue);
  });

  test('keeps subtitle and uncensored detection for alphanumeric codes', () {
    expect('MMR-AZ090-en.mp4'.isHasEnSub(), isTrue);
    expect('MMR-AZ090-indo.mp4'.isHasIdSub(), isTrue);
    expect('MMR-AZ090-un.mp4'.isHasUncensored(), isTrue);
    expect('holiday-en.mp4'.isHasEnSub(), isFalse);
    expect('/Volumes/ABP-001-en/holiday.mp4'.isHasEnSub(), isFalse);
    expect('/Volumes/subindo/ABP-001.mp4'.isHasIdSub(), isFalse);
    expect('/Volumes/ABP-001-un/holiday.mp4'.isHasUncensored(), isFalse);
  });
}
