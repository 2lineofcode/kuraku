import json
import re
import sqlite3
import sys
import time
from pathlib import Path


# Strip literals, quoted identifiers and comments before checking conflict syntax.
TOKENS = re.compile(r"--[^\n]*|/\*[\s\S]*?(?:\*/|$)|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|`(?:``|[^`])*`|\[[^\]]*\]|([A-Za-z_][A-Za-z_0-9]*)")
FUNCTIONS = set('abs avg changes char coalesce concat concat_ws count date datetime format glob group_concat hex if ifnull iif instr json json_array json_array_length json_error_position json_extract json_group_array json_group_object json_insert json_object json_patch json_quote json_remove json_replace json_set json_type json_valid julianday lag last_insert_rowid lead length likelihood likely ln log log10 log2 lower ltrim max min nth_value ntile nullif octet_length percent_rank pow power printf quote random randomblob rank replace round row_number rtrim sign soundex sqlite_version strftime string_agg substr substring sum timediff time total total_changes trim trunc typeof unicode unhex unixepoch unlikely upper zeroblob dense_rank first_value last_value cume_dist like'.split())


def words(sql):
    return [match.group(1).upper() for match in TOKENS.finditer(sql) if match.group(1)]


def run(request):
    started = time.monotonic()
    sql = request.get('sql')
    if not isinstance(sql, str) or not sql.strip() or len(sql) > 32000:
        raise ValueError('Query must contain 1–32000 characters.')
    tokens = words(sql)
    if not tokens or tokens[0] not in ('SELECT', 'WITH', 'INSERT', 'UPDATE'):
        raise ValueError('Only SELECT, INSERT and UPDATE are allowed. DELETE and schema changes are blocked.')
    if any(tokens[i:i + 2] == ['OR', 'REPLACE'] for i in range(len(tokens) - 1)):
        raise ValueError('OR REPLACE is blocked because it can delete existing rows.')
    args = request.get('args', [])
    if not isinstance(args, (list, dict)):
        raise ValueError('Parameters must be a JSON array or object.')
    operation = request.get('operation', 'run')
    if operation not in ('run', 'validate'):
        raise ValueError('Unknown operation.')
    db = sqlite3.connect(Path(request['main']).resolve().as_uri() + '?mode=rw', uri=True, timeout=2, isolation_level=None)
    try:
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA temp_store=MEMORY')
        definitions = dict(db.execute("SELECT name, sql FROM sqlite_master WHERE type='table'"))
        unsafe = set()
        for table, definition in definitions.items():
            table_words = words(definition or '')
            if 'VIRTUAL' in table_words or any(table_words[i:i + 3] == ['ON', 'CONFLICT', 'REPLACE'] for i in range(len(table_words) - 2)):
                unsafe.add(table)
        writes = set()

        def authorize(action, table, column, source, trigger):
            if action in (sqlite3.SQLITE_SELECT, sqlite3.SQLITE_RECURSIVE):
                return sqlite3.SQLITE_OK
            if action == sqlite3.SQLITE_READ and source in ('main', None):
                return sqlite3.SQLITE_OK
            # Keep our COMMIT/ROLLBACK authorized on Python versions without detach support.
            if action == sqlite3.SQLITE_TRANSACTION:
                return sqlite3.SQLITE_OK
            if action == sqlite3.SQLITE_FUNCTION and (column or '').lower() in FUNCTIONS:
                return sqlite3.SQLITE_OK
            if action in (sqlite3.SQLITE_INSERT, sqlite3.SQLITE_UPDATE):
                if source == 'main' and table in definitions and not table.startswith('sqlite_') and table not in unsafe and not trigger:
                    writes.add(table)
                    return sqlite3.SQLITE_OK
            return sqlite3.SQLITE_DENY

        if hasattr(db, 'setlimit'):
            db.setlimit(sqlite3.SQLITE_LIMIT_LENGTH, 1000000)
            db.setlimit(sqlite3.SQLITE_LIMIT_SQL_LENGTH, 33000)
            db.setlimit(sqlite3.SQLITE_LIMIT_COLUMN, 128)
            db.setlimit(sqlite3.SQLITE_LIMIT_EXPR_DEPTH, 100)
        db.set_progress_handler(lambda: time.monotonic() - started > 10, 1000)
        # SQL input is restricted to a single SELECT/INSERT/UPDATE statement.
        db.execute('BEGIN')
        db.set_authorizer(authorize)
        db.execute('EXPLAIN ' + sql, args).close()
        if operation == 'validate' or writes and request.get('confirm_write') is not True:
            return {'requires_confirmation': bool(writes), 'tables': sorted(writes)}
        cursor = db.execute(sql, args)
        columns = [item[0] for item in cursor.description] if cursor.description else []
        rows, truncated, remaining = [], False, 250000
        if columns:
            for row in cursor:
                if len(rows) == 500 or remaining <= 0:
                    truncated = True
                    if not writes:
                        break
                    continue
                values = []
                for value in row:
                    if isinstance(value, bytes):
                        value = f'[BLOB: {len(value)} bytes]'
                    if isinstance(value, str):
                        limit = min(2000, max(0, remaining))
                        if len(value) > limit:
                            value = value[:limit] + '…'
                            truncated = True
                        remaining -= len(value)
                    values.append(value)
                rows.append(values)
        cursor.close()
        result = {'columns': columns, 'rows': rows, 'truncated': truncated, 'affected_rows': db.total_changes if writes else 0,
                  'write': bool(writes), 'elapsed_ms': round((time.monotonic() - started) * 1000, 1)}
        # Serialize before committing so encoding failures cannot hide a successful write.
        json.dumps(result, allow_nan=False)
        db.execute('COMMIT')
        return result
    except sqlite3.DatabaseError as error:
        if 'authorized' in str(error):
            raise ValueError('Query blocked: DELETE, schema changes, unsafe functions and writes through triggers are not allowed.') from error
        if 'interrupted' in str(error):
            raise ValueError('Query exceeded the 10-second time limit. No changes were committed.') from error
        raise
    finally:
        db.set_progress_handler(None, 0)
        try:
            if db.in_transaction:
                db.rollback()
        finally:
            db.close()


if __name__ == '__main__':
    try:
        result = run(json.load(sys.stdin))
    except (sqlite3.Error, ValueError, KeyError, TypeError) as error:
        result = {'error': str(error)[:300]}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
