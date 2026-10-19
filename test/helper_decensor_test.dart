import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/utils/helper_decensor.dart';

void main() {
  test('Decensor decodes title entities while preserving literal text', () {
    expect(HelperDecensor.decensor('Hikari Imada&#39;s Swimsuit'), "Hikari Imada's Swimsuit");
    expect(HelperDecensor.decensor('Sister&#x27;s &amp; &quot;S*****t&quot;'), 'Sister\'s & "Student"');
    expect(HelperDecensor.decensor('A <B> &lt;C&gt; &unknown;'), 'A <B> <C> &unknown;');
    expect(HelperDecensor.decensor('Rock & Roll'), 'Rock & Roll');
  });

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

  test('Censored masks overlapping keywords using the longest complete phrase', () {
    const samples = {
      'Abused': 'A****d',
      'Assaulted': 'A*******d',
      'Assaulting': 'A********g',
      'Children': 'C******n',
      'Disgraced': 'D*******d',
      'Drugged': 'D*****d',
      'Drugging': 'D******g',
      'Drugs': 'D***s',
      'Drug': 'D**g',
      'Forced': 'F****d',
      'Forceful': 'F******l',
      'Hypnosis': 'H******s',
      'Hypnotic': 'H******c',
      'Hypnotism': 'H*******m',
      'Hypnotize': 'H*******e',
      'Hypnotized': 'H********d',
      'Kidnap': 'K****p',
      'Kids': 'K**s',
      'Killer': 'K****r',
      'Killing': 'K*****g',
      'Lolicon': 'L*****n',
      'Lolita': 'L****a',
      'Molestation': 'M*********n',
      'Molested': 'M******d',
      'Molester': 'M******r',
      'Molesting': 'M*******g',
      'Punished': 'P******d',
      'Punisher': 'P******r',
      'Punishing': 'P*******g',
      'Raped': 'R***d',
      'Rapes': 'R***s',
      'Rapists': 'R*****s',
      'Scatology': 'S*******y',
      'School Girls': 'S**********s',
      'Schoolgirls': 'S*********s',
      'Shotacon': 'S******n',
      'Students': 'S******s',
      'Tentacles': 'T*******s',
      'Tortured': 'T******d',
      'Violated': 'V******d',
    };
    samples.forEach((word, mask) {
      expect(HelperDecensor.censored(word), mask, reason: word);
      expect(HelperDecensor.decensor(mask), word, reason: mask);
      expect(HelperDecensor.censored(mask), mask, reason: 'mask must stay unchanged');
    });
    expect(HelperDecensor.censored(samples.keys.join(' / ')), samples.values.join(' / '));
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
