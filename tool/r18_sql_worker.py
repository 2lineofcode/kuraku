import hashlib
import json
import runpy
import sqlite3
import sys
import time
from pathlib import Path


if sys.argv[1] == ':memory:':
    conn = sqlite3.connect(':memory:')
    conn.executescript(Path('test/fixtures/r18_catalog.sql').read_text())
    conn.execute("INSERT INTO derived_video(content_id,dvd_id,series_id,release_date,title_en,runtime_mins,jacket_thumb_url) VALUES ('current','DEF-789',1,date('now','localtime'),'Current release',130,'current.jpg')")
    conn.execute("INSERT INTO derived_video_category VALUES ('current',2)")
    conn.execute("INSERT INTO derived_video_actress VALUES ('current',3)")
    runpy.run_path('assets/python/r18_importer.py')['create_catalog_indexes'](conn)
else:
    conn = sqlite3.connect(Path(sys.argv[1]).resolve().as_uri() + '?mode=ro', uri=True)
conn.row_factory = sqlite3.Row
conn.setlimit(sqlite3.SQLITE_LIMIT_VARIABLE_NUMBER, 999)
for line in sys.stdin:
    request = json.loads(line)
    start = time.perf_counter()
    conn.set_progress_handler(lambda: time.perf_counter() - start > 30, 10000)
    try:
        sql, args = request['sql'], request['args']
        plan = [row[3] for row in conn.execute('EXPLAIN QUERY PLAN ' + sql, args)]
        times = []
        for _ in range(request.get('runs', 1)):
            start = time.perf_counter()
            rows = [dict(row) for row in conn.execute(sql, args)]
            times.append(round((time.perf_counter() - start) * 1000, 2))
        canonical = sorted(json.dumps(row, sort_keys=True, ensure_ascii=False) for row in rows)
        digest = hashlib.sha256('\n'.join(canonical).encode()).hexdigest()
        print(json.dumps({'rows': rows, 'plan': plan, 'times_ms': times, 'hash': digest}), flush=True)
    except Exception as error:
        print(json.dumps({'error': str(error), 'elapsed_ms': round((time.perf_counter() - start) * 1000)}), flush=True)
conn.close()
