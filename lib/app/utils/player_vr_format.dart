import 'package:path/path.dart' as p;

enum VrProjection { vr180, vr360 }
enum VrLayout { mono, sideBySide, topBottom }

({VrProjection? projection, VrLayout? layout})? detectVrFormat(String path, {Map? stream, Map? formatTags}) {
  final name = p.basenameWithoutExtension(path.replaceAll('\\', '/')).toLowerCase()
      // A catalog number such as ABC-180 is not a projection marker.
      .replaceFirst(RegExp(r'^(?!vr-)[a-z]{2,10}-\d{2,7}(?=$|[._\s\[\]()\-])'), '');
  bool has(String marker) => RegExp('(?:^|[._\\s\\[\\]()\\-])(?:$marker)(?=\$|[._\\s\\[\\]()\\-])').hasMatch(name);
  final vr = has('vr');
  final half = has('(?:vr)?180(?:vr|deg|°)?');
  final full = has('(?:vr)?360(?:vr|deg|°)?');
  VrProjection? projection = half == full ? null : half ? VrProjection.vr180 : VrProjection.vr360;
  final layouts = {
    if (has('mono|2d')) VrLayout.mono,
    if (has('sbs')) VrLayout.sideBySide,
    if (has('tb|ou')) VrLayout.topBottom,
  };
  VrLayout? layout = layouts.length == 1 ? layouts.single : null;
  if (vr && !half && !full) projection = VrProjection.vr180;
  if (vr && layouts.isEmpty) layout = VrLayout.sideBySide;

  final tags = {...?formatTags, if (stream?['tags'] is Map) ...stream!['tags'] as Map};
  dynamic spherical = tags['projection'];
  dynamic stereo = tags['stereo_mode'];
  final sideData = stream?['side_data_list'];
  if (sideData is List) {
    for (final data in sideData.whereType<Map>()) {
      if (data['side_data_type'] == 'Spherical Mapping') spherical = data['projection'];
      if (data['side_data_type'] == 'Stereo 3D') stereo = data['type'];
    }
  }
  if (spherical != null) {
    // Only full equirectangular metadata maps directly to the supported projection.
    if (spherical != 'equirectangular') return null;
    projection = VrProjection.vr360;
  }
  layout = switch (stereo) {
    'side by side' || 'left_right' => VrLayout.sideBySide,
    'top and bottom' || 'top_bottom' => VrLayout.topBottom,
    '2D' || 'mono' => VrLayout.mono,
    null => layout,
    _ => null,
  };
  if (stereo != null && layout == null) return null;
  if (layouts.length > 1 && stereo == null) projection = null;
  if (projection == null && layout == null) return null;
  return (projection: projection, layout: layout);
}
