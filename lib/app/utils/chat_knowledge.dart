import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

class ChatKnowledge {
  ChatKnowledge({required this.mainPath, this.r18Path, this.loadScript});
  final Future<String> Function()? loadScript;
  final String mainPath;
  final String? r18Path;

  static const tool = {
    'type': 'function',
    'function': {
      'name': 'query_local',
      'description': 'Read library and R18 metadata using a single read-only SQLite SELECT. For video lists always select dvd_id AS code (R18) or video_code AS code (library), plus title. Results with a code column are displayed directly to the user; do not rewrite them. Use the requested LIMIT up to 500, default 20, with ORDER BY release_date DESC, code ASC (null dates last). Never use web_search for SQL.',
      'parameters': {
        'type': 'object', 'properties': {'sql': {'type': 'string'}},
        'required': ['sql'], 'additionalProperties': false,
      },
    },
  };

  static const searchTool = {
    'type': 'function',
    'function': {
      'name': 'search_local_titles',
      'description': 'Find videos across languages in local titles and cached translations. Translate the user search phrase into precise Japanese and English equivalents and spelling variants, then pass them as terms. Terms are OR alternatives of ONE concept, not unrelated words. Use this for title/topic searches even when English titles are missing. Results use database pagination; the UI fetches subsequent pages without a total result cap. The app uses 25 records per page regardless of limit. Do not broaden the meaning. Use required_terms for additional mandatory concepts (AND between groups, OR within each group), exclude_terms to reject any matching term, and unowned to exclude owned codes. For similarity, first read get_video_reference, derive precise themes from its title and description (not actor names alone), and set similar_to. Similarity matches titles/descriptions using these themes; matched_in explains the evidence. Use query_local for counts or other numeric filters.',
      'parameters': {
        'type': 'object',
        'properties': {
          'terms': {'type': 'array', 'items': {'type': 'string'}, 'minItems': 1, 'maxItems': 12},
          'source': {'type': 'string', 'enum': ['r18', 'library']},
          'required_terms': {'type': 'array', 'maxItems': 4, 'items': {'type': 'array', 'minItems': 1, 'maxItems': 12, 'items': {'type': 'string'}}},
          'exclude_terms': {'type': 'array', 'maxItems': 12, 'items': {'type': 'string'}},
          'unowned': {'type': 'boolean'},
          'similar_to': {'type': 'string', 'description': 'Reference code already read using get_video_reference; excludes that video and searches descriptions as well.'},
          'missing_english': {'type': 'boolean', 'description': 'Only true when explicitly asked for titles without an English/original title.'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 500},
          'offset': {'type': 'integer', 'minimum': 0},
        },
        'required': ['terms', 'source', 'limit'], 'additionalProperties': false,
      },
    },
  };

  static const referenceTool = {
    'type': 'function',
    'function': {
      'name': 'get_video_reference',
      'description': 'Read the actual local title and description of a reference video before finding similar videos. Never invent its themes. Then use search_local_titles with precise translated theme terms and similar_to set to this code. If metadata lacks meaningful themes, ask the user what aspect they want instead of matching actors alone.',
      'parameters': {'type': 'object', 'properties': {'code': {'type': 'string'}}, 'required': ['code'], 'additionalProperties': false},
    },
  };

  // Exact intents only; filtered and conversational questions go to the model.
  Map<String, dynamic>? directQuery(String text) {
    final query = text.trim().toLowerCase().replaceFirst(RegExp(r'[?!.]+$'), '').trim();
    if (const ['berapa jumlah video saya', 'berapa video saya', 'berapa video yang saya punya', 'jumlah video saya', 'total video saya', 'how many videos do i have', 'count my videos'].contains(query)) {
      return {'sql': 'SELECT COUNT(*) AS total_videos FROM main.videos'};
    }
    if (const ['berapa jumlah video r18', 'jumlah video r18', 'total video r18', 'count r18 videos'].contains(query)) {
      return {'sql': 'SELECT COUNT(*) AS catalog_records FROM r18.derived_video'};
    }
    if (const ['tampilkan favorit saya', 'video favorit saya', 'show my favorites'].contains(query)) {
      return {'sql': 'SELECT video_code AS code, title, quality FROM main.videos WHERE is_favorite = 1 ORDER BY release_date DESC, video_code ASC LIMIT 20'};
    }
    final match = RegExp(r'^(?:(?:coba |tolong |please )?(?:cek|cari|lookup|check)(?: (?:kode|video))?\s+)?([a-z]{2,12}-\d{2,7})$').firstMatch(query);
    if (match == null) return null;
    final code = match[1]!.toUpperCase();
    return {
      'sql': "SELECT 'Owned' AS source, video_code AS code, title, release_date FROM main.videos WHERE video_code = ?"
          "${r18Path == null ? '' : " UNION ALL SELECT 'R18 catalog', dvd_id, COALESCE(title_en, title_ja), release_date FROM r18.derived_video WHERE dvd_id = ?"} ORDER BY release_date DESC, code ASC LIMIT 20",
      'args': [code, if (r18Path != null) code],
    };
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> query, CancelToken token) async {
    if (token.isCancelled) throw token.cancelError!;
    final script = await (loadScript?.call() ?? File('assets/chat_knowledge.py').readAsString());
    Process? process;
    for (final candidate in ['python3', '/opt/homebrew/bin/python3', '/usr/local/bin/python3', if (Platform.isWindows) 'python']) {
      if (token.isCancelled) throw token.cancelError!;
      try {
        process = await Process.start(candidate, ['-B', '-c', script]);
        break;
      } on ProcessException { continue; }
    }
    if (process == null) throw StateError('Python 3 is required for local knowledge.');
    final worker = process;
    var finished = false;
    unawaited(token.whenCancel.then((_) { if (!finished) worker.kill(); }));
    final timer = Timer(const Duration(seconds: 15), () => worker.kill(ProcessSignal.sigkill));
    final output = worker.stdout.transform(utf8.decoder).join();
    final errors = worker.stderr.drain<void>();
    try {
      if (token.isCancelled) throw token.cancelError!;
      worker.stdin.writeln(jsonEncode({...query, 'main': mainPath, 'r18': r18Path}));
      await worker.stdin.close();
      final code = await worker.exitCode;
      final text = await output;
      await errors;
      if (token.isCancelled) throw token.cancelError!;
      if (code != 0) throw StateError('Local query timed out or Python could not run.');
      final result = jsonDecode(text) as Map<String, dynamic>;
      if (result['error'] != null) throw StateError(result['error'] as String);
      return result;
    } finally {
      finished = true;
      timer.cancel();
      worker.kill();
    }
  }

  static String displayColumn(String value) {
    final plain = value.toLowerCase().replaceAll(RegExp(r'[\s_\\`*]+'), '');
    return ['dvdid', 'videocode', 'code'].contains(plain) ? 'Code' : value;
  }

  static String normalizeTableHeaders(String content) {
    final lines = content.split('\n');
    String? fence;
    for (var i = 0; i + 1 < lines.length; i++) {
      final marker = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(lines[i])?[1];
      if (marker != null) {
        if (fence == null) { fence = marker; } else if (marker.startsWith(fence)) { fence = null; }
        continue;
      }
      if (fence != null) continue;
      if (!lines[i].contains('|') || !RegExp(r'^\|?:?-{3,}:?(\|:?-{3,}:?)*\|?$').hasMatch(lines[i + 1].replaceAll(RegExp(r'\s'), ''))) continue;
      lines[i] = lines[i].split('|').map((cell) => displayColumn(cell.trim()) == 'Code' ? ' Code ' : cell).join('|');
    }
    return lines.join('\n');
  }

  static String contextContent(String content) {
    var rows = 0;
    final lines = content.split('\n').where((line) => !line.trimLeft().startsWith('|') || ++rows <= 7).join('\n');
    final clipped = lines.length > 12000 ? lines.substring(0, 12000) : lines;
    return '$clipped${rows > 7 || lines.length > 12000 ? '\n[Earlier result abbreviated for context; full data remains in the chat.]' : ''}';
  }

  static String render(Map<String, dynamic> result) {
    String cell(Object? value) => (value ?? '—').toString().replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll('\\', '\\\\').replaceAll('|', r'\|').replaceAll('`', r'\`')
        .replaceAll('*', r'\*').replaceAll('_', r'\_').replaceAll('[', r'\[').replaceAll('<', '&lt;');
    final columns = (result['columns'] as List).map((column) => switch (displayColumn(column.toString()).toLowerCase()) {
      'dvd_id' || 'video_code' || 'code' => 'Code',
      'title' || 'title_en' => 'Title',
      'title_ja' => 'Japanese title',
      'release_date' => 'Release date',
      'matched_in' => 'Matched in',
      _ => column.toString().replaceAll('_', ' '),
    }).toList();
    final rows = result['rows'] as List;
    final codeIndex = columns.indexOf('Code');
    final titleIndex = columns.indexOf('Title');
    final videoList = codeIndex >= 0 && titleIndex >= 0;
    final imageFields = ['image', 'image_url', 'fan_art', 'poster', 'jacket_full_url', 'jacket_thumb_url'];
    final rawColumns = (result['columns'] as List).map((column) => column.toString().toLowerCase()).toList();
    final imageIndex = rawColumns.indexWhere(imageFields.contains);
    final order = videoList ? [codeIndex, titleIndex, ...List.generate(columns.length, (i) => i).where((i) => i != codeIndex && i != titleIndex && !imageFields.contains(rawColumns[i]))]
        : List.generate(columns.length, (i) => i);
    final headers = [if (videoList) 'Image', ...order.map((i) => columns[i]), if (videoList) 'Actions'];
    final covers = result['covers'] as Map? ?? {};
    String rowText(List row) {
      final values = order.map((i) => cell(row[i])).toList();
      if (videoList) {
        final code = row[codeIndex]?.toString() ?? '';
        final cover = (covers[code] ?? (imageIndex >= 0 ? row[imageIndex] : null))?.toString() ?? '';
        values.insert(0, '![${cell(code)}](javit-cover:${Uri.encodeComponent(cover)})');
        final japaneseIndex = rawColumns.indexOf('title_ja');
        final title = (japaneseIndex >= 0 ? row[japaneseIndex] : row[titleIndex])?.toString() ?? '';
        values.add('${RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(title) ? '[Translate](javit-translate:${Uri.encodeComponent(title)}) · ' : ''}'
            '[Similar](javit-similar:${Uri.encodeComponent(code)})');
      }
      return '| ${values.join(' | ')} |';
    }
    final body = rows.isEmpty ? 'Tidak ada hasil / No matches.' : [
      '| ${headers.map(cell).join(' | ')} |',
      '| ${headers.map((_) => '---').join(' | ')} |',
      ...rows.map((row) => rowText(row as List)),
    ].join('\n');
    final filters = <String>[
      if (result['similar_to'] != null) 'Similar themes to ${cell(result['similar_to'])}',
      for (final group in result['required_terms'] as List? ?? []) 'Required: ${(group as List).map(cell).join(' / ')}',
      if ((result['exclude_terms'] as List? ?? []).isNotEmpty) 'Exclude: ${(result['exclude_terms'] as List).map(cell).join(' / ')}',
      if (result['unowned'] == true) 'Not in your library',
    ].join(' · ');
    final terms = (result['search_terms'] as List?)?.map(cell).join(', ');
    final offset = result['page_offset'] as int? ?? 0;
    final count = terms != null && rows.isNotEmpty ? 'Rows ${offset + 1}–${offset + rows.length}' : '${rows.length} records';
    final notice = terms != null && result['has_more'] == true ? 'More matches available on the next page.'
        : result['truncated'] == true ? 'Showing a limited result (up to 500 records). Narrow the filter or request the next batch.' : '';
    return '${filters.isEmpty ? '' : '$filters\n\n'}${terms == null ? '' : 'Cross-language title search · $terms\n\n'}${rows.length > 1 || terms != null ? '$count\n\n' : ''}$body\n\n${notice.isEmpty ? '' : '$notice\n\n'}'
        '_Local · ${(result['sources'] as List).map(cell).join(', ')} · ${result['elapsed_ms']} ms_';
  }
}
