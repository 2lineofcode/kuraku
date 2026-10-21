from contextlib import closing
import importlib.util
import sqlite3
import tempfile
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('chat_knowledge', Path(__file__).parents[1] / 'assets/python/chat_database_worker.py')
knowledge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(knowledge)


def test_queries():
    with tempfile.TemporaryDirectory() as folder:
        main = Path(folder) / 'kuraku.db'
        r18 = Path(folder) / 'r18_test.db'
        with closing(sqlite3.connect(main)) as db, db:
            db.executescript('CREATE TABLE videos (id TEXT, video_code TEXT, title TEXT, video_path TEXT, is_favorite INTEGER); CREATE TABLE chat_message (content TEXT);')
            db.executemany('INSERT INTO videos VALUES (?, ?, ?, ?, ?)', [(str(i), 'TEST-001', 'Title', '/private/video', 1) for i in range(30)])
        with closing(sqlite3.connect(r18)) as db, db:
            db.executescript("CREATE TABLE derived_video (content_id TEXT, dvd_id TEXT, title_en TEXT); INSERT INTO derived_video VALUES ('one', 'TEST-001', 'Catalog title');")
        def run(sql, **extra):
            return knowledge.run({'main': str(main), 'r18': str(r18), 'sql': sql, **extra})
        with closing(sqlite3.connect(main)) as db, db:
            db.executescript("CREATE TABLE playlist (id TEXT, name TEXT); CREATE TABLE playlist_item (playlist_id TEXT, video_id TEXT, created_at TEXT); INSERT INTO playlist VALUES ('p1','My list'); INSERT INTO playlist_item VALUES ('p1','0','2026');")
        assert run('SELECT p.name, v.video_code FROM playlist p JOIN playlist_item i ON i.playlist_id=p.id JOIN videos v ON v.id=i.video_id')['rows'] == [['My list', 'TEST-001']]
        assert run('SELECT count(*) AS total FROM temp.videos')['rows'] == [[30]]
        assert run('SELECT count(*) AS total FROM temp.videos WHERE title = ?', args=['Title'])['rows'] == [[30]]
        assert run('SELECT title FROM temp.videos WHERE video_code = ?', args=["' OR 1=1 --"])['rows'] == []
        joined = run('SELECT DISTINCT v.video_code, r.title_en FROM temp.videos v JOIN r18.derived_video r ON r.dvd_id = v.video_code')
        assert joined['rows'] == [['TEST-001', 'Catalog title']]
        assert joined['sources'] == ['kuraku.db', 'r18_test.db']
        limited = run('SELECT title FROM videos')
        assert not limited['truncated'] and len(limited['rows']) == 30
        assert knowledge.run({'main': str(main), 'schema': True})['schema']['temp.videos'] == ['id', 'video_code', 'title', 'is_favorite']
        for sql in [
            'DELETE FROM videos', "UPDATE videos SET title = 'changed'", 'DROP TABLE videos',
            "ATTACH DATABASE ':memory:' AS other", 'PRAGMA query_only = OFF',
            'SELECT video_path FROM videos', 'SELECT * FROM chat_message', 'SELECT * FROM sqlite_master',
            "SELECT load_extension('anything')", 'SELECT randomblob(1000000000)',
            'SELECT * FROM pragma_database_list', 'SELECT 1; DELETE FROM videos',
            'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n) SELECT * FROM n',
        ]:
            try:
                run(sql)
            except sqlite3.Error:
                pass
            else:
                raise AssertionError('Unsafe query accepted: ' + sql)
        try:
            with patch.object(knowledge.time, 'monotonic', side_effect=[0, 11]):
                run('SELECT sum(length(a.title)) FROM videos a, videos b, videos c, videos d, videos e, videos f')
        except sqlite3.OperationalError as error:
            assert 'interrupted' in str(error)
        else:
            raise AssertionError('Unbounded query accepted')
        assert run('SELECT count(*) FROM videos')['rows'] == [[30]]
        with closing(sqlite3.connect(main)) as db, db:
            db.execute('ALTER TABLE videos ADD COLUMN fan_art TEXT')
            db.execute("UPDATE videos SET fan_art = 'digital/video/test001/test001pl' WHERE video_code = 'TEST-001'")
        with closing(sqlite3.connect(r18)) as db, db:
            db.execute('ALTER TABLE derived_video ADD COLUMN jacket_full_url TEXT')
            db.execute("UPDATE derived_video SET jacket_full_url = 'https://example.com/catalog.jpg'")
            db.executemany('INSERT INTO derived_video (content_id, dvd_id, title_en) VALUES (?, ?, ?)',
                           [(str(i), f'TEST-{i:03}', 'Sample title ' + 'x' * 400) for i in range(600)])
        with closing(sqlite3.connect(r18)) as db, db:
            db.execute("UPDATE derived_video SET jacket_full_url = 'https://example.com/test002.jpg?size=large' WHERE dvd_id = 'TEST-002'")
        bulk = run('SELECT dvd_id, title_en FROM r18.derived_video ORDER BY dvd_id LIMIT 200')
        assert bulk['covers']['TEST-001'] == 'digital/video/test001/test001pl'
        assert bulk['covers']['TEST-002'] == 'https://example.com/test002.jpg?size=large'
        assert 'TEST-003' not in bulk['covers']
        assert bulk['columns'] == ['code', 'title_en']
        assert len(bulk['rows']) == 200 and not bulk['truncated']
        assert all(len(row[1]) > 400 for row in bulk['rows'] if row[1] != 'Catalog title')
        bounded = run('SELECT dvd_id, title_en FROM r18.derived_video ORDER BY dvd_id')
        assert len(bounded['rows']) == 500 and bounded['truncated']
        assert not (Path(folder) / 'missing.db').exists()
        try:
            knowledge.run({'main': str(Path(folder) / 'missing.db'), 'schema': True})
        except sqlite3.OperationalError:
            pass
        else:
            raise AssertionError('Missing database created')
    print('Local query checks passed: reads, joins, bounds, injection, write denial, timeout, missing DB.')


def test_title_search():
    with tempfile.TemporaryDirectory() as folder:
        main, r18 = Path(folder) / 'kuraku.db', Path(folder) / 'r18.db'
        with closing(sqlite3.connect(main)) as db, db:
            db.execute('CREATE TABLE videos (video_code TEXT, title TEXT, title_ja TEXT)')
            db.execute("INSERT INTO videos VALUES ('LOCAL-001', NULL, '雨の散歩')")
        with closing(sqlite3.connect(r18)) as db, db:
            db.executescript('CREATE TABLE derived_video (dvd_id TEXT, title_en TEXT, title_ja TEXT); CREATE TABLE machine_translation (source_ja TEXT, target_en TEXT);')
            db.executemany('INSERT INTO derived_video VALUES (?, ?, ?)', [
                ('TEST-001', None, '雨の散歩'), ('TEST-001', '', '雨の散歩'),
                ('TEST-002', '  ', '傘を持つ'), ('TEST-003', None, '山の散歩'),
                ('TEST-004', 'A rainy day', '雨の日'), ('TEST-005', '100% sunshine', '晴れ'),
            ])
            db.execute("INSERT INTO machine_translation VALUES ('傘を持つ', 'Walking in the rain')")
        base = {'main': str(main), 'r18': str(r18), 'operation': 'search_titles', 'terms': ['rain', '雨'], 'source': 'r18', 'missing_english': True, 'limit': 20}
        result = knowledge.run(base)
        assert [row[0] for row in result['rows']] == ['TEST-001', 'TEST-002']
        assert result['rows'][0][3] == 'Japanese title'
        assert result['rows'][1][1:4] == ['Walking in the rain', '傘を持つ', 'Local translation']
        assert result['search_terms'] == ['rain', '雨']
        first = knowledge.run({**base, 'limit': 1})
        second = knowledge.run({**base, 'limit': 1, 'offset': 1})
        assert first['truncated'] and not second['truncated']
        assert first['rows'][0][0] != second['rows'][0][0]
        assert knowledge.run({**base, 'source': 'library'})['rows'][0][0] == 'LOCAL-001'
        assert knowledge.run({**base, 'terms': ["' OR 1=1 --"]})['rows'] == []
        literal = knowledge.run({**base, 'terms': ['%'], 'missing_english': False})
        assert [row[0] for row in literal['rows']] == ['TEST-005']
        for invalid in [{'terms': []}, {'terms': ['']}, {'terms': ['x'] * 13}, {'limit': 501}, {'offset': -1}, {'source': 'unknown'}, {'missing_english': 'true'}]:
            try:
                knowledge.run({**base, **invalid})
            except ValueError:
                pass
            else:
                raise AssertionError('Invalid title search accepted')
        with closing(sqlite3.connect(r18)) as db, db:
            db.execute('DROP TABLE machine_translation')
        assert [row[0] for row in knowledge.run(base)['rows']] == ['TEST-001']
        with closing(sqlite3.connect(r18)) as db, db:
            db.executemany('INSERT INTO derived_video VALUES (?, NULL, ?)', [(f'PAGE-{i:04}', '雨の散歩') for i in range(600)])
        beyond_old_cap = knowledge.run({**base, 'limit': 25, 'offset': 500})
        assert len(beyond_old_cap['rows']) == 25 and beyond_old_cap['rows'][0][0] == 'PAGE-0500'
        assert beyond_old_cap['has_more'] and beyond_old_cap['page_offset'] == 500
        assert knowledge.run({**base, 'offset': 10001})['rows'] == []
        with closing(sqlite3.connect(r18)) as db, db:
            db.execute('ALTER TABLE derived_video ADD COLUMN release_date TEXT')
            db.execute("UPDATE derived_video SET release_date = '2026-09-22' WHERE dvd_id IN ('PAGE-0598', 'PAGE-0599')")
            db.execute("UPDATE derived_video SET release_date = '2020-01-01' WHERE dvd_id = 'PAGE-0597'")
        ordered = knowledge.run({**base, 'limit': 4})
        assert [row[0] for row in ordered['rows']] == ['PAGE-0598', 'PAGE-0599', 'PAGE-0597', 'PAGE-0000']
        assert ordered['columns'][4:] == ['release_date', 'match_evidence']
        assert knowledge.run({**base, 'limit': 2, 'offset': 2})['rows'][0][0] == 'PAGE-0597'
    print('Cross-language checks passed: Japanese-only, cached translation, evidence, unique codes, paging, literal terms, missing translation table.')


def test_filters_and_similarity():
    with tempfile.TemporaryDirectory() as folder:
        main, r18 = Path(folder) / 'kuraku.db', Path(folder) / 'r18.db'
        with closing(sqlite3.connect(main)) as db, db:
            db.execute('CREATE TABLE videos (video_code TEXT, title TEXT, title_ja TEXT)')
            db.execute("INSERT INTO videos VALUES ('TEST-002', 'Owned', '')")
        with closing(sqlite3.connect(r18)) as db, db:
            db.executescript('CREATE TABLE derived_video (content_id TEXT, dvd_id TEXT, title_en TEXT, title_ja TEXT, comment_en TEXT, comment_ja TEXT); CREATE TABLE derived_category (id TEXT, name_en TEXT, name_ja TEXT); CREATE TABLE derived_video_category (content_id TEXT, category_id TEXT);')
            db.executemany('INSERT INTO derived_video VALUES (?,?,?,?,?,?)', [
                ('ref', 'REF-001', 'Evening stroll', '夜の散歩', 'An outdoor walk in the rain', ''),
                ('one', 'TEST-001', None, '雨の散歩', 'An outdoor walk', ''),
                ('two', 'TEST-002', None, '雨の散歩', 'An outdoor walk', ''),
                ('three', 'TEST-003', None, '雨の散歩', 'Inside a room', ''),
                ('four', 'TEST-004', None, '雨の散歩', 'An outdoor walk', ''),
                ('five', 'TEST-005', 'A quiet morning', '静かな朝', 'An outdoor walk in the rain', ''),
            ])
            db.execute("INSERT INTO derived_category VALUES ('c', 'Compilation', '総集編')")
            db.execute("INSERT INTO derived_video_category VALUES ('four', 'c')")
        base = {'main': str(main), 'r18': str(r18), 'operation': 'search_titles', 'source': 'r18', 'terms': ['rain', '雨'],
                'required_terms': [['outdoor', '屋外'], ['walk', '散歩']], 'exclude_terms': ['compilation', '総集編'], 'unowned': True, 'limit': 25}
        wide = {**base, 'terms': ['雨'] * 12, 'required_terms': [['walk'] * 12] * 4, 'exclude_terms': ['absent'] * 12}
        assert knowledge.run(wide)['rows']
        filtered = knowledge.run(base)
        assert [r[0] for r in filtered['rows']] == ['TEST-001', 'REF-001', 'TEST-005']
        similar = knowledge.run({**base, 'similar_to': 'REF-001'})
        assert [r[0] for r in similar['rows']] == ['TEST-001', 'TEST-005']
        assert similar['rows'][1][3] == 'Description'
        assert similar['required_terms'] == base['required_terms'] and similar['unowned']
        reference = knowledge.run({**base, 'operation': 'video_reference', 'code': 'REF-001'})
        assert reference['reference']['comment_en'] == 'An outdoor walk in the rain'
        for invalid in [{'similar_to': 'MISSING-001'}, {'required_terms': [['']]}, {'required_terms': 'outdoor'}, {'exclude_terms': ['x'] * 13}, {'unowned': 'true'}, {'source': 'library'}]:
            try:
                knowledge.run({**base, **invalid})
            except ValueError:
                pass
            else:
                raise AssertionError('Invalid filters accepted')
    print('Filter/similarity checks passed: AND concepts, OR synonyms, category exclusion, owned exclusion, reference lookup, description evidence, missing reference.')


def test_saved_translations_and_duplicate_metadata():
    with tempfile.TemporaryDirectory() as folder:
        main, r18 = Path(folder) / 'kuraku.db', Path(folder) / 'r18.db'
        with closing(sqlite3.connect(main)) as db, db:
            db.executescript('CREATE TABLE videos (video_code TEXT, title TEXT); CREATE TABLE chat_translation (source_text TEXT, target_language TEXT, translated_text TEXT);')
            db.execute("INSERT INTO videos VALUES ('LOCAL-001', 'Rain in the park')")
            db.executemany('INSERT INTO chat_translation VALUES (?,?,?)', [
                ('傘の散歩', 'id', 'Hujan di taman'), ('雨の総集編', 'id', 'Hujan di taman kompilasi'),
                (' ', 'id', 'Hujan di taman'), ('晴れ', 'en', 'Hujan di taman'),
            ])
        with closing(sqlite3.connect(r18)) as db, db:
            db.execute('CREATE TABLE derived_video (dvd_id TEXT, title_en TEXT, title_ja TEXT, comment_ja TEXT)')
            db.executemany('INSERT INTO derived_video VALUES (?,?,?,?)', [
                ('DUP-001', '', '雨の散歩', ''), ('DUP-001', 'Rainy walk', '雨の散歩', ''),
                ('SAVED-001', None, ' 傘の散歩 ', ''), ('SAVED-002', None, '雨の総集編', ''),
                ('EMPTY-001', None, ' ', ''), ('LANG-001', None, '晴れ', ''),
                ('REF-001', None, '', ''), ('REF-001', 'Rainy stroll', '雨の散歩', '屋外の散歩'),
            ])
        base = {'main': str(main), 'r18': str(r18), 'operation': 'search_titles', 'source': 'r18', 'terms': ['hujan'],
                'required_terms': [['taman']], 'exclude_terms': ['kompilasi'], 'missing_english': True, 'limit': 25}
        result = knowledge.run(base)
        assert [row[0] for row in result['rows']] == ['SAVED-001']
        assert result['rows'][0][1:4] == ['Hujan di taman', ' 傘の散歩 ', 'Saved translation']
        missing = knowledge.run({**base, 'terms': ['雨'], 'required_terms': [], 'exclude_terms': []})
        assert 'DUP-001' not in [row[0] for row in missing['rows']]
        ordinary = knowledge.run({**base, 'terms': ['rain', 'rainy'], 'required_terms': [], 'exclude_terms': [], 'missing_english': False})
        assert [row[0] for row in ordinary['rows']].count('DUP-001') == 1
        library = knowledge.run({**base, 'source': 'library', 'terms': ['rain'], 'required_terms': [], 'missing_english': False})
        assert library['rows'][0][0] == 'LOCAL-001'
        reference = knowledge.run({**base, 'operation': 'video_reference', 'code': 'REF-001'})
        assert reference['reference']['title_en'] == 'Rainy stroll'
        assert reference['reference']['comment_ja'] == '屋外の散歩'
    print('Metadata checks passed: saved Indonesian translations, filters, duplicate English titles, empty Japanese titles, English-only library, richest reference.')


def test_deleted_videos():
    with tempfile.TemporaryDirectory() as folder:
        main, r18 = Path(folder) / 'kuraku.db', Path(folder) / 'r18.db'
        with closing(sqlite3.connect(main)) as db, db:
            db.executescript("CREATE TABLE videos(id TEXT, video_code TEXT, title TEXT, title_ja TEXT, is_favorite INTEGER, is_deleted INTEGER, poster TEXT); INSERT INTO videos VALUES ('live','LIVE-001','Rain live','雨',1,0,'live.jpg'),('gone','GONE-001','Rain deleted','雨',1,1,'gone.jpg');")
        with closing(sqlite3.connect(r18)) as db, db:
            db.executescript("CREATE TABLE derived_video(dvd_id TEXT, title_en TEXT); INSERT INTO derived_video VALUES ('LIVE-001','Rain live'),('GONE-001','Rain deleted');")
        base = {'main': str(main), 'r18': str(r18)}
        assert knowledge.run({**base, 'sql': 'SELECT COUNT(*) FROM temp.videos'})['rows'] == [[1]]
        assert knowledge.run({**base, 'sql': 'SELECT video_code AS code FROM videos WHERE is_favorite=1'})['rows'] == [['LIVE-001']]
        titles = {'operation': 'search_titles', 'terms': ['Rain'], 'source': 'library', 'limit': 25}
        assert [row[0] for row in knowledge.run({**base, **titles})['rows']] == ['LIVE-001']
        assert [row[0] for row in knowledge.run({**base, **titles, 'source': 'r18', 'unowned': True})['rows']] == ['GONE-001']
        assert knowledge.run({**base, 'sql': "SELECT dvd_id AS code FROM r18.derived_video WHERE dvd_id='GONE-001'"})['covers'] == {}
        for sql in ['SELECT COUNT(*) FROM main.videos', 'SELECT title FROM main.videos', 'SELECT is_deleted FROM temp.videos',
                    'WITH videos AS (SELECT video_code,title,is_deleted FROM main.videos) SELECT * FROM videos',
                    'WITH "videos" AS (SELECT video_code,title FROM main.videos) SELECT * FROM "videos"']:
            try:
                knowledge.run({**base, 'sql': sql})
            except sqlite3.Error:
                pass
            else:
                raise AssertionError('Deleted records exposed: ' + sql)
        try:
            knowledge.run({**base, 'operation': 'video_reference', 'code': 'GONE-001', 'r18': None})
        except ValueError:
            pass
        else:
            raise AssertionError('Deleted reference exposed')
    print('Soft deletion checks passed: counts, favorites, title search, ownership, covers and bypass denial.')


def test_contextual_ranking():
    with tempfile.TemporaryDirectory() as folder:
        main, r18 = Path(folder) / 'kuraku.db', Path(folder) / 'r18.db'
        with closing(sqlite3.connect(main)) as db, db:
            db.executescript('CREATE TABLE videos (video_code TEXT, title TEXT, title_ja TEXT, description TEXT, category TEXT, series TEXT, actress TEXT);')
            db.executemany('INSERT INTO videos VALUES (?,?,?,?,?,?,?)', [
                ('REF-001', 'Library reference', '雨の散歩', 'An outdoor walk in the park', '[{"category":"Outdoor"}]', 'Library series', ''),
                ('ACTOR-001', 'Quiet room', '', '', '[]', '', '[{"name":"Rain"}]'),
            ])
        with closing(sqlite3.connect(r18)) as db, db:
            db.executescript('CREATE TABLE derived_video (content_id TEXT, dvd_id TEXT, title_en TEXT, title_ja TEXT, comment_en TEXT, release_date TEXT, series_id INTEGER); CREATE INDEX code_index ON derived_video(dvd_id); CREATE TABLE derived_category (id INTEGER, name_en TEXT, name_ja TEXT); CREATE TABLE derived_video_category (content_id TEXT, category_id INTEGER); CREATE INDEX category_index ON derived_video_category(category_id, content_id); CREATE INDEX content_index ON derived_video_category(content_id, category_id); CREATE TABLE derived_series (id INTEGER, name_en TEXT, name_ja TEXT);')
            for symbol in ['%', '_', '\\', '*', '?', '[', ']', '^', '-']:
                pattern = knowledge.candidate_pattern(symbol)
                assert db.execute('SELECT ? GLOB ?, ? GLOB ?', (symbol, pattern, 'ordinary', pattern)).fetchone() == (1, 0)
            db.executemany('INSERT INTO derived_video VALUES (?,?,?,?,?,?,?)', [
                ('ref', 'REF-001', 'Evening rain', '', '', '2020-01-01', 1),
                ('good', 'GOOD-001', 'Rain in the park', '雨の公園', 'An outdoor walk near the station', '2020-01-01', None),
                ('copy', 'COPY-001', 'Rain in the park', '雨の公園', 'An outdoor walk near the station', '2020-01-01', None),
                ('broad', 'BROAD-001', 'Rain rain RAIN', '雨', 'Rain again', '2026-01-01', None),
                ('broad2', 'BROAD-001', 'Rain', '雨', '', '2026-01-01', None),
                ('new', 'NEW-001', 'Inside a room', '室内', 'Rain outside the window', '2026-09-01', None),
                ('cat', 'CAT-001', 'Quiet afternoon', '静かな午後', 'An outdoor walk in the park', '2025-01-01', None),
                ('train', 'TRAIN-001', 'Train on a mountain', '', 'An indoor ride', '2026-01-01', None),
                ('rainy', 'RAINY-001', 'Rainy train', '', '', '2026-01-01', None),
                ('trip', 'TRIP-001', 'Rain near a train', '', 'An outdoor walk in the park', '2022-01-01', None),
                ('training', 'TRAINING-001', 'Rain training camp', '', '', '2023-01-01', None),
                ('wide', 'WIDE-001', 'ＲＡＩＮ　ｉｎ　ｔｈｅ　ｐａｒｋ', '', 'An outdoor walk', '2021-01-01', None),
                ('mixed', 'MIXED-001', 'Ｒain', '', '', '2021-01-01', None),
                ('half', 'HALF-001', '', 'ﾋﾟｸﾆｯｸ', 'An outdoor picnic', '2021-01-01', None),
                ('kana', 'KANA-001', '', 'ピｸニック', '', '2021-01-01', None),
                ('accent', 'ACCENT-001', 'CAFÉ', '', '', '2021-01-01', None),
                ('accent2', 'ACCENT-002', 'ＣＡＦＥ́', '', '', '2021-01-01', None),
                ('split1', 'SPLIT-001', 'Rain', '', '', '2024-01-01', None),
                ('split2', 'SPLIT-001', 'Quiet room', '', 'An outdoor walk in the park', '2024-01-01', None),
                ('wild', 'WILD-001', '100% full_score \\ path *?[]', '', '', '', None),
            ])
            db.execute("INSERT INTO derived_category VALUES (1, 'Rain', '雨')")
            db.executemany('INSERT INTO derived_video_category VALUES (?,1)', [('cat',), ('ref',)])
            db.execute("INSERT INTO derived_series VALUES (1, 'Evening series', '夜のシリーズ')")
        base = {'main': str(main), 'r18': str(r18), 'operation': 'search_titles', 'terms': ['rain', '雨'], 'limit': 100}
        def codes(result):
            return [row[0] for row in result['rows']]
        result = knowledge.run(base)
        found = codes(result)
        assert found.index('GOOD-001') < found.index('NEW-001')
        assert 'TRAIN-001' not in found and 'RAINY-001' not in found
        assert found.count('BROAD-001') == 1 and found.count('SPLIT-001') == 1
        assert 'COPY-001' in found and 'GOOD-001' in found
        assert 'WIDE-001' in found
        assert 'MIXED-001' in found
        width_codes = codes(knowledge.run({**base, 'terms': ['rain']}))
        assert 'MIXED-001' in width_codes
        for terms in [['Ｒain'], ['rain', 'Ｒain'], ['Ｒain', 'rain']]:
            assert codes(knowledge.run({**base, 'terms': terms})) == width_codes
        assert codes(knowledge.run({**base, 'terms': ['ピクニック']})) == ['HALF-001', 'KANA-001']
        assert codes(knowledge.run({**base, 'terms': ['café']})) == ['ACCENT-001', 'ACCENT-002']
        category = next(row for row in result['rows'] if row[0] == 'CAT-001')
        assert category[3] == 'Category' and 'Rain' in category[5] and '[Category;' in category[5]
        description = next(row for row in result['rows'] if row[0] == 'NEW-001')
        assert description[3] == 'Description' and 'Rain outside the window' in description[5]
        fullwidth = next(row for row in result['rows'] if row[0] == 'WIDE-001')
        assert 'ＲＡＩＮ' in fullwidth[5]
        assert result['sort'] == 'relevance' and result['missing_english'] is False
        related = [['outdoor', '屋外'], ['park', '公園']]
        contextual = knowledge.run({**base, 'related_terms': related})
        assert codes(contextual).index('GOOD-001') < codes(contextual).index('BROAD-001')
        assert 'BROAD-001' in codes(contextual) and contextual['related_terms'] == related
        good = next(row for row in contextual['rows'] if row[0] == 'GOOD-001')
        assert 'Related 1 [Description; outdoor]' in good[5] and 'Related 2 [Japanese title; 公園]' in good[5]
        synonyms = knowledge.run({**base, 'terms': ['rain', '雨', 'RAIN']})
        assert codes(synonyms) == found
        required = {**base, 'required_terms': related}
        switched = {**base, 'terms': related[1], 'required_terms': [related[0], base['terms']]}
        assert codes(knowledge.run(required)) == codes(knowledge.run(switched))
        assert 'CAT-001' in codes(knowledge.run(switched)) and 'SPLIT-001' in codes(knowledge.run(required))
        excluded = knowledge.run({**base, 'exclude_terms': ['train']})
        assert 'TRIP-001' not in codes(excluded) and 'TRAINING-001' in codes(excluded)
        newest = knowledge.run({**base, 'sort': 'newest'})
        assert codes(newest)[0] == 'NEW-001' and newest['sort'] == 'newest'
        pages = [knowledge.run({**base, 'related_terms': related, 'limit': 3, 'offset': i}) for i in range(0, len(found), 3)]
        assert [code for page in pages for code in codes(page)] == codes(contextual)
        assert all(page['has_more'] for page in pages[:-1]) and not pages[-1]['has_more']
        for term in ['%', '_', '\\', '*', '?', '[', ']']:
            assert codes(knowledge.run({**base, 'terms': [term]})) == ['WILD-001']
        assert codes(knowledge.run({**base, 'source': 'library'})) == ['REF-001']
        assert codes(knowledge.run({**base, 'source': 'library', 'terms': ['outdoor']})) == ['REF-001']
        similar = knowledge.run({**base, 'similar_to': 'REF-001', 'related_terms': related})
        reference = similar['reference']
        assert 'REF-001' not in codes(similar) and 'NEW-001' in codes(similar)
        assert reference['title'] == 'Evening rain' and reference['title_ja'] == '雨の散歩'
        assert reference['comment'] == 'An outdoor walk in the park'
        assert set(reference['categories']) == {'Rain', '雨', 'Outdoor'}
        assert set(reference['series']) == {'Evening series', '夜のシリーズ', 'Library series'}
        for invalid in [{'sort': 'random'}, {'related_terms': 'park'}, {'related_terms': [['']]}, {'related_terms': [['x']] * 5}, {'related_terms': [['rain']]}, {'related_terms': [['park'], ['PARK']]}]:
            try:
                knowledge.run({**base, **invalid})
            except ValueError:
                pass
            else:
                raise AssertionError('Invalid contextual search accepted')
        try:
            with patch.object(knowledge.time, 'monotonic', side_effect=[0, 21]):
                knowledge.run(base)
        except sqlite3.OperationalError as error:
            assert 'interrupted' in str(error)
        else:
            raise AssertionError('Unbounded metadata search accepted')
    print('Context checks passed: source-independent concepts, coverage ranking, evidence, boundaries, literal wildcards, metadata fallback, stable paging and duplicate titles.')


def test_canonical_codes_and_operations():
    with tempfile.TemporaryDirectory() as folder:
        main, r18 = Path(folder) / 'kuraku.db', Path(folder) / 'r18.db'
        with closing(sqlite3.connect(main)) as db, db:
            db.executescript("CREATE TABLE videos (video_code TEXT, title TEXT, release_date TEXT, is_deleted INTEGER); INSERT INTO videos VALUES ('CANON-001','Owned rain','2024-01-01',0),('CANON-001','Other file','2024-01-01',0),('LIB-001','Library only','2025-01-01',0),('GONE-001','Deleted','2026-01-01',1);")
        with closing(sqlite3.connect(r18)) as db, db:
            db.executescript('CREATE TABLE derived_video (content_id TEXT, video_code TEXT, dvd_id TEXT, title_en TEXT, title_ja TEXT, release_date TEXT, jacket_full_url TEXT); CREATE INDEX canonical_index ON derived_video(video_code);')
            db.executemany('INSERT INTO derived_video VALUES (?,?,?,?,?,?,?)', [
                ('one', 'CANON-001', None, 'Rain in the park', '雨の公園', '2020-01-01', 'https://example.com/one.jpg'),
                ('two', 'CANON-001', 'wrong0001', 'Rain duplicate', '雨', '2021-01-01', 'https://example.com/two.jpg'),
                ('three', 'NEW-002', None, 'Rain outside', '雨の外', '2026-01-01', 'https://example.com/new.jpg'),
                ('uncoded', None, 'DVD-ONLY-009', 'Rain uncoded', '', '2026-01-01', ''),
            ])
        base = {'main': str(main), 'r18': str(r18)}
        assert knowledge.run({**base, 'schema': True})['r18_code_column'] == 'video_code'
        count = knowledge.run({**base, 'operation': 'catalog_count'})
        assert count['columns'] == ['catalog_records', 'unique_videos'] and count['rows'] == [[4, 2]]
        assert 'sort' not in count and 'related_terms' not in count
        compare = knowledge.run({**base, 'operation': 'compare_catalog'})
        assert compare['columns'] == ['library_files', 'unique_owned_videos', 'unique_catalog_videos', 'owned_in_catalog']
        assert compare['rows'] == [[3, 2, 2, 1]]
        query = {**base, 'operation': 'search_titles', 'terms': ['rain']}
        result = knowledge.run(query)
        assert [row[0] for row in result['rows']] == ['NEW-002', 'CANON-001']
        assert result['covers']['NEW-002'] == 'https://example.com/new.jpg'
        assert result['covers']['CANON-001'] == 'https://example.com/one.jpg'
        assert [row[0] for row in knowledge.run({**query, 'unowned': True})['rows']] == ['NEW-002']
        assert [row[0] for row in knowledge.run({**query, 'similar_to': 'CANON-001'})['rows']] == ['NEW-002']
        reference = knowledge.run({**base, 'operation': 'video_reference', 'code': 'CANON-001'})['reference']
        assert reference['code'] == 'CANON-001' and reference['title'] == 'Rain in the park'
        lookup = knowledge.run({**base, 'operation': 'video_lookup', 'code': 'canon-001'})
        assert lookup['columns'] == ['source', 'code', 'title', 'release_date']
        assert lookup['rows'] == [['Owned', 'CANON-001', 'Other file', '2024-01-01'], ['R18 catalog', 'CANON-001', 'Rain duplicate', '2021-01-01']]
        assert knowledge.run({**base, 'operation': 'video_lookup', 'code': 'DVD-ONLY-009'})['rows'] == []
        assert knowledge.run({**base, 'operation': 'video_lookup', 'code': 'LIB-001', 'r18': None})['rows'] == [['Owned', 'LIB-001', 'Library only', '2025-01-01']]
        assert knowledge.run({**base, 'sql': 'SELECT 1'})['rows'] == [[1]]
        assert 'sort' not in knowledge.run({**base, 'sql': 'SELECT 1'})
        with closing(sqlite3.connect(r18)) as db, db:
            db.execute('DROP INDEX canonical_index')
            db.execute('ALTER TABLE derived_video DROP COLUMN video_code')
        assert knowledge.run({**base, 'schema': True})['r18_code_column'] == 'dvd_id'
        assert knowledge.run({**base, 'operation': 'catalog_count'})['rows'] == [[4, 2]]
        assert knowledge.run({**base, 'operation': 'video_lookup', 'code': 'DVD-ONLY-009'})['rows'][0][1] == 'DVD-ONLY-009'
    print('Canonical code checks passed: missing DVD IDs, ownership, covers, deduplication, counts, comparison, lookup and legacy fallback.')


if __name__ == '__main__':
    test_queries()
    test_title_search()
    test_filters_and_similarity()
    test_saved_translations_and_duplicate_metadata()
    test_deleted_videos()
    test_contextual_ranking()
    test_canonical_codes_and_operations()
