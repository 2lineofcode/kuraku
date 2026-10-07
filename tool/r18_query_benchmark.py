import argparse
import re
import sqlite3
import statistics
import time
from pathlib import Path


def category_queries(source, category, mode, size):
    patterns = []
    for field, prefix in [('_blacklistedPrefixes', True), ('_blacklistedSuffixes', False)]:
        values = re.search(field + r' = \[(.*?)\];', source, re.S)[1]
        patterns.extend(value + '%' if prefix else '%' + value for value in re.findall("'([^']+)'", values))
    literal = "clauses.add(\"$column NOT LIKE '$prefix%'\");" in source
    blacklist = ' AND ' + ' AND '.join("v.video_code NOT LIKE '" + pattern + "'" if literal else 'v.video_code NOT LIKE ?' for pattern in patterns)
    cast = '' if mode == 'all' else 'AND EXISTS (SELECT 1 FROM derived_video_actress dva2 WHERE dva2.content_id = v.content_id GROUP BY dva2.content_id HAVING COUNT(DISTINCT dva2.actress_id) ' + ('=' if mode == 'single' else '>') + ' 1)'
    for method in ['getCountAllVideosByCategory', 'getAllVideosByCategory']:
        body = source[source.index(method):]
        match = re.search(r"_(raw|browse)Query\('''(.*?)'''", body, re.S)
        sql = match[2].replace("${blacklist['sql']}", blacklist).replace('${_actressModeClause(actressMode)}', cast)
        args = [category, *([] if literal else patterns)]
        if method == 'getAllVideosByCategory':
            args.extend([size, 0])
        if match[1] == 'browse':
            helper = source[source.index('static Future<List<Map<String, dynamic>>> _browseQuery'):]
            wrapper = re.search(r"_rawQuery\('''(.*?)'''", helper, re.S)[1]
            wrapper = re.sub(r'\$\{ignoreEmptyTitle \? .*? : \'([^\']+)\'\}', lambda match: match[1], wrapper)
            sql = wrapper.replace('$sql', sql).replace('$extraColumns', '')
        yield method, sql, args


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Read-only benchmark of the actual Dart category SQL')
    parser.add_argument('database', type=Path)
    parser.add_argument('--source', type=Path, default=Path('lib/app/data/database/db_r18.dart'))
    parser.add_argument('--category', default='Big Tits')
    parser.add_argument('--mode', choices=['all', 'single', 'multi'], default='single')
    parser.add_argument('--size', type=int, default=500)
    parser.add_argument('--runs', type=int, default=3)
    args = parser.parse_args()
    with sqlite3.connect(args.database.resolve().as_uri() + '?mode=ro', uri=True) as conn:
        for method, sql, bindings in category_queries(args.source.read_text(), args.category, args.mode, args.size):
            print(method)
            for row in conn.execute('EXPLAIN QUERY PLAN ' + sql, bindings):
                print(' ', row[3])
            times = []
            for _ in range(args.runs):
                start = time.perf_counter()
                rows = conn.execute(sql, bindings).fetchall()
                times.append(round((time.perf_counter() - start) * 1000))
            print(f'  median={statistics.median(times)} ms runs={times} rows={len(rows)}')
