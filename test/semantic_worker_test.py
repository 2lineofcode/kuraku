"""Run with the semantic runtime's Python: python -B test/semantic_worker_test.py."""
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path
import sqlite3
import tempfile
import unittest

import numpy as np

spec = importlib.util.spec_from_file_location('semantic_worker', Path(__file__).parents[1] / 'assets/semantic_worker.py')
worker_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker_module)


class SemanticWorkerTest(unittest.TestCase):
    def test_index_resume_binary_freshness_and_search(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / 'javit.db'
            db = sqlite3.connect(db_path)
            db.execute('CREATE TABLE videos (id TEXT PRIMARY KEY, video_path TEXT, title TEXT, video_code TEXT, actress TEXT, updated_at TEXT)')
            db.execute('CREATE TABLE video_embeddings (video_id TEXT PRIMARY KEY, source_text TEXT, embedding TEXT, model TEXT, created_at TEXT, updated_at TEXT)')
            db.execute('INSERT INTO videos VALUES (?, ?, ?, ?, ?, ?)', ('one', str(root / 'one.mp4'), 'A red car', 'TEST-001', '[{"name_romaji":"Jane Doe"}]', ''))
            db.execute('INSERT INTO videos VALUES (?, ?, ?, ?, ?, ?)', ('two', str(root / 'two.mp4'), 'A blue boat', 'TEST-002', '[]', ''))
            db.commit()
            (root / 'vid_thumbnail').mkdir()
            from PIL import Image
            for name in ('one', 'two'):
                (root / (name + '.mp4')).write_bytes(b'video fixture')
                Image.new('RGB', (256, 256), 'gray').save(root / 'vid_thumbnail' / (name + '.jpg'))
            worker = worker_module.Worker(db_path, root)
            calls = []
            vector = np.zeros(512, dtype='<f4')
            vector[0] = 1
            worker.encode = lambda kind, value: calls.append(kind) or vector
            self.assertEqual(len(worker.plan()['ids']), 2)
            self.assertTrue(worker.index('one')['indexed'])
            self.assertEqual(worker.plan()['ids'], ['two'])
            self.assertEqual(worker.summary()['indexed'], 1)
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
            # Thumbnail changes and ambiguous basenames must be rechecked, not silently reused.
            (root / 'vid_thumbnail/one.jpg').write_bytes(b'changed thumbnail')
            self.assertEqual(len(worker.plan()['ids']), 2)
            db.execute('INSERT INTO videos VALUES (?, ?, ?, ?, ?, ?)', ('duplicate', '/other/one.mp4', '', '', '[]', ''))
            db.commit()
            self.assertEqual(worker.plan()['missing_thumbnails'], 2)
            worker.refresh()
            self.assertFalse(np.any(worker.matrix))
            self.assertFalse(worker.index('deleted')['indexed'])
            worker.db.close()
            db.close()

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
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            video = root / 'short.mp4'
            subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
                '-i', 'color=c=blue:s=320x240:d=1', '-threads', '1', str(video)], check=True)
            db = sqlite3.connect(root / 'javit.db')
            db.execute('CREATE TABLE videos(video_path TEXT)')
            db.close()
            worker = worker_module.Worker(root / 'javit.db', root / 'runtime')
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
            worker.db.close()

    def test_legacy_or_corrupt_vectors_are_not_used(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'javit.db'
            db = sqlite3.connect(path)
            db.execute('CREATE TABLE videos (id TEXT PRIMARY KEY, video_path TEXT, title TEXT, updated_at TEXT)')
            db.execute('CREATE TABLE video_embeddings (video_id TEXT PRIMARY KEY, source_text TEXT, embedding TEXT, model TEXT)')
            db.execute("INSERT INTO videos VALUES ('a', '/a.mp4', 'A car', '')")
            db.execute('INSERT INTO video_embeddings VALUES (?, ?, ?, ?)', ('a', json.dumps(['/a.mp4']), '[1, 2]', worker_module.MODEL))
            db.commit()
            worker = worker_module.Worker(path, Path(tmp))
            worker.refresh()
            self.assertFalse(np.any(worker.matrix))
            with self.assertRaisesRegex(ValueError, 'No visual index'):
                worker.search('forest')
            worker.db.close()
            db.close()


if __name__ == '__main__':
    unittest.main()
