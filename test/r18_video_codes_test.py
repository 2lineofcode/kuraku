import runpy
import sqlite3
from pathlib import Path


create_video_codes = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'assets/r18_database_importer.py'))['create_video_codes']


def database():
    conn = sqlite3.connect(':memory:')
    conn.execute('CREATE TABLE derived_video(content_id TEXT, dvd_id TEXT, service_code TEXT, series_id INTEGER, release_date TEXT, title_en TEXT)')
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
    with database() as conn:
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
        assert conn.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    print('R18 normalization, idempotency and rollback passed')
