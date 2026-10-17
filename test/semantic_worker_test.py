"""Run with the semantic runtime's Python: python -B test/semantic_worker_test.py."""
from contextlib import ExitStack, closing
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

spec = importlib.util.spec_from_file_location('semantic_worker', Path(__file__).parents[1] / 'assets/visual_search_worker.py')
worker_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker_module)


class SemanticWorkerTest(unittest.TestCase):
    def test_index_resume_binary_freshness_and_search(self):
        with tempfile.TemporaryDirectory() as tmp, ExitStack() as connections:
            root = Path(tmp)
            db_path = root / 'kuraku.db'
            db = connections.enter_context(closing(sqlite3.connect(db_path)))
            db.execute('CREATE TABLE videos (id TEXT PRIMARY KEY, video_path TEXT, title TEXT, video_code TEXT, actress TEXT, updated_at TEXT, is_deleted INTEGER NOT NULL DEFAULT 0, filesize INTEGER)')
            db.execute("CREATE TABLE video_embeddings (video_id TEXT PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE, source_text TEXT NOT NULL, embedding BLOB NOT NULL CHECK(typeof(embedding)='blob' AND length(embedding)>0 AND length(embedding)%4=0), model TEXT NOT NULL, created_at TEXT, updated_at TEXT)")
            db.execute('INSERT INTO videos VALUES (?, ?, ?, ?, ?, ?, 0, 3)', ('one', str(root / 'one.mp4'), 'A red car', 'TEST-001', '[{"name_romaji":"Jane Doe"}]', ''))
            db.execute('INSERT INTO videos VALUES (?, ?, ?, ?, ?, ?, 0, 3)', ('two', str(root / 'two.mp4'), 'A blue boat', 'TEST-002', '[]', ''))
            db.commit()
            (root / 'vid_thumbnail').mkdir()
            from PIL import Image
            for name in ('one', 'two'):
                (root / (name + '.mp4')).write_bytes(b'video fixture')
                Image.new('RGB', (256, 256), 'gray').save(root / 'vid_thumbnail' / (name + '.jpg'))
            worker = worker_module.Worker(db_path, root)
            connections.enter_context(closing(worker.db))
            self.assertEqual(worker.db.execute('PRAGMA foreign_keys').fetchone()[0], 1)
            calls = []
            vector = np.zeros(512, dtype='<f4')
            vector[0] = 1
            worker.encode = lambda kind, value: calls.append(kind) or vector
            self.assertEqual(len(worker.plan()['ids']), 2)
            self.assertTrue(worker.index('one')['indexed'])
            self.assertEqual(worker.plan()['ids'], ['two'])
            self.assertEqual(worker.summary()['indexed'], 1)
            self.assertEqual(worker.summary()['pending'], len(worker.plan()['ids']))
            blob, kind = db.execute('SELECT embedding, typeof(embedding) FROM video_embeddings').fetchone()
            self.assertEqual((len(blob), kind), (2048, 'blob'))
            # A metadata-only change does not require running the image encoder again.
            db.execute("UPDATE videos SET title='A green car' WHERE id='one'")
            db.commit()
            self.assertEqual(worker.plan()['ids'], ['two'])
            self.assertEqual(worker.search('green car')[0]['video']['id'], 'one')
            self.assertEqual(worker.search('Jane Doe')[0]['video']['id'], 'one')
            calls.clear()
            self.assertEqual([hit['video']['id'] for hit in worker.search('TEST001')], ['one'])
            self.assertEqual(calls, [])
            # Latest database metadata is visible even after the search cache was populated.
            db.execute("UPDATE videos SET title='A yellow car' WHERE id='one'")
            db.commit()
            self.assertEqual(worker.search('yellow car')[0]['video']['title'], 'A yellow car')
            # Partial words/queries do not count as exact metadata matches.
            prepared = worker_module.prepare_fields(['inside video', 'blue boat'])
            self.assertEqual(worker_module.lexical_score('id', {'id'}, prepared, ''), 0)
            self.assertEqual(worker_module.lexical_score('blue car', {'blue', 'car'}, prepared, ''), 0)
            self.assertIn('日本語', worker_module.tokens('日本語'))
            video = root / 'one.mp4'
            for content in (b'other fixture', b'a larger replacement video'):
                modified = video.stat().st_mtime_ns
                video.write_bytes(content)
                os.utime(video, ns=(modified + 1000000, modified + 1000000))
                self.assertEqual(set(worker.plan()['ids']), {'one', 'two'})
                self.assertEqual(worker.summary()['pending'], 2)
                with patch.object(worker, 'ensure_thumbnail', side_effect=lambda row, force=False: worker.thumbnail(row)):
                    self.assertTrue(worker.index('one')['indexed'])
                self.assertEqual(worker.plan()['ids'], ['two'])
                self.assertEqual(worker.summary()['indexed'], 1)
                self.assertEqual(db.execute("SELECT filesize FROM videos WHERE id='one'").fetchone()[0], len(content))
                self.assertEqual([hit['video']['id'] for hit in worker.search('forest')], ['one'])
                self.assertEqual(worker.indexed_count, 1)
            original_source = db.execute("SELECT source_text FROM video_embeddings WHERE video_id='one'").fetchone()[0]
            for change in ["video_path='/moved.mp4', filesize=999", 'is_deleted=1, filesize=999']:
                def move_during_inference(kind, value):
                    db.execute(f"UPDATE videos SET {change} WHERE id='one'")
                    db.commit()
                    return vector
                with patch.object(worker, 'encode', side_effect=move_during_inference), patch.object(worker, 'ensure_thumbnail', side_effect=lambda row, force=False: worker.thumbnail(row)):
                    self.assertFalse(worker.index('one')['indexed'])
                self.assertEqual(db.execute("SELECT filesize FROM videos WHERE id='one'").fetchone()[0], 999)
                self.assertEqual(db.execute("SELECT source_text FROM video_embeddings WHERE video_id='one'").fetchone()[0], original_source)
                db.execute("UPDATE videos SET video_path=?, is_deleted=0, filesize=? WHERE id='one'", (str(video), video.stat().st_size))
                db.commit()
            # Index only pending items; rebuilding explicitly includes completed frames.
            (root / 'vid_thumbnail/one.jpg').write_bytes(b'changed thumbnail')
            self.assertEqual(worker.plan()['ids'], ['two'])
            self.assertEqual(worker.summary()['pending'], len(worker.plan()['ids']))
            self.assertEqual(set(worker.plan(force=True)['ids']), {'one', 'two'})
            (root / 'one.mp4').unlink()
            self.assertEqual(worker.plan()['ids'], ['two'])
            db.execute('INSERT INTO videos VALUES (?, ?, ?, ?, ?, ?, 0, 0)', ('duplicate', '/other/one.mp4', '', '', '[]', ''))
            db.commit()
            self.assertEqual(worker.plan()['missing_thumbnails'], 1)
            worker.refresh()
            self.assertFalse(np.any(worker.matrix))
            db.execute("UPDATE videos SET is_deleted=1 WHERE id='one'")
            db.commit()
            self.assertEqual(worker.summary()['total'], 2)
            self.assertEqual(set(worker.plan(force=True)['ids']), {'two', 'duplicate'})
            self.assertFalse(worker.index('one')['indexed'])
            with self.assertRaisesRegex(ValueError, 'No visual index yet'):
                worker.search('TEST001')
            self.assertNotIn('one', [row['id'] for row in worker.rows])
            self.assertFalse(worker.index('deleted')['indexed'])
            with worker.db:
                worker.db.execute("DELETE FROM videos WHERE id='one'")
            self.assertEqual(worker.db.execute('SELECT COUNT(*) FROM video_embeddings').fetchone()[0], 0)

    def test_visual_cutoff_is_stable_and_long_queries_are_rejected(self):
        worker = worker_module.Worker(None, Path('/unused'))
        worker.refresh = lambda: None
        worker.rows = [{'id': 'a'}, {'id': 'b'}]
        worker.fields = [worker_module.prepare_fields([])] * 2
        worker.matrix = np.zeros((2, 512), dtype=np.float32)
        worker.matrix[:, 0] = [.25, .9]
        vector = np.zeros(512, dtype=np.float32)
        vector[0] = 1
        worker.encode = lambda kind, value: vector
        self.assertEqual([hit['video']['id'] for hit in worker.search('forest')], ['b', 'a'])
        self.assertEqual([hit['video']['id'] for hit in worker.search('forest', .28)], ['b'])
        worker.matrix[1, 0] = .1
        self.assertEqual([hit['video']['id'] for hit in worker.search('forest')], ['a'])
        with self.assertRaisesRegex(ValueError, '500 characters'):
            worker.search('x' * 501)
        for invalid in (np.full(512, np.nan, dtype='<f4'), np.zeros(512, dtype='<f4')):
            self.assertIsNone(worker_module.Worker.valid_vector(invalid.tobytes()))

    @unittest.skipUnless(shutil.which('ffmpeg'), 'FFmpeg is not installed')
    def test_missing_frame_is_created_once_and_short_video_falls_back(self):
        with tempfile.TemporaryDirectory() as tmp, ExitStack() as connections:
            root = Path(tmp)
            video = root / 'short.mp4'
            subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
                '-i', 'color=c=blue:s=320x240:d=1', '-threads', '1', str(video)], check=True)
            with closing(sqlite3.connect(root / 'kuraku.db')) as db:
                db.execute('CREATE TABLE videos(video_path TEXT, is_deleted INTEGER NOT NULL DEFAULT 0)')
            worker = worker_module.Worker(root / 'kuraku.db', root / 'runtime')
            connections.enter_context(closing(worker.db))
            row = {'video_path': str(video)}
            frame = worker.ensure_thumbnail(row)
            self.assertTrue(frame.exists())
            from PIL import Image
            with Image.open(frame) as image:
                self.assertEqual(image.size, (256, 256))
            modified = frame.stat().st_mtime_ns
            self.assertEqual(worker.ensure_thumbnail(row).stat().st_mtime_ns, modified)
            # Replacing the video under the same path must regenerate its cached frame.
            subprocess.run([shutil.which('ffmpeg'), '-y', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
                '-i', 'color=c=red:s=320x240:d=1', '-threads', '1', str(video)], check=True)
            replacement = worker.ensure_thumbnail(row)
            self.assertNotEqual(replacement.stat().st_mtime_ns, modified)
            with Image.open(replacement) as image:
                red, green, blue = image.getpixel((128, 128))
                self.assertGreater(red, blue + 100)
            with self.assertRaisesRegex(OSError, 'offline'):
                worker.ensure_thumbnail({'video_path': str(root / 'missing.mp4')})
            self.assertFalse(list(frame.parent.glob('*.part.jpg')))

    def test_legacy_or_corrupt_vectors_are_not_used(self):
        with tempfile.TemporaryDirectory() as tmp, ExitStack() as connections:
            path = Path(tmp) / 'kuraku.db'
            db = connections.enter_context(closing(sqlite3.connect(path)))
            db.execute('CREATE TABLE videos (id TEXT PRIMARY KEY, video_path TEXT, title TEXT, updated_at TEXT, is_deleted INTEGER NOT NULL DEFAULT 0)')
            db.execute('CREATE TABLE video_embeddings (video_id TEXT PRIMARY KEY, source_text TEXT, embedding TEXT, model TEXT)')
            db.execute("INSERT INTO videos VALUES ('a', '/a.mp4', 'A car', '', 0)")
            db.execute('INSERT INTO video_embeddings VALUES (?, ?, ?, ?)', ('a', json.dumps(['/a.mp4']), '[1, 2]', worker_module.MODEL))
            db.commit()
            worker = worker_module.Worker(path, Path(tmp))
            connections.enter_context(closing(worker.db))
            worker.refresh()
            self.assertFalse(np.any(worker.matrix))
            self.assertEqual(worker.summary()['pending'], 1)
            self.assertEqual(worker.plan()['ids'], ['a'])
            for blob, source, model in [(np.zeros(512, dtype='<f4').tobytes(), '{}', worker_module.MODEL),
                    (np.full(512, np.nan, dtype='<f4').tobytes(), json.dumps({'path': '/a.mp4'}), worker_module.MODEL),
                    (np.eye(1, 512, dtype='<f4').tobytes(), '{broken', worker_module.MODEL),
                    (np.eye(1, 512, dtype='<f4').tobytes(), json.dumps({'path': '/old.mp4'}), worker_module.MODEL),
                    (np.eye(1, 512, dtype='<f4').tobytes(), json.dumps({'path': '/a.mp4'}), 'old-model')]:
                db.execute('UPDATE video_embeddings SET embedding=?, source_text=?, model=?', (blob, source, model))
                db.commit()
                self.assertEqual(worker.summary()['pending'], 1)
                self.assertEqual(worker.plan()['ids'], ['a'])
            with self.assertRaisesRegex(ValueError, 'No visual index'):
                worker.search('forest')


if __name__ == '__main__':
    unittest.main()
