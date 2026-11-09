import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/utils/player_vr_format.dart';

void main() {
  test('filename markers are case insensitive, bounded and limited to the basename', () {
    for (final path in ['/movies/ABC-123-VR.mp4', r'C:\movies\ABC-123-vr.mkv']) {
      expect(detectVrFormat(path), (projection: VrProjection.vr180, layout: VrLayout.sideBySide));
    }
    expect(detectVrFormat('VR-180-SBS.mp4'), (projection: VrProjection.vr180, layout: VrLayout.sideBySide));
    expect(detectVrFormat('VR-360-TB.mp4'), (projection: VrProjection.vr360, layout: VrLayout.topBottom));
    expect(detectVrFormat('Movie_360_TB.mp4'), (projection: VrProjection.vr360, layout: VrLayout.topBottom));
    expect(detectVrFormat('Movie [VR180] [SBS].mkv'), (projection: VrProjection.vr180, layout: VrLayout.sideBySide));
    expect(detectVrFormat('Movie.180VR.MONO.mp4'), (projection: VrProjection.vr180, layout: VrLayout.mono));
    expect(detectVrFormat('Movie_360_OU.mp4')?.layout, VrLayout.topBottom);
    expect(detectVrFormat('Movie_SBS.mp4'), (projection: null, layout: VrLayout.sideBySide));
    for (final path in ['ABC-180.mp4', 'ABC-360.mp4', '/VR/ordinary.mp4', 'VRaptor.mp4', 'Movie_1800.mp4', 'ordinary.mp4']) {
      expect(detectVrFormat(path), isNull, reason: path);
    }
  });

  test('ambiguous names do not choose a projection automatically', () {
    expect(detectVrFormat('Movie_180_360_SBS.mp4')?.projection, isNull);
    expect(detectVrFormat('Movie_VR_SBS_TB.mp4'), isNull);
  });

  test('stream side data overrides tags and filename hints', () {
    expect(detectVrFormat('Movie_180_SBS.mp4', formatTags: {'stereo_mode': 'left_right'}, stream: {
      'tags': {'stereo_mode': 'mono'},
      'side_data_list': [null, 'invalid',
        {'side_data_type': 'Spherical Mapping', 'projection': 'equirectangular'},
        {'side_data_type': 'Stereo 3D', 'type': 'top and bottom'},
      ],
    }), (projection: VrProjection.vr360, layout: VrLayout.topBottom));
    expect(detectVrFormat('Movie_VR.mp4', stream: {'tags': {'stereo_mode': 'mono'}})?.layout, VrLayout.mono);
    expect(detectVrFormat('ordinary.mp4', formatTags: {'projection': 'equirectangular', 'stereo_mode': 'left_right'}),
      (projection: VrProjection.vr360, layout: VrLayout.sideBySide));
    expect(detectVrFormat('Movie_VR.mp4', stream: {'side_data_list': 'invalid'}),
      (projection: VrProjection.vr180, layout: VrLayout.sideBySide));
  });

  test('unsupported metadata stays manual instead of guessing a supported format', () {
    for (final projection in ['cubemap', 'tiled equirectangular', 'fisheye']) {
      expect(detectVrFormat('Movie_180_SBS.mp4', stream: {'side_data_list': [
        {'side_data_type': 'Spherical Mapping', 'projection': projection},
      ]}), isNull);
    }
    expect(detectVrFormat('Movie_VR.mp4', stream: {'tags': {'stereo_mode': 'row_interleaved'}}), isNull);
  });
}
