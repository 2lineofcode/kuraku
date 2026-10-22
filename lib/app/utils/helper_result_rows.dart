import 'helper_misc.dart';

List<Map<String, dynamic>> resultDownloadRows(Map<String, dynamic> data) {
  if (data['write'] == true) return [];
  final columns = (data['columns'] as List? ?? []).map((column) => '$column'.trim().toLowerCase()).toList();
  if (!columns.contains('video_code') && !columns.contains('dvd_id') && !columns.contains('code')) return [];
  final output = <Map<String, dynamic>>[];
  final codes = <String>{};
  for (final values in (data['rows'] as List? ?? []).whereType<List>()) {
    final row = <String, dynamic>{for (var i = 0; i < columns.length && i < values.length; i++) columns[i]: values[i]};
    final code = HelperMisc.resolveVideoCode(
      videoCode: (row['video_code'] ?? row['code']) is String ? row['video_code'] ?? row['code'] : null,
      title: row['dvd_id'] is String ? row['dvd_id'] : null);
    if (code.isEmpty || !codes.add(code)) continue;
    final duration = num.tryParse('${row['duration'] ?? row['runtime_mins'] ?? ''}');
    final sourceUrl = row['source_url'];
    final cover = (data['covers'] as Map?)?[code];
    output.add({
      'video_code': code,
      'title': '${row['title'] ?? row['title_en'] ?? row['title_ja'] ?? code}',
      'poster': '${row['poster'] ?? row['jacket_thumb_url'] ?? cover ?? ''}',
      'fan_art': '${row['fan_art'] ?? row['jacket_full_url'] ?? row['poster'] ?? row['jacket_thumb_url'] ?? cover ?? ''}',
      'release_date': '${row['release_date'] ?? ''}',
      'duration': duration != null && duration.isFinite ? duration.toInt() : null,
      if (sourceUrl is String && sourceUrl.trim().isNotEmpty) 'source_url': sourceUrl.trim(),
      'trailer': '${row['trailer'] ?? row['sample_url'] ?? ''}',
      'actresses': '${row['actresses'] ?? ''}',
      'categories': '${row['categories'] ?? ''}',
      'series': row['series'] is String ? row['series'] : null,
      'actress_count': row['actress_count'] is int ? row['actress_count'] : null,
    });
  }
  return output;
}
