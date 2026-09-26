import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/utils/helper_decensor.dart';

void main() {
  test('Decensor restores masked keywords and leaves the surrounding text untouched', () {
    expect(HelperDecensor.decensor('R**e'), 'Rape');
    expect(HelperDecensor.decensor('S********l'), 'Schoolgirl');
    expect(HelperDecensor.decensor('S*********l'), 'School Girl');
    expect(HelperDecensor.decensor('The S*****t was A****p, then D*****d'), 'The Student was Asleep, then Drugged');
    expect(HelperDecensor.decensor('nothing to unmask here'), 'nothing to unmask here');
    expect(HelperDecensor.decensor('M************n'), 'Mother And Son');
  });

  test('Decensor and censored treat null and blank input as an empty string', () {
    for (final value in [null, '']) {
      expect(HelperDecensor.decensor(value), '');
      expect(HelperDecensor.censored(value), '');
    }
    // A whitespace-only string is not "empty" for the helper, so it is returned as-is.
    expect(HelperDecensor.decensor('  '), '  ');
    expect(HelperDecensor.censored('  '), '  ');
  });

  test('Censored masks known keywords but only on an exact case-sensitive match', () {
    expect(HelperDecensor.censored('Rape'), 'R**e');
    expect(HelperDecensor.censored('Slave'), 'S***e');
    expect(HelperDecensor.censored('Torture and Violence'), 'T*****e and V******e');
    expect(HelperDecensor.censored('rape'), 'rape');
    expect(HelperDecensor.censored('RAPE'), 'RAPE');
  });

  test('Censored replaces the first matching keyword, so shorter words win over longer ones', () {
    // 'Drug' is registered before 'Drugged', and 'Hypno' before 'Hypnosis'.
    expect(HelperDecensor.censored('Drugged'), 'D**gged');
    expect(HelperDecensor.censored('Hypnosis'), 'H***osis');
    expect(HelperDecensor.censored('Drug'), 'D**g');
  });

  test('Both directions are idempotent and survive a full round trip', () {
    const sentences = [
      'Rape',
      'The Student was Asleep',
      'Drugged and Hypnosis',
      'Schoolgirl meets School Girl',
      'plain sentence without keywords',
    ];
    for (final sentence in sentences) {
      final masked = HelperDecensor.censored(sentence);
      expect(HelperDecensor.decensor(masked), sentence, reason: 'round trip failed for "$sentence"');
      expect(HelperDecensor.decensor(HelperDecensor.decensor(masked)), sentence);
      expect(HelperDecensor.censored(masked), masked, reason: 'masking twice should not change "$masked"');
    }
  });

  test('Every mask keeps the first and last character of the original keyword', () {
    const samples = {
      'A***e': 'Abuse',
      'K**********n': 'Kindergarten',
      'U*********s': 'Unconscious',
      'Y********l': 'Young Girl',
      'C*********a': 'Coprophilia',
    };
    samples.forEach((mask, word) {
      expect(HelperDecensor.decensor(mask), word);
      expect(mask.length, word.length, reason: '$mask should keep the length of $word');
      expect(mask[0], word[0]);
      expect(mask[mask.length - 1], word[word.length - 1]);
    });
  });
}
