from contextlib import closing
import gzip
import runpy
import sqlite3
import tempfile
from pathlib import Path


converter = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'assets/python/r18_importer.py'))


def dump():
    return '''CREATE TABLE public.derived_video (
content_id TEXT, dvd_id TEXT, service_code TEXT, series_id INTEGER, release_date TEXT,
title_en TEXT, title_ja TEXT, maker_id INTEGER, label_id INTEGER, site_id INTEGER
);
CREATE TABLE public.derived_series (id INTEGER, name_en TEXT);
CREATE TABLE public.derived_label (id INTEGER, name_en TEXT);
CREATE TABLE public.derived_maker (id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE public.derived_site (id INTEGER, name TEXT);
CREATE TABLE public.derived_director (id INTEGER, name_romaji TEXT, name_kana TEXT);
CREATE TABLE public.derived_video_director (content_id TEXT, director_id INTEGER);
CREATE TABLE public.derived_actress (id INTEGER, name_romaji TEXT);
CREATE TABLE public.derived_video_actress (content_id TEXT, actress_id INTEGER);
CREATE TABLE public.derived_actor (id INTEGER);
CREATE TABLE public.derived_video_actor (content_id TEXT, actor_id INTEGER);
CREATE TABLE public.derived_category (id INTEGER, name_en TEXT);
CREATE TABLE public.derived_video_category (content_id TEXT, category_id INTEGER);
CREATE TABLE public.machine_translation (source_ja TEXT, target_en TEXT, timestamp TEXT);
CREATE TABLE public.source_dmm_trailer (timestamp TEXT);
CREATE TABLE public.source_dmm_video_histrion (timestamp TEXT);
COPY public.derived_video (content_id, dvd_id, service_code, title_en) FROM stdin;
118abp00001\t\\N\tdigital\tExample
\\.
'''


def test_copy_escapes():
    cases = [
        (r'\N', None), (r'\\N', r'\N'), ('', ''),
        (r'Line\nTwo\tPart\\End', 'Line\nTwo\tPart\\End'),
        (r'\b\f\r\v', '\b\f\r\v'),
        (r'\101\x42\7\12\x3', 'AB\x07\n\x03'),
        ('日本語' + r'\343\201\202\xe3\x81\x84', '日本語あい'),
        (r'\q', 'q'),
    ]
    rows = ''.join(f'118abp{i:05}\t\\N\tdigital\t{encoded}\n' for i, (encoded, _) in enumerate(cases, 1))
    with tempfile.TemporaryDirectory(prefix='r18 copy escapes ') as directory:
        source, output = Path(directory) / 'dump.sql.gz', Path(directory) / 'r18.db'
        with gzip.open(source, 'wt', encoding='utf-8') as stream:
            stream.write(dump().replace('118abp00001\t\\N\tdigital\tExample\n', rows))
        converter['convert_dump'](source, output)
        with closing(sqlite3.connect(output)) as conn:
            assert conn.execute('SELECT title_en FROM derived_video ORDER BY content_id').fetchall() == [(expected,) for _, expected in cases]


if __name__ == '__main__':
    test_copy_escapes()
    with tempfile.TemporaryDirectory(prefix='r18 update ') as directory:
        root = Path(directory)
        source = root / 'r18dotdev_dump_2026-10-06.sql.gz'
        output = root / 'r18_2026_10_06.db'
        previous = root / 'r18_2026_09_29.db'
        previous.write_bytes(b'previous catalog')
        with gzip.open(source, 'wt') as stream:
            stream.write(dump())
        converter['convert_dump'](source, output)
        with closing(sqlite3.connect(output)) as conn:
            assert conn.execute('SELECT video_code FROM derived_video').fetchone() == ('ABP-001',)
            assert conn.execute('PRAGMA quick_check').fetchone() == ('ok',)
        valid = output.read_bytes()
        for broken in [dump().replace('\\.\n', ''), dump() + 'INVALID SQL;\n', dump().replace('Example', r'\xff'), dump().replace('118abp00001\t\\N\tdigital\tExample\n', ''), 'not a gzip file']:
            if broken == 'not a gzip file':
                source.write_text(broken)
            else:
                with gzip.open(source, 'wt') as stream:
                    stream.write(broken)
            try:
                converter['convert_dump'](source, output)
            except (ValueError, sqlite3.Error, gzip.BadGzipFile):
                pass
            else:
                raise AssertionError('Invalid dump must fail')
            assert previous.read_bytes() == b'previous catalog'
            assert output.read_bytes() == valid
            assert not Path(f'{output}.importing').exists()
            assert source.exists()
    print('R18 gzip import, validation, atomic replacement and failure cleanup passed')
