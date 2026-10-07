from contextlib import closing
import importlib.util
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location('sql_editor', Path(__file__).resolve().parents[1] / 'assets/sql_editor_worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class SqlEditorTest(unittest.TestCase):
    def test_execution_and_deletion_protection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'test.db')
            with closing(sqlite3.connect(path)) as db:
                db.executescript('''
                    CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE);
                    INSERT INTO items(name) VALUES ('one'), ('two');
                    CREATE TABLE replace_default(id INTEGER PRIMARY KEY, name TEXT UNIQUE ON CONFLICT REPLACE);
                    INSERT INTO replace_default VALUES (1, 'one'), (2, 'two');
                    CREATE TABLE events(id INTEGER PRIMARY KEY, name TEXT);
                    CREATE TRIGGER delete_trigger AFTER INSERT ON events BEGIN DELETE FROM items; END;
                    CREATE TABLE proxy(id INTEGER PRIMARY KEY, name TEXT);
                    CREATE TRIGGER replace_trigger AFTER INSERT ON proxy BEGIN INSERT OR REPLACE INTO items(id, name) VALUES (1, 'changed'); END;
                    CREATE TABLE parent(id INTEGER PRIMARY KEY);
                    CREATE TABLE child(parent_id INTEGER REFERENCES parent(id) ON DELETE CASCADE);
                    INSERT INTO parent VALUES (1);
                    INSERT INTO child VALUES (1);
                ''')

            def run(sql, **request):
                return worker.run({'main': path, 'sql': sql, **request})

            def snapshot():
                with closing(sqlite3.connect(path)) as db:
                    return list(db.iterdump())

            initial = snapshot()
            for sql in [
                'DELETE FROM items', '-- comment\nDeLeTe FROM items WHERE id=1',
                'WITH target AS (SELECT 1) DELETE FROM items', 'DROP TABLE items',
                'INSERT OR REPLACE INTO items VALUES (1, "other")',
                'UPDATE OR REPLACE items SET name="two" WHERE id=1',
                'REPLACE INTO items VALUES (1, "other")',
                'UPDATE replace_default SET name="two" WHERE id=1',
                'INSERT INTO replace_default VALUES (3, "two")',
                'INSERT INTO events VALUES (1, "x")', 'INSERT INTO proxy VALUES (1, "x")',
                'DELETE FROM parent', 'PRAGMA writable_schema=ON',
                "SELECT load_extension('bad')", "ATTACH DATABASE ':memory:' AS other",
                "SELECT 1; DELETE FROM items", "UPDATE items SET name='bad' WHERE id=1; SELECT 1",
            ]:
                with self.subTest(sql=sql), self.assertRaises((ValueError, sqlite3.Error)):
                    run(sql, confirm_write=True)
                self.assertEqual(snapshot(), initial)

            preview = run('UPDATE items SET name=:name WHERE id=1', args={'name': 'updated'})
            self.assertTrue(preview['requires_confirmation'])
            self.assertEqual(snapshot(), initial)
            self.assertTrue(run("INSERT INTO items(name) VALUES ('three')", operation='validate')['requires_confirmation'])
            self.assertEqual(snapshot(), initial)
            result = run('UPDATE items SET name=:name WHERE id=1', args={'name': 'updated'}, confirm_write=True)
            self.assertEqual(result['affected_rows'], 1)
            result = run("INSERT INTO items(name) VALUES ('three') RETURNING id, name", confirm_write=True)
            self.assertEqual(result['rows'], [[3, 'three']])
            result = run('SELECT id, name FROM items ORDER BY id')
            self.assertEqual(result['columns'], ['id', 'name'])
            self.assertEqual(result['rows'], [[1, 'updated'], [2, 'two'], [3, 'three']])
            self.assertEqual(run("SELECT 'DELETE FROM items' AS text")['rows'], [['DELETE FROM items']])
            self.assertEqual(run("SELECT replace(name, 'updated', 'ok') FROM items WHERE id=1")['rows'], [['ok']])
            self.assertEqual(run('SELECT id FROM items WHERE id < 0')['columns'], ['id'])
            self.assertEqual(run('SELECT 1 AS x, 2 AS x')['columns'], ['x', 'x'])
            self.assertTrue(run('WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<600) SELECT x FROM n')['truncated'])
            before = snapshot()
            with self.assertRaises(sqlite3.IntegrityError):
                run("UPDATE items SET name='duplicate'", confirm_write=True)
            self.assertEqual(snapshot(), before)
            with patch.object(worker.time, 'monotonic', side_effect=[0] + [11] * 20):
                with self.assertRaisesRegex(ValueError, 'time limit'):
                    run('WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n) INSERT INTO items(name) SELECT CAST(x AS TEXT) FROM n', confirm_write=True)
            self.assertEqual(snapshot(), before)
            with self.assertRaises(ValueError):
                run('SELECT 1', args='bad')
            with self.assertRaises(sqlite3.Error):
                run('SELECT :missing')


if __name__ == '__main__':
    unittest.main()
