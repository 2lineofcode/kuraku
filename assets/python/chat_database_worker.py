import heapq
import json
import re
import sqlite3
import sys
import time
import unicodedata
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
        'derived_video': 'content_id video_code dvd_id title_en title_ja runtime_mins release_date maker_id label_id series_id site_id jacket_full_url jacket_thumb_url comment_en comment_ja',
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
HALFWIDTH_KANA = {unicodedata.normalize('NFKC', chr(code)): chr(code) for code in range(0xff61, 0xffa0)}


def normalized(value):
    return unicodedata.normalize('NFKC', value).casefold()


def candidate_pattern(value):
    parts = ['*']
    for char in value:
        if char.isspace():
            parts.append('*')
        else:
            decomposed = unicodedata.normalize('NFKD', char)
            variants = {char, decomposed[0]}
            variants.update(form for letter in list(variants) for form in [letter.lower(), letter.upper()])
            variants.update(HALFWIDTH_KANA.get(letter, letter) for letter in list(variants))
            variants.update(chr(ord(letter) + 0xfee0) for letter in list(variants) if len(letter) == 1 and '!' <= letter <= '~')
            letters = ''.join(sorted(letter for letter in variants if len(letter) == 1 and letter not in ']-^'))
            parts.append('[' + (']' if ']' in variants else '') + letters + ('^' if '^' in variants else '') + ('-' if '-' in variants else '') + ']')
            # Exact normalized matching later rejects extra combining-character candidates.
            if len(decomposed) > 1:
                parts.append('*')
    return ''.join(parts) + '*'


def source_fields(schema, source):
    if source == 'library':
        return 'temp.videos', 'video_code', 'title'
    return 'r18.derived_video', 'video_code' if 'video_code' in schema.get('r18.derived_video', []) else 'dvd_id', 'title_en'


def concept_terms(values):
    if not isinstance(values, list) or not 1 <= len(values) <= 12 or any(not isinstance(t, str) or not 1 <= len(t.strip()) <= 100 for t in values):
        raise ValueError('Each concept must contain 1–12 terms of 1–100 characters.')
    terms = {}
    for term in values:
        terms.setdefault(normalized(term.strip()), term.strip())
    return list(terms.values())


def search_concepts(request):
    terms = concept_terms(request.get('terms'))
    groups = []
    for name in ['required_terms', 'related_terms']:
        values = request.get(name, [])
        if not isinstance(values, list) or len(values) > 4:
            raise ValueError(name + ' must contain at most four concepts.')
        groups.append([concept_terms(group) for group in values])
    required, related = groups
    excluded = request.get('exclude_terms', [])
    if not isinstance(excluded, list):
        raise ValueError('exclude_terms must be an array.')
    excluded = concept_terms(excluded) if excluded else []
    used = {normalized(term) for group in [terms] + required for term in group}
    for group in related:
        keys = {normalized(term) for term in group}
        if keys & used:
            raise ValueError('Related concepts must be distinct from mandatory concepts and each other.')
        used.update(keys)
    return terms, required, related, excluded


def translation_sources(schema):
    return [item for item in [
        ('r18.machine_translation', 'source_ja', 'target_en', 'Local translation', ''),
        ('main.chat_translation', 'source_text', 'translated_text', 'Saved translation', " AND target_language = 'id'"),
    ] if all(field in schema.get(item[0], []) for field in [item[1], item[2], *(['target_language'] if item[4] else [])])]


def category_fields(schema):
    if not all(field in schema.get('r18.derived_video_category', []) for field in ['content_id', 'category_id']) or 'id' not in schema.get('r18.derived_category', []):
        return []
    return [field for field in ['name_en', 'name_ja'] if field in schema['r18.derived_category']]


def title_search(request, schema):
    terms, required, related, excluded = search_concepts(request)
    source = request.get('source', 'r18')
    unowned = request.get('unowned', False)
    if type(unowned) is not bool or unowned and source != 'r18':
        raise ValueError('Unowned filtering is available only for the R18 catalog.')
    if request.get('similar_to') is not None:
        reference_code(request['similar_to'])
    limit, offset = request.get('limit', 20), request.get('offset', 0)
    if source not in ('r18', 'library') or type(limit) is not int or not 1 <= limit <= 500 or type(offset) is not int or offset < 0:
        raise ValueError('Invalid search source, limit or offset.')
    if request.get('sort', 'relevance') not in ('relevance', 'newest'):
        raise ValueError('sort must be relevance or newest.')
    if type(request.get('missing_english', False)) is not bool:
        raise ValueError('missing_english must be a boolean.')
    table, code, english = source_fields(schema, source)
    columns = schema.get(table, [])
    if code not in columns:
        raise ValueError('This source has no searchable video metadata.')
    if unowned and 'video_code' not in schema.get('temp.videos', []):
        raise ValueError('Owned library metadata is unavailable.')
    if request.get('missing_english') and 'title_ja' not in columns:
        raise ValueError('This source has no Japanese title metadata.')
    patterns = set()
    for term in terms:
        forms = {term, normalized(term), unicodedata.normalize('NFD', term)}
        forms.add(''.join(HALFWIDTH_KANA.get(char, char) for char in unicodedata.normalize('NFKD', normalized(term))))
        for form in forms:
            parts = [part.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') for part in re.split(r'\s+', form)]
            patterns.add(('like', '%' + '%'.join(parts) + '%'))
        patterns.add(('glob', candidate_pattern(normalized(term))))
    args = []
    def match(field):
        tests = []
        for mode, pattern in sorted(patterns, reverse=True):
            args.append(pattern)
            tests.append(f"{field} LIKE ? ESCAPE '\\'" if mode == 'like' else f'{field} GLOB ?')
        return '(' + ' OR '.join(tests) + ')'
    fields = [field for field in ['title_ja', english, 'comment_en', 'comment_ja', 'description', 'category'] if field in columns]
    tests = [match('v.' + field) for field in fields]
    if 'title_ja' in columns:
        for translation_table, original, translated, label, condition in translation_sources(schema):
            title = 'TRIM(v.title_ja)' if condition else 'v.title_ja'
            tests.append(f"(TRIM(v.title_ja) != '' AND {title} IN (SELECT {original} FROM {translation_table} WHERE {match(translated)}{condition}))")
    if source == 'r18' and 'content_id' in columns:
        names = category_fields(schema)
        if names:
            category_match = ' OR '.join(match('cat.' + field) for field in names)
            tests.append(f'v.content_id IN (SELECT vc.content_id FROM r18.derived_video_category vc WHERE vc.category_id IN (SELECT cat.id FROM r18.derived_category cat WHERE {category_match}))')
    if not tests:
        raise ValueError('This source has no searchable topic metadata.')
    # A code-index scan causes random reads for substring searches; enrich matches by index later.
    sql = f"SELECT DISTINCT v.{code} AS code FROM {table} v NOT INDEXED WHERE v.{code} IS NOT NULL AND TRIM(v.{code}) != '' AND (" + ' OR '.join(tests) + ')'
    return sql, args, terms, limit


def reference_code(code):
    if not isinstance(code, str) or not re.fullmatch(r'[A-Za-z0-9_-]{2,40}', code):
        raise ValueError('Invalid reference code.')
    return code.upper()


def metadata_rows(db, schema, source, codes):
    table, key, english = source_fields(schema, source)
    available = schema.get(table, [])
    if key not in available:
        return []
    fields = [field for field in [english, 'title_ja', 'comment_en', 'comment_ja', 'description', 'category', 'release_date', 'content_id', 'series_id', 'series'] if field in available]
    selected = ','.join([f'{key} AS code', *fields])
    cursor = db.execute(f"SELECT {selected} FROM {table} WHERE {key} IN ({','.join('?' for _ in codes)})", codes)
    return [dict(zip([column[0] for column in cursor.description], row)) for row in cursor]


def category_names(value):
    if not value:
        return []
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            return [value]
    if isinstance(value, dict):
        return [value[field] for field in ['category', 'name', 'name_en', 'name_ja'] if isinstance(value.get(field), str) and value[field].strip()]
    if isinstance(value, list):
        return [name for item in value for name in category_names(item)]
    return []


def metadata_extras(db, schema, rows):
    translations, categories = {}, {}
    titles = sorted({value for row in rows if isinstance(row.get('title_ja'), str) and row['title_ja'].strip() for value in [row['title_ja'], row['title_ja'].strip()]})
    for table, original, translated, label, condition in translation_sources(schema):
        for start in range(0, len(titles), 200):
            batch = titles[start:start + 200]
            for title, text in db.execute(f"SELECT {original},{translated} FROM {table} WHERE {original} IN ({','.join('?' for _ in batch)}){condition}", batch):
                if isinstance(text, str) and text.strip():
                    translations.setdefault((label, title), set()).add(text)
    content_ids = sorted({row['content_id'] for row in rows if row.get('content_id')})
    fields = category_fields(schema)
    if fields:
        for start in range(0, len(content_ids), 200):
            batch = content_ids[start:start + 200]
            for row in db.execute(f"SELECT vc.content_id,{','.join('cat.' + field for field in fields)} FROM r18.derived_video_category vc JOIN r18.derived_category cat ON cat.id = vc.category_id WHERE vc.content_id IN ({','.join('?' for _ in batch)})", batch):
                categories.setdefault(row[0], set()).update(value for value in row[1:] if isinstance(value, str) and value.strip())
    return translations, categories


def best_text(values):
    return min((value for value in values if isinstance(value, str) and value.strip()), key=lambda value: (-len(value.strip()), value), default='')


def document(rows, source, translations, categories):
    english = 'title_en' if source == 'r18' else 'title'
    texts = set()
    for row in rows:
        for field, label, strength in [('title_ja', 'Japanese title', 3), (english, 'Original title', 3), ('comment_en', 'Description', 2), ('comment_ja', 'Description', 2), ('description', 'Description', 2)]:
            if isinstance(row.get(field), str) and row[field].strip():
                texts.add((label, row[field], strength))
        for name in category_names(row.get('category')) + sorted(categories.get(row.get('content_id'), [])):
            texts.add(('Category', name, 1))
        title = row.get('title_ja') or ''
        if title.strip():
            for label in ['Saved translation', 'Local translation']:
                key = title.strip() if label == 'Saved translation' else title
                for text in translations.get((label, key), []):
                    texts.add((label, text, 3))
    japanese = best_text(row.get('title_ja') for row in rows)
    original = best_text(row.get(english) for row in rows)
    title = original or best_text(text for label, text, strength in texts if label == 'Saved translation') or best_text(text for label, text, strength in texts if label == 'Local translation') or japanese
    return title, japanese, original, sorted(texts, key=lambda item: (-item[2], item[0], item[1]))


def concept_pattern(terms):
    alternatives = []
    for i, term in sorted(enumerate(terms), key=lambda item: (-len(normalized(item[1])), normalized(item[1]))):
        term = normalized(term)
        pattern = r'\s+'.join(re.escape(part) for part in re.split(r'\s+', term))
        if term[0].isascii() and term[0].isalnum():
            pattern = r'(?<![a-z0-9_])' + pattern
        if term[-1].isascii() and term[-1].isalnum():
            pattern += r'(?![a-z0-9_])'
        alternatives.append(f'(?P<t{i}>{pattern})')
    return re.compile('|'.join(alternatives))


def evidence_snippet(text, match):
    def original_index(position):
        low, high = 0, len(text)
        while low < high:
            middle = (low + high) // 2
            if len(normalized(text[:middle])) < position:
                low = middle + 1
            else:
                high = middle
        return low
    start, end = original_index(match.start()), original_index(match.end())
    left, right = max(0, start - 45), min(len(text), max(end, start + 100) + 35)
    return ('…' if left else '') + ' '.join(text[left:right].split()) + ('…' if right < len(text) else '')


def ranked_titles(db, schema, request, sql, args, limit, deadline):
    terms, required, related, excluded = search_concepts(request)
    mandatory = []
    for group in [terms] + required:
        if {normalized(term) for term in group} not in [{normalized(term) for term in previous} for previous in mandatory]:
            mandatory.append(group)
    groups = mandatory + related + ([excluded] if excluded else [])
    patterns = [concept_pattern(group) for group in groups]
    owned = {normalized(str(row[0]).strip()) for row in db.execute('SELECT video_code FROM temp.videos WHERE video_code IS NOT NULL')} if request.get('unowned') else set()
    source = request.get('source', 'r18')
    def candidates():
        cursor = db.execute(sql, args)
        while True:
            codes = [row[0] for row in cursor.fetchmany(128)]
            if not codes:
                return
            rows = metadata_rows(db, schema, source, codes)
            translations, categories = metadata_extras(db, schema, rows)
            videos = {}
            for row in rows:
                videos.setdefault(row['code'], []).append(row)
            for code in sorted(videos):
                if time.monotonic() > deadline:
                    raise sqlite3.OperationalError('interrupted')
                if normalized(str(code).strip()) in owned or request.get('similar_to') and normalized(code) == normalized(request['similar_to']):
                    continue
                metadata = videos[code]
                title, japanese, original, texts = document(metadata, source, translations, categories)
                if request.get('missing_english') and (original or not japanese.strip()):
                    continue
                matches = [[] for _ in groups]
                for label, text, strength in texts:
                    value = normalized(text)
                    for i, pattern in enumerate(patterns):
                        match = pattern.search(value)
                        if match:
                            matches[i].append((label, text, strength, match))
                if any(not hits for hits in matches[:len(mandatory)]) or excluded and matches[-1]:
                    continue
                optional = matches[len(mandatory):len(mandatory) + len(related)]
                coverage = sum(bool(hits) for hits in optional)
                strength = sum(max(hit[2] for hit in hits) for hits in matches[:len(mandatory)])
                related_strength = sum(max((hit[2] for hit in hits), default=0) for hits in optional)
                release = max((row.get('release_date') or '' for row in metadata), default='')
                date_rank = -int(re.sub(r'\D', '', release)[:14].ljust(14, '0'))
                relevance = (-coverage, -strength, -related_strength)
                rank = (date_rank, *relevance, code) if request.get('sort') == 'newest' else (*relevance, date_rank, code)
                yield rank, (code, title, japanese, matches, release, groups, len(mandatory))
    offset = request.get('offset', 0)
    page = heapq.nsmallest(offset + limit + 1, candidates(), key=lambda item: item[0])[offset:]
    rows = []
    for rank, (code, title, japanese, matches, release, groups, mandatory_count) in page:
        evidence = []
        for i, hits in enumerate(matches[:mandatory_count + len(related)]):
            if not hits:
                continue
            label, text, strength, match = hits[0]
            role = 'Primary' if i == 0 else f'Required {i}' if i < mandatory_count else f'Related {i - mandatory_count + 1}'
            term = groups[i][int(match.lastgroup[1:])]
            evidence.append(f'{role} [{label}; {term}]: "{evidence_snippet(text, match)}"')
        labels = ','.join(dict.fromkeys(hit[0] for hit in matches[0]))
        rows.append([code, title or None, japanese or None, labels, release or None, '; '.join(evidence)])
    return ['code', 'title', 'title_ja', 'matched_in', 'release_date', 'match_evidence'], rows


def video_reference(db, schema, code):
    code = reference_code(code)
    result = {'code': code}
    categories, series = set(), set()
    for source in ['r18', 'library']:
        rows = metadata_rows(db, schema, source, [code, code.lower()])
        translations, related_categories = metadata_extras(db, schema, rows)
        for field in ['title_en' if source == 'r18' else 'title', 'title_ja', 'comment_en', 'comment_ja', 'description']:
            value = best_text(row.get(field) for row in rows)
            if value and not result.get(field):
                result[field] = value[:3000]
        for row in rows:
            categories.update(category_names(row.get('category')))
            categories.update(related_categories.get(row.get('content_id'), []))
            if isinstance(row.get('series'), str) and row['series'].strip():
                series.add(row['series'].strip())
        ids = list({row['series_id'] for row in rows if row.get('series_id') is not None})
        names = [field for field in ['name_en', 'name_ja'] if field in schema.get('r18.derived_series', [])]
        if ids and names and 'id' in schema['r18.derived_series']:
            for row in db.execute(f"SELECT {','.join(names)} FROM r18.derived_series WHERE id IN ({','.join('?' for _ in ids)})", ids):
                series.update(value for value in row if isinstance(value, str) and value.strip())
    if len(result) == 1 and not categories and not series:
        raise ValueError('Reference video was not found in local metadata.')
    result['title'] = result.get('title_en') or result.get('title') or result.get('title_ja', '')
    result['comment'] = result.get('comment_en') or result.get('comment_ja') or result.get('description', '')
    result['categories'] = sorted(categories)
    if series:
        result['series'] = sorted(series)
    return result


def catalog_query(request, schema):
    operation = request['operation']
    table, key, english = source_fields(schema, 'r18')
    catalog = key in schema.get(table, [])
    if operation in ('catalog_count', 'compare_catalog') and not catalog:
        raise ValueError('R18 catalog metadata is unavailable.')
    if operation == 'catalog_count':
        return f"SELECT COUNT(*) AS catalog_records, COUNT(DISTINCT NULLIF(TRIM({key}), '')) AS unique_videos FROM {table}", []
    if operation == 'compare_catalog':
        if 'video_code' not in schema.get('temp.videos', []):
            raise ValueError('Owned library metadata is unavailable.')
        return f"SELECT (SELECT COUNT(*) FROM temp.videos) AS library_files, (SELECT COUNT(DISTINCT NULLIF(TRIM(video_code), '')) FROM temp.videos) AS unique_owned_videos, (SELECT COUNT(DISTINCT NULLIF(TRIM({key}), '')) FROM {table}) AS unique_catalog_videos, (SELECT COUNT(DISTINCT owned.video_code) FROM temp.videos owned WHERE EXISTS (SELECT 1 FROM {table} catalog WHERE catalog.{key} = owned.video_code)) AS owned_in_catalog", []
    code = reference_code(request.get('code'))
    branches, args = [], []
    for source in ['library', 'r18']:
        table, key, english = source_fields(schema, source)
        columns = schema.get(table, [])
        if key not in columns:
            continue
        title = f"MIN(NULLIF(TRIM({english}), ''))" if english in columns else 'NULL'
        if 'title_ja' in columns:
            title = f"COALESCE({title}, MIN(NULLIF(TRIM(title_ja), '')))"
        release = "MAX(NULLIF(TRIM(release_date), ''))" if 'release_date' in columns else 'NULL'
        label = 'Owned' if source == 'library' else 'R18 catalog'
        branches.append(f"SELECT '{label}' AS source,{key} AS code,{title} AS title,{release} AS release_date FROM {table} WHERE {key} = ? GROUP BY {key}")
        args.append(code)
    if not branches:
        raise ValueError('Local video metadata is unavailable.')
    return ' UNION '.join(branches) + ' ORDER BY source, code, title, release_date', args


def run(request):
    started = time.monotonic()
    deadline = started + (20 if request.get('operation') == 'search_titles' else 10)
    paths = {'main': request['main']}
    if request.get('r18'):
        paths['r18'] = request['r18']
    db = sqlite3.connect(Path(paths['main']).resolve().as_uri() + '?mode=ro', uri=True, timeout=1)
    db.set_progress_handler(lambda: time.monotonic() > deadline, 1000)
    try:
        if 'r18' in paths:
            db.execute('ATTACH DATABASE ? AS r18', (Path(paths['r18']).resolve().as_uri() + '?mode=ro',))
        db.execute('PRAGMA temp_store = MEMORY')
        schema = {}
        for source in paths:
            for table, allowed in TABLES[source].items():
                columns = [row[1] for row in db.execute(f'PRAGMA {source}.table_info("{table}")') if row[1] in allowed.split()]
                if columns:
                    schema[f'{source}.{table}'] = columns
        video_columns = schema.pop('main.videos', [])
        if video_columns:
            stored_columns = [row[1] for row in db.execute('PRAGMA main.table_info(videos)')]
            selected = ','.join('"' + column + '"' for column in video_columns)
            where = ' WHERE is_deleted = 0' if 'is_deleted' in stored_columns else ''
            # A CTE can spoof a view's authorizer context; expose a filtered snapshot instead.
            db.execute(f'CREATE TEMP TABLE videos AS SELECT {selected} FROM main.videos{where}')
            for column in ['video_code', 'id']:
                if column in video_columns:
                    db.execute(f'CREATE INDEX temp.chat_{column} ON videos({column})')
            schema['temp.videos'] = video_columns
        db.execute('PRAGMA query_only = ON')
        if request.get('schema'):
            return {'schema': schema, 'r18_code_column': source_fields(schema, 'r18')[1],
                    'sources': {key: Path(value).name for key, value in paths.items()}}
        search_terms = None
        row_limit = 500
        if request.get('operation') == 'video_reference':
            sql, query_args = 'SELECT 1', []
        elif request.get('operation') == 'search_titles':
            sql, query_args, search_terms, row_limit = title_search(request, schema)
        elif request.get('operation') in ('catalog_count', 'compare_catalog', 'video_lookup'):
            sql, query_args = catalog_query(request, schema)
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
                    sources.add('main' if source == 'temp' else source)
                    return sqlite3.SQLITE_OK
            if action == sqlite3.SQLITE_FUNCTION and column.lower() in FUNCTIONS:
                return sqlite3.SQLITE_OK
            return sqlite3.SQLITE_DENY

        db.set_authorizer(authorize)
        if hasattr(db, 'setlimit'):
            db.setlimit(sqlite3.SQLITE_LIMIT_LENGTH, 100000)
            db.setlimit(sqlite3.SQLITE_LIMIT_COLUMN, 32)
            db.setlimit(sqlite3.SQLITE_LIMIT_EXPR_DEPTH, 200 if search_terms is not None else 30)
        if request.get('operation') == 'video_reference':
            return {'reference': video_reference(db, schema, request.get('code'))}
        reference = video_reference(db, schema, request['similar_to']) if search_terms is not None and request.get('similar_to') else None
        if search_terms is not None:
            columns, rows = ranked_titles(db, schema, request, sql, query_args, row_limit, deadline)
        else:
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
            for column, value in zip(columns, row):
                if isinstance(value, bytes):
                    value = '[binary omitted]'
                    truncated = True
                if isinstance(value, str):
                    limit = min(4000 if column == 'match_evidence' else 1000, remaining)
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
                ('temp.videos', 'video_code', ['fan_art', 'poster']),
                ('r18.derived_video', source_fields(schema, 'r18')[1], ['jacket_full_url', 'jacket_thumb_url']),
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
                **({'related_terms': request.get('related_terms', []), 'sort': request.get('sort', 'relevance'),
                    'missing_english': request.get('missing_english', False)} if search_terms is not None else {}),
                **({'reference': reference} if reference is not None else {}),
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
