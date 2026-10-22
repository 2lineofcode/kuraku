import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

const audioNormalizationFilter = 'lavfi=[dynaudnorm=f=150:g=7:p=0.9:m=5]';

Future<bool> applyNativeAudioNormalization(NativePlayer player, {required bool enabled}) async {
  try {
    // Filter commands roll back failed graphs; setProperty drops mpv errors.
    await player.command(['af', 'set', enabled ? audioNormalizationFilter : '']);
    if (enabled && !(await player.getProperty('af')).contains('dynaudnorm')) {
      throw StateError('The audio normalization filter was not applied');
    }
    return enabled;
  } catch (error) {
    debugPrint('Audio normalization failed: $error');
    try { await player.command(['af', 'set', '']); } catch (_) {}
    return false;
  }
}
