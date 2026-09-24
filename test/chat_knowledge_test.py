import importlib.util
import sqlite3
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('chat_knowledge', Path(__file__).parents[1] / 'assets/chat_knowledge.py')
knowledge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(knowledge)


def test_queries():
    with tempfile.TemporaryDirectory() as folder:
        main = Path(folder) / 'javit.db'
        r18 = Path(folder) / 'r18_test.db'
        with sqlite3.connect(main) as db:
            db.executescript('CREATE TABLE videos (id TEXT, video_code TEXT, title TEXT, video_path TEXT, is_favorite INTEGER); CREATE TABLE chat_message (content TEXT);')
            db.executemany('INSERT INTO videos VALUES (?, ?, ?, ?, ?)', [(str(i), 'TEST-001', 'Title', '/private/video', 1) for i in range(30)])
        with sqlite3.connect(r18) as db:
            db.executescript("CREATE TABLE derived_video (content_id TEXT, dvd_id TEXT, title_en TEXT); INSERT INTO derived_video VALUES ('one', 'TEST-001', 'Catalog title');")
        def run(sql, **extra):
            return knowledge.run({'main': str(main), 'r18': str(r18), 'sql': sql, **extra})
        assert run('SELECT count(*) AS total FROM main.videos')['rows'] == [[30]]
        assert run('SELECT title FROM main.videos WHERE video_code = ?', args=["' OR 1=1 --"])['rows'] == []
        joined = run('SELECT DISTINCT v.video_code, r.title_en FROM main.videos v JOIN r18.derived_video r ON r.dvd_id = v.video_code')
        assert joined['rows'] == [['TEST-001', 'Catalog title']]
        assert joined['sources'] == ['javit.db', 'r18_test.db']
        limited = run('SELECT title FROM videos')
        assert not limited['truncated'] and len(limited['rows']) == 30
        assert knowledge.run({'main': str(main), 'schema': True})['schema']['main.videos'] == ['id', 'video_code', 'title', 'is_favorite']
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
            run('SELECT count(*) FROM videos a, videos b, videos c, videos d, videos e, videos f')
        except sqlite3.OperationalError as error:
            assert 'interrupted' in str(error)
        else:
            raise AssertionError('Unbounded query accepted')
        assert run('SELECT count(*) FROM videos')['rows'] == [[30]]
        with sqlite3.connect(main) as db:
            db.execute('ALTER TABLE videos ADD COLUMN fan_art TEXT')
            db.execute("UPDATE videos SET fan_art = 'digital/video/test001/test001pl' WHERE video_code = 'TEST-001'")
        with sqlite3.connect(r18) as db:
            db.execute('ALTER TABLE derived_video ADD COLUMN jacket_full_url TEXT')
            db.execute("UPDATE derived_video SET jacket_full_url = 'https://example.com/catalog.jpg'")
            db.executemany('INSERT INTO derived_video (content_id, dvd_id, title_en) VALUES (?, ?, ?)',
                           [(str(i), f'TEST-{i:03}', 'Sample title ' + 'x' * 400) for i in range(600)])
        with sqlite3.connect(r18) as db:
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
        main, r18 = Path(folder) / 'javit.db', Path(folder) / 'r18.db'
        with sqlite3.connect(main) as db:
            db.execute('CREATE TABLE videos (video_code TEXT, title TEXT, title_ja TEXT)')
            db.execute("INSERT INTO videos VALUES ('LOCAL-001', NULL, '雨の散歩')")
        with sqlite3.connect(r18) as db:
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
        with sqlite3.connect(r18) as db:
            db.execute('DROP TABLE machine_translation')
        assert [row[0] for row in knowledge.run(base)['rows']] == ['TEST-001']
        with sqlite3.connect(r18) as db:
            db.executemany('INSERT INTO derived_video VALUES (?, NULL, ?)', [(f'PAGE-{i:04}', '雨の散歩') for i in range(600)])
        beyond_old_cap = knowledge.run({**base, 'limit': 25, 'offset': 500})
        assert len(beyond_old_cap['rows']) == 25 and beyond_old_cap['rows'][0][0] == 'PAGE-0500'
        assert beyond_old_cap['has_more'] and beyond_old_cap['page_offset'] == 500
        assert knowledge.run({**base, 'offset': 10001})['rows'] == []
        with sqlite3.connect(r18) as db:
            db.execute('ALTER TABLE derived_video ADD COLUMN release_date TEXT')
            db.execute("UPDATE derived_video SET release_date = '2026-09-22' WHERE dvd_id IN ('PAGE-0598', 'PAGE-0599')")
            db.execute("UPDATE derived_video SET release_date = '2020-01-01' WHERE dvd_id = 'PAGE-0597'")
        ordered = knowledge.run({**base, 'limit': 4})
        assert [row[0] for row in ordered['rows']] == ['PAGE-0598', 'PAGE-0599', 'PAGE-0597', 'PAGE-0000']
        assert ordered['columns'][-1] == 'release_date'
        assert knowledge.run({**base, 'limit': 2, 'offset': 2})['rows'][0][0] == 'PAGE-0597'
    print('Cross-language checks passed: Japanese-only, cached translation, evidence, unique codes, paging, literal terms, missing translation table.')


def test_filters_and_similarity():
    with tempfile.TemporaryDirectory() as folder:
        main, r18 = Path(folder) / 'javit.db', Path(folder) / 'r18.db'
        with sqlite3.connect(main) as db:
            db.execute('CREATE TABLE videos (video_code TEXT, title TEXT, title_ja TEXT)')
            db.execute("INSERT INTO videos VALUES ('TEST-002', 'Owned', '')")
        with sqlite3.connect(r18) as db:
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
        assert [r[0] for r in filtered['rows']] == ['TEST-001']
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


if __name__ == '__main__':
    test_queries()
    test_title_search()
    test_filters_and_similarity()
