"""Usage: RUNTIME/venv/bin/python -B test/semantic_search_benchmark.py RUNTIME.

Public Transformers.js fixtures go in RUNTIME/images; see README.
Worker timings exclude IPC and Flutter rendering. The corpus is synthetic.
"""
import importlib.util
import json
from pathlib import Path
import resource
import sqlite3
import statistics
import sys
import tempfile
import time

spec = importlib.util.spec_from_file_location('worker', Path(__file__).parents[1] / 'assets/visual_search_worker.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(sys.argv[1])
fixtures = {
    'cats.jpg': 'a photo of cats', 'corgi.jpg': 'a photo of a dog',
    'airport.jpg': 'an airport with airplanes', 'astronaut.png': 'an astronaut in a spacesuit',
    'beach.png': 'a tropical beach', 'bread.png': 'a loaf of bread',
    'butterfly.jpg': 'a butterfly', 'house.jpg': 'a house',
    'moraine-lake.png': 'a mountain lake', 'sam-car.png': 'a car',
}
with tempfile.TemporaryDirectory() as tmp:
    dbpath = Path(tmp) / 'kuraku.db'
    db = sqlite3.connect(dbpath)
    db.execute('CREATE TABLE videos(id TEXT PRIMARY KEY, video_path TEXT, title TEXT, video_code TEXT, updated_at TEXT, is_deleted INTEGER NOT NULL DEFAULT 0)')
    db.execute('CREATE TABLE video_embeddings(video_id TEXT PRIMARY KEY, source_text TEXT, embedding BLOB, model TEXT)')
    worker = module.Worker(dbpath, root)
    vectors = []
    for filename in fixtures:
        start = time.perf_counter()
        vectors.append(worker.encode('image', root / 'images' / filename))
        print(filename, 'image_ms', round((time.perf_counter() - start) * 1000, 1), flush=True)
    for i in range(10000):
        path = f'/video/{i}.mp4'
        db.execute('INSERT INTO videos VALUES(?,?,?,?,?,0)', (str(i), path, f'Item {i}', f'TEST-{i:05}', ''))
        db.execute('INSERT INTO video_embeddings VALUES(?,?,?,?)',
            (str(i), json.dumps({'path': path}), vectors[i % len(vectors)].tobytes(), module.MODEL))
    db.commit()
    correct = 0
    for expected, query in enumerate(fixtures.values()):
        start = time.perf_counter()
        hits = worker.search(query, minimum=0.0)
        actual = int(hits[0]['video']['id']) % len(vectors) if hits else None
        correct += actual == expected
        print(query, 'ms', round((time.perf_counter() - start) * 1000, 1),
            'top', list(fixtures)[actual] if actual is not None else None,
            'score', round(hits[0]['visual'], 3) if hits else None,
            'balanced_candidates', sum(hit['visual'] >= .24 for hit in hits), flush=True)
    assert correct == len(fixtures), f'Top-1 accuracy: {correct}/{len(fixtures)}'
    latency = []
    for _ in range(20):
        start = time.perf_counter()
        worker.search('a photo of cats')
        latency.append((time.perf_counter() - start) * 1000)
    print('cached_10000_median_ms', round(statistics.median(latency), 1))
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    print('peak_rss_mib', round(rss / (1024 * 1024 if sys.platform == 'darwin' else 1024), 1))
    worker.db.close()
    db.close()
