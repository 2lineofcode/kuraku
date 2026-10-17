from contextlib import closing
import runpy
import sqlite3
from pathlib import Path


importer = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'assets/r18_database_importer.py'))
create_video_codes = importer['create_video_codes']


def database():
    conn = sqlite3.connect(':memory:')
    conn.execute('CREATE TABLE derived_video(content_id TEXT, dvd_id TEXT, service_code TEXT, series_id INTEGER, release_date TEXT, title_en TEXT, title_ja TEXT)')
    conn.executemany('INSERT INTO derived_video(content_id,dvd_id,service_code,series_id,release_date) VALUES (?, ?, ?, 1, NULL)', [
        ('n_1541naac066', None, 'mono'),
        ('n_1541naac066tk', None, 'mono'),
        ('118abp00001', '', 'digital'),
        ('h_090cns00003', 'CNS-03', 'mono'),
        ('h_090cns00004', None, 'digital'),
        ('ebook001', None, 'ebook'),
        ('invalid', None, 'digital'),
        ('xyz999999', None, 'digital'),
    ])
    conn.commit()
    return conn


if __name__ == '__main__':
    with closing(database()) as conn, conn:
        before = conn.execute('SELECT content_id, dvd_id FROM derived_video').fetchall()
        conn.execute("CREATE TRIGGER fail_migration BEFORE UPDATE ON derived_video BEGIN SELECT RAISE(ABORT, 'forced failure'); END")
        try:
            create_video_codes(conn)
        except sqlite3.IntegrityError:
            pass
        else:
            raise AssertionError('Migration must fail')
        assert 'video_code' not in [row[1] for row in conn.execute('PRAGMA table_info(derived_video)')]
        assert conn.execute('SELECT content_id, dvd_id FROM derived_video').fetchall() == before
        conn.execute('DROP TRIGGER fail_migration')
        create_video_codes(conn)
        expected = [('NAAC-066',), (None,), ('ABP-001',), ('CNS-03',), ('CNS-04',), (None,), (None,), (None,)]
        assert conn.execute('SELECT video_code FROM derived_video ORDER BY rowid').fetchall() == expected
        create_video_codes(conn)
        assert conn.execute('SELECT video_code FROM derived_video ORDER BY rowid').fetchall() == expected
        assert conn.execute('SELECT content_id, dvd_id FROM derived_video').fetchall() == before
        conn.execute('CREATE TABLE derived_video_category(content_id TEXT, category_id INTEGER)')
        conn.execute('CREATE TABLE derived_video_actress(content_id TEXT, actress_id INTEGER)')
        conn.execute('CREATE TABLE derived_series(id INTEGER)')
        conn.execute('CREATE TABLE machine_translation(source_ja TEXT, target_en TEXT)')
        importer['create_catalog_indexes'](conn)
        importer['create_catalog_indexes'](conn)
        summaries = conn.execute('SELECT * FROM kuraku_catalog_groups_v2 ORDER BY kind, id').fetchall()
        assert summaries
        conn.execute('ALTER TABLE kuraku_catalog_groups_v2 RENAME TO kuraku_catalog_groups_v1')
        conn.commit()
        conn.set_authorizer(lambda action, name, *args: sqlite3.SQLITE_DENY if action == sqlite3.SQLITE_INSERT and name == 'kuraku_catalog_groups_v2' else sqlite3.SQLITE_OK)
        try:
            importer['create_catalog_indexes'](conn)
        except sqlite3.DatabaseError:
            pass
        else:
            raise AssertionError('Catalog preparation must fail')
        conn.set_authorizer(None)
        assert not conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'kuraku_catalog_groups_v2'").fetchone()
        assert conn.execute('SELECT * FROM kuraku_catalog_groups_v1 ORDER BY kind, id').fetchall() == summaries
        importer['create_catalog_indexes'](conn)
        assert conn.execute('SELECT * FROM kuraku_catalog_groups_v2 ORDER BY kind, id').fetchall() == summaries
        assert not conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'kuraku_catalog_groups_v1'").fetchone()
        plan = conn.execute("EXPLAIN QUERY PLAN SELECT video_code, release_date FROM derived_video WHERE content_id = ? AND video_code IS NOT NULL", ['118abp00001']).fetchall()
        assert any('COVERING INDEX idx_dv_content_code_date' in row[3] for row in plan), plan
        assert conn.execute('SELECT content_id, dvd_id FROM derived_video').fetchall() == before
        assert conn.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    print('R18 normalization, idempotency and rollback passed')
