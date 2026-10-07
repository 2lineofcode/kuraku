import json
import re
import sqlite3
import sys
import time
from pathlib import Path


# Only metadata needed for library questions is exposed to the model.
TABLES = {
    'main': {
        'videos': 'id video_code title title_ja actress category release_date duration studio label director series view_count is_favorite filesize quality created_at fan_art poster description',
        'library': 'id alias total_video',
        'playlist': 'id name',
        'playlist_item': 'playlist_id video_id created_at',
        'watch_session': 'video_id video_code watched_seconds created_at',
        'chat_translation': 'source_text target_language translated_text',
    },
    'r18': {
        'derived_video': 'content_id dvd_id title_en title_ja runtime_mins release_date maker_id label_id series_id site_id jacket_full_url jacket_thumb_url comment_en comment_ja',
        'machine_translation': 'source_ja target_en',
        'derived_actress': 'id name_romaji name_kanji name_kana',
        'derived_category': 'id name_en name_ja',
        'derived_maker': 'id name_en name_ja',
        'derived_label': 'id name_en name_ja',
        'derived_series': 'id name_en name_ja',
        'derived_video_actress': 'content_id actress_id ordinality release_date',
        'derived_video_category': 'content_id category_id release_date',
    },
}
FUNCTIONS = set('count sum avg min max total coalesce nullif lower upper trim ltrim rtrim length substr substring replace round abs date datetime strftime julianday ifnull like glob json_extract json_array_length json_valid group_concat distinct'.split())


def title_search(request, schema):
    terms = request.get('terms')
    if not isinstance(terms, list) or not 1 <= len(terms) <= 12 or any(not isinstance(t, str) or not 1 <= len(t.strip()) <= 100 for t in terms):
        raise ValueError('Provide 1–12 translated search terms, each 1–100 characters.')
    terms = list(dict.fromkeys(t.strip() for t in terms))
    required = request.get('required_terms', [])
    excluded = request.get('exclude_terms', [])
    if not isinstance(required, list) or len(required) > 4 or not isinstance(excluded, list) or len(excluded) > 12:
        raise ValueError('Use at most four required concepts and twelve excluded terms.')
    for group in required + ([excluded] if excluded else []):
        if not isinstance(group, list) or not 1 <= len(group) <= 12 or any(not isinstance(t, str) or not 1 <= len(t.strip()) <= 100 for t in group):
            raise ValueError('Each concept must contain 1–12 non-empty translated terms.')
    required = [list(dict.fromkeys(t.strip() for t in group)) for group in required]
    excluded = list(dict.fromkeys(t.strip() for t in excluded))
    source = request.get('source', 'r18')
    unowned = request.get('unowned', False)
    if type(unowned) is not bool or unowned and source != 'r18':
        raise ValueError('Unowned filtering is available only for the R18 catalog.')
    similar = request.get('similar_to')
    if similar is not None and (not isinstance(similar, str) or not re.fullmatch(r'[A-Za-z0-9_-]{2,40}', similar)):
        raise ValueError('Invalid reference code.')
    limit, offset = request.get('limit', 20), request.get('offset', 0)
    if source not in ('r18', 'library') or type(limit) is not int or not 1 <= limit <= 500 or type(offset) is not int or offset < 0:
        raise ValueError('Invalid search source, limit or offset.')
    missing_english = request.get('missing_english', False)
    if type(missing_english) is not bool:
        raise ValueError('missing_english must be a boolean.')
    table, code, english = ('r18.derived_video', 'dvd_id', 'title_en') if source == 'r18' else ('main.videos', 'video_code', 'title')
    columns = schema.get(table, [])
    if code not in columns or not any(field in columns for field in ['title_ja', english]):
        raise ValueError('This source has no searchable title metadata.')
    args, branches = [], []
    def match(field, values=terms):
        for term in values:
            args.append('%' + term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%')
        return '(' + ' OR '.join(f"{field} LIKE ? ESCAPE '\\'" for _ in values) + ')'
    has_english = english in columns
    japanese = 'v.title_ja' if 'title_ja' in columns else 'NULL'
    title = f"COALESCE(NULLIF(TRIM(v.{english}), ''), {japanese})" if has_english else japanese
    release = "NULLIF(TRIM(v.release_date), '')" if 'release_date' in columns else 'NULL'
    base = f"v.{code} IS NOT NULL AND TRIM(v.{code}) != ''"
    if similar:
        base += f" AND v.{code} != ?"
    if unowned and 'video_code' not in schema.get('main.videos', []):
        raise ValueError('Owned library metadata is unavailable.')
    if missing_english:
        if 'title_ja' not in columns:
            raise ValueError('This source has no Japanese title metadata.')
        base += " AND NULLIF(TRIM(v.title_ja), '') IS NOT NULL"
        if has_english:
            base += f" AND NOT EXISTS (SELECT 1 FROM {table} translated WHERE translated.{code} = v.{code} AND NULLIF(TRIM(translated.{english}), '') IS NOT NULL)"
    fields = [*([('title_ja', 'Japanese title')] if 'title_ja' in columns else []), *([(english, 'Original title')] if has_english else [])]
    translations = []
    if 'title_ja' in columns:
        for translation_table, original, translated, label, condition in [
            ('r18.machine_translation', 'source_ja', 'target_en', 'Local translation', ''),
            ('main.chat_translation', 'source_text', 'translated_text', 'Saved translation', " AND t.target_language = 'id'"),
        ]:
            needed = [original, translated, *(['target_language'] if condition else [])]
            if all(field in schema.get(translation_table, []) for field in needed):
                translations.append((translation_table, original, translated, label, condition))
    if similar:
        fields += [(field, 'Description') for field in ['comment_en', 'comment_ja', 'description'] if field in columns]
    for field, label in fields:
        if similar: args.append(similar.upper())
        branches.append(f"SELECT v.{code} AS code, {title} AS title, {japanese} AS title_ja, '{label}' AS matched_in, {release} AS release_date FROM {table} v WHERE {base} AND {match('v.' + field)}")
    for translation_table, original, translated, label, condition in translations:
        if similar: args.append(similar.upper())
        original_title = 'TRIM(v.title_ja)' if translation_table == 'main.chat_translation' else 'v.title_ja'
        branches.append(f"SELECT v.{code} AS code, t.{translated} AS title, v.title_ja AS title_ja, '{label}' AS matched_in, {release} AS release_date FROM {translation_table} t JOIN {table} v ON {original_title} = t.{original} WHERE {base}{condition} AND {match('t.' + translated)}")
    filters = []
    def concept(values):
        fields = [field for field in ['title_ja', english, 'comment_en', 'comment_ja', 'description', 'category'] if field in columns]
        tests = [match('x.' + field, values) for field in dict.fromkeys(fields)]
        for translation_table, original, translated, label, condition in translations:
            original_title = 'TRIM(x.title_ja)' if translation_table == 'main.chat_translation' else 'x.title_ja'
            tests.append(f"EXISTS (SELECT 1 FROM {translation_table} t WHERE t.{original} = {original_title}{condition} AND {match('t.' + translated, values)})")
        if source == 'r18' and 'content_id' in columns and all(f in schema.get('r18.derived_video_category', []) for f in ['content_id', 'category_id']) and all(f in schema.get('r18.derived_category', []) for f in ['id', 'name_en', 'name_ja']):
            tests.append(f"EXISTS (SELECT 1 FROM r18.derived_video_category vc WHERE vc.content_id = x.content_id AND vc.category_id IN (SELECT cat.id FROM r18.derived_category cat WHERE {match('cat.name_en', values)} OR {match('cat.name_ja', values)}))")
        return f"EXISTS (SELECT 1 FROM {table} x WHERE x.{code} = hits.code AND (" + ' OR '.join(tests) + '))'
    filters += [concept(group) for group in required]
    if excluded: filters.append('NOT ' + concept(excluded))
    if unowned: filters.append('NOT EXISTS (SELECT 1 FROM main.videos owned WHERE owned.video_code = hits.code)')
    where = ' WHERE ' + ' AND '.join(filters) if filters else ''
    grouped = "SELECT code, COALESCE(MIN(CASE WHEN matched_in = 'Saved translation' THEN title END), MIN(CASE WHEN matched_in = 'Local translation' THEN title END), MIN(title)) AS title, MIN(title_ja) AS title_ja, GROUP_CONCAT(DISTINCT matched_in) AS matched_in, MAX(release_date) AS release_date FROM (" + ' UNION ALL '.join(branches) + ') GROUP BY code'
    sql = 'SELECT * FROM (' + grouped + ') hits' + where + ' ORDER BY release_date DESC, code ASC LIMIT ? OFFSET ?'
    args.extend([limit + 1, offset])
    return sql, args, terms, limit


def video_reference(db, schema, code):
    if not isinstance(code, str) or not re.fullmatch(r'[A-Za-z0-9_-]{2,40}', code):
        raise ValueError('Invalid reference code.')
    for table, key, fields in [
        ('r18.derived_video', 'dvd_id', ['title_en', 'title_ja', 'comment_en', 'comment_ja']),
        ('main.videos', 'video_code', ['title', 'title_ja', 'description']),
    ]:
        available = schema.get(table, [])
        selected = [field for field in fields if field in available]
        if key not in available or not selected: continue
        richness = ' + '.join(f"LENGTH(TRIM(COALESCE({field}, '')))" for field in selected)
        row = db.execute(f"SELECT {','.join(selected)} FROM {table} WHERE {key} = ? ORDER BY ({richness}) DESC, {','.join(selected)} LIMIT 1", [code.upper()]).fetchone()
        if row and any(str(value or '').strip() for value in row):
            return {'code': code.upper(), **{field: str(value or '')[:3000] for field, value in zip(selected, row)}}
    raise ValueError('Reference video was not found in local metadata.')


def run(request):
    started = time.monotonic()
    paths = {'main': request['main']}
    if request.get('r18'):
        paths['r18'] = request['r18']
    db = sqlite3.connect(Path(paths['main']).resolve().as_uri() + '?mode=ro', uri=True, timeout=1)
    try:
        if 'r18' in paths:
            db.execute('ATTACH DATABASE ? AS r18', (Path(paths['r18']).resolve().as_uri() + '?mode=ro',))
        db.execute('PRAGMA query_only = ON')
        db.execute('PRAGMA temp_store = MEMORY')
        schema = {}
        for source in paths:
            for table, allowed in TABLES[source].items():
                columns = [row[1] for row in db.execute(f'PRAGMA {source}.table_info("{table}")') if row[1] in allowed.split()]
                if columns:
                    schema[f'{source}.{table}'] = columns
        if request.get('schema'):
            return {'schema': schema, 'sources': {key: Path(value).name for key, value in paths.items()}}
        search_terms = None
        row_limit = 500
        if request.get('operation') == 'video_reference':
            sql, query_args = 'SELECT 1', []
        elif request.get('operation') == 'search_titles':
            sql, query_args, search_terms, row_limit = title_search(request, schema)
        else:
            sql, query_args = request.get('sql'), request.get('args', [])
        if not isinstance(sql, str) or not sql.strip() or len(sql) > (32000 if request.get('operation') == 'search_titles' else 8000):
            raise ValueError('Query must contain 1–8000 characters.')
        sources = set()

        def authorize(action, table, column, source, trigger):
            if action == sqlite3.SQLITE_SELECT:
                return sqlite3.SQLITE_OK
            if action == sqlite3.SQLITE_READ:
                if source is None and not column:
                    matches = [key.split('.')[0] for key in schema if key.endswith('.' + table)]
                    source = matches[0] if len(matches) == 1 else None
                allowed = schema.get(f'{source}.{table}')
                if allowed is not None and (not column or column in allowed):
                    sources.add(source)
                    return sqlite3.SQLITE_OK
            if action == sqlite3.SQLITE_FUNCTION and column.lower() in FUNCTIONS:
                return sqlite3.SQLITE_OK
            return sqlite3.SQLITE_DENY

        db.set_authorizer(authorize)
        db.set_progress_handler(lambda: time.monotonic() - started > 10, 1000)
        if hasattr(db, 'setlimit'):
            db.setlimit(sqlite3.SQLITE_LIMIT_LENGTH, 100000)
            db.setlimit(sqlite3.SQLITE_LIMIT_COLUMN, 32)
            db.setlimit(sqlite3.SQLITE_LIMIT_EXPR_DEPTH, 200 if search_terms is not None else 30)
        if request.get('operation') == 'video_reference':
            return {'reference': video_reference(db, schema, request.get('code'))}
        if request.get('similar_to'):
            video_reference(db, schema, request['similar_to'])
        cursor = db.execute(sql, query_args)
        if cursor.description is None:
            raise ValueError('Only read-only queries are supported.')
        columns = ['code' if ''.join(item[0].lower().replace('_', '').split()) in ('dvdid', 'videocode', 'code') else item[0] for item in cursor.description]
        rows = cursor.fetchmany(row_limit + 1)
        truncated = len(rows) > row_limit
        result = []
        remaining = 250000
        for row in rows[:row_limit]:
            if remaining <= 0:
                truncated = True
                break
            clipped = []
            for value in row:
                if isinstance(value, bytes):
                    value = '[binary omitted]'
                    truncated = True
                if isinstance(value, str):
                    limit = min(1000, remaining)
                    if len(value) > limit:
                        value = value[:limit] + '…'
                        truncated = True
                    remaining -= min(len(value), limit)
                clipped.append(value)
            result.append(clipped)
        covers = {}
        if 'code' in columns and result:
            codes = list({str(row[columns.index('code')]) for row in result if row[columns.index('code')]})
            placeholders = ','.join('?' for _ in codes)
            # Fetch covers in batches; missing metadata must not discard query results.
            for table, code, fields in [
                ('main.videos', 'video_code', ['fan_art', 'poster']),
                ('r18.derived_video', 'dvd_id', ['jacket_full_url', 'jacket_thumb_url']),
            ]:
                available = schema.get(table, [])
                fields = [field for field in fields if field in available]
                if not codes or code not in available or not fields:
                    continue
                expressions = [f"MIN(NULLIF({field}, ''))" for field in fields]
                image = 'COALESCE(' + ','.join(expressions) + ')' if len(fields) > 1 else expressions[0]
                try:
                    for value, cover in db.execute(f'SELECT {code}, {image} FROM {table} WHERE {code} IN ({placeholders}) GROUP BY {code}', codes):
                        if isinstance(cover, str) and cover.strip():
                            covers.setdefault(str(value), cover.strip()[:2000])
                except sqlite3.Error:
                    continue
        return {'columns': columns, 'rows': result, 'truncated': truncated,
                'covers': covers, 'search_terms': search_terms, 'has_more': len(rows) > row_limit,
                'page_offset': request.get('offset', 0), 'required_terms': request.get('required_terms', []),
                'exclude_terms': request.get('exclude_terms', []), 'unowned': request.get('unowned', False), 'similar_to': request.get('similar_to'), 'sources': [Path(paths[source]).name for source in sorted(sources)],
                'elapsed_ms': round((time.monotonic() - started) * 1000, 1)}
    finally:
        db.close()


if __name__ == '__main__':
    try:
        result = run(json.load(sys.stdin))
    except (sqlite3.Error, ValueError, KeyError, TypeError) as error:
        result = {'error': 'Local query unavailable or rejected: ' + str(error)[:180]}
    print(json.dumps(result, ensure_ascii=False))
