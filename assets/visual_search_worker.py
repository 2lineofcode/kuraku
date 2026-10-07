#!/usr/bin/env python3
"""Local CLIP search. Setup downloads models; serve never uses the network."""
import collections
import gc
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import urllib.request

os.environ['OMP_NUM_THREADS'] = '1'
os.environ['OPENBLAS_NUM_THREADS'] = '1'
os.environ['TOKENIZERS_PARALLELISM'] = 'false'
MODEL = 'clip-vit-b32-int8-v2'
READY = MODEL + ':2'
REVISION = 'd15189d7028b43f1d3e65039190477f6af591c2a'
FILES = {
    'onnx/vision_model_int8.onnx': '0ab0c1b3ace708e539633af1744d5a95247fe4e14d3e08ff197ef82a6cb9bd93',
    'onnx/text_model_int8.onnx': '18845f2ccc35223bb7fec403383a131154b11ac0918df25cf51986df5efd3a21',
    'tokenizer.json': 'f7f3b7af117d467b58374797691a6438d3e6b9e9cef800dfd5dced7f697a90cd',
    'LICENSE': '987e63b32f6c89ff5160e429458a872ff048e6860b590a3912e938f9da8f14db',
}
_decoder = None


def stop_worker(signum, frame):
    if _decoder is not None:
        _decoder.kill()
    raise SystemExit(0)


STOP_WORDS = set('a an the of in on at with and or photo image video showing is are to'.split())


def file_digest(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        while chunk := file.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def run_child(arguments):
    global _decoder
    try:
        _decoder = subprocess.Popen(arguments)
        if _decoder.wait() != 0:
            raise RuntimeError('Local runtime installation failed. Check the setup log and retry.')
    finally:
        if _decoder is not None and _decoder.poll() is None:
            _decoder.kill()
            _decoder.wait()
        _decoder = None


def progress(message):
    print('PROGRESS ' + message, flush=True)


def setup(root):
    if sys.version_info < (3, 12):
        raise RuntimeError('Python 3.12 or newer is required for Visual Search.')
    root.mkdir(parents=True, exist_ok=True)
    (root / 'ready').unlink(missing_ok=True)
    python = root / 'venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    progress('Preparing local runtime...')
    if not python.exists():
        run_child([sys.executable, '-m', 'venv', str(root / 'venv')])
    run_child([str(python), '-m', 'pip', 'install', '--disable-pip-version-check',
               '--only-binary=:all:', 'onnxruntime==1.30.0', 'numpy==2.5.3',
               'pillow==12.3.0', 'tokenizers==0.23.2'])
    for name, expected in FILES.items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() and file_digest(target) == expected:
            continue
        partial = target.with_suffix(target.suffix + '.part')
        try:
            url = f'https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/{REVISION}/{name}'
            if name == 'LICENSE':
                url = 'https://raw.githubusercontent.com/openai/CLIP/d05afc436d78f1c48dc0dbf8e5980a9d471f35f6/LICENSE'
            digest = hashlib.sha256()
            with urllib.request.urlopen(url, timeout=60) as response, partial.open('wb') as output:
                total = int(response.headers.get('Content-Length', 0))
                if total and shutil.disk_usage(root).free < total + 32 * 1024 * 1024:
                    raise OSError('Not enough free disk space for Visual Search models.')
                received = 0
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
                    digest.update(chunk)
                    received += len(chunk)
                    amount = f'{received * 100 // total}%' if total else f'{received // 1048576} MB'
                    label = 'image search model' if 'vision' in name else 'text search model' if 'text_model' in name else 'search resources'
                    progress(f'Downloading {label}: {amount}')
            if digest.hexdigest() != expected:
                raise ValueError('Model checksum mismatch. Please retry setup.')
            partial.replace(target)
        finally:
            partial.unlink(missing_ok=True)
    progress('Checking image and text inference...')
    run_child([str(python), '-B', str(Path(__file__).resolve()), 'verify', str(root)])
    (root / 'ready.tmp').write_text(READY)
    (root / 'ready.tmp').replace(root / 'ready')


def verify_runtime(root):
    from PIL import Image
    worker = Worker(None, root)
    worker.encode('text', 'a photo of a room')
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'check.png'
        Image.new('RGB', (224, 224), 'gray').save(path)
        worker.encode('image', str(path))
    worker.unload()


def tokens(value):
    return set(re.findall(r'[^\W_]+', (value or '').casefold(), re.UNICODE)) - STOP_WORDS


def names(row, field, key):
    try:
        return [str(item.get(key) or '') for item in json.loads(row.get(field) or '[]')]
    except (ValueError, TypeError, AttributeError):
        return []


def lexical_fields(row):
    fields = [row.get(k) or '' for k in ('title', 'title_ja', 'video_code', 'series', 'studio')]
    fields += names(row, 'actress', 'name_romaji') + names(row, 'category', 'category')
    fields.append(Path(row.get('video_path') or '').stem)
    return fields


def prepare_fields(fields):
    field_tokens = [tokens(field) for field in fields]
    return field_tokens, set().union(*field_tokens)


def lexical_score(query, query_tokens, prepared, code):
    if not query_tokens:
        return 0.0
    compact = re.sub(r'[^\w]', '', query.casefold())
    if code and compact == re.sub(r'[^\w]', '', code.casefold()):
        return 3.0
    field_tokens, combined = prepared
    if any(query_tokens == field for field in field_tokens if field):
        return 2.0
    # Partial keyword hits alone do not qualify as a match for a compound query.
    return 1.0 if query_tokens <= combined else 0.0


class Worker:
    def __init__(self, db_path, root):
        self.root = root
        self.db = sqlite3.connect(Path(db_path).resolve().as_uri() + '?mode=rw', uri=True, timeout=5) if db_path else None
        if self.db is not None:
            self.db.row_factory = sqlite3.Row
        self.db_directory = Path(db_path).resolve().parent if db_path else root
        self.session = None
        self.session_kind = None
        self.tokenizer = None
        self.query_cache = collections.OrderedDict()
        self.cache_version = None
        self.rows = []
        self.matrix = None
        self.fields = []
        stems = collections.Counter(Path(row[0] or '').stem for row in (self.db.execute('SELECT video_path FROM videos') if self.db else []))
        self.ambiguous_stems = {stem for stem, count in stems.items() if count > 1}

    def unload(self):
        self.session = None
        self.session_kind = None
        gc.collect()
        return {}

    def session_for(self, kind):
        import onnxruntime as ort
        if self.session_kind != kind:
            self.unload()
            options = ort.SessionOptions()
            options.intra_op_num_threads = 1
            options.inter_op_num_threads = 1
            options.add_session_config_entry('session.intra_op.allow_spinning', '0')
            options.add_session_config_entry('session.inter_op.allow_spinning', '0')
            options.enable_cpu_mem_arena = False
            file = 'vision_model_int8.onnx' if kind == 'image' else 'text_model_int8.onnx'
            self.session = ort.InferenceSession(str(self.root / 'onnx' / file), options, providers=['CPUExecutionProvider'])
            self.session_kind = kind
        return self.session

    def encode(self, kind, value):
        import numpy as np
        session = self.session_for(kind)
        if kind == 'image':
            from PIL import Image, ImageOps
            with Image.open(value) as image:
                image = ImageOps.exif_transpose(image).convert('RGB')
                width, height = image.size
                scale = 224 / min(width, height)
                image = image.resize((int(width * scale), int(height * scale)), Image.Resampling.BICUBIC)
                left, top = (image.width - 224) // 2, (image.height - 224) // 2
                image = image.crop((left, top, left + 224, top + 224))
                values = np.asarray(image, dtype=np.float32).transpose(2, 0, 1)[None] / 255.0
            mean = np.array([.48145466, .4578275, .40821073], dtype=np.float32)[None, :, None, None]
            std = np.array([.26862954, .26130258, .27577711], dtype=np.float32)[None, :, None, None]
            inputs = {'pixel_values': (values - mean) / std}
        else:
            if self.tokenizer is None:
                from tokenizers import Tokenizer
                self.tokenizer = Tokenizer.from_file(str(self.root / 'tokenizer.json'))
                self.tokenizer.enable_truncation(max_length=77)
                self.tokenizer.enable_padding(length=77, pad_id=49407, pad_token='<|endoftext|>')
            encoded = self.tokenizer.encode(value)
            inputs = {'input_ids': np.array([encoded.ids], dtype=np.int64),
                      'attention_mask': np.array([encoded.attention_mask], dtype=np.int64)}
        inputs = {item.name: inputs[item.name] for item in session.get_inputs()}
        output_name = 'image_embeds' if kind == 'image' else 'text_embeds'
        vector = session.run([output_name], inputs)[0].reshape(-1).astype('<f4')
        norm = float(np.linalg.norm(vector))
        if vector.size != 512 or not np.isfinite(vector).all() or norm <= 0:
            raise ValueError('Invalid model embedding')
        return vector / norm

    def thumbnail(self, row):
        # ponytail: one frame per video; add sampling only if retrieval evaluation requires it.
        video_path = row.get('video_path') or ''
        key = hashlib.sha256(video_path.encode()).hexdigest()
        own = self.root / 'thumbnails' / (key + '.jpg')
        if own.exists():
            return own
        path = self.db_directory / 'vid_thumbnail'
        legacy = path / (Path(video_path).stem + '.jpg')
        return legacy if Path(video_path).stem not in self.ambiguous_stems and legacy.exists() else own

    def ensure_thumbnail(self, row, force=False):
        global _decoder
        video_path = row.get('video_path') or ''
        try:
            stat = Path(video_path).stat()
        except OSError:
            raise OSError('Video is offline or missing')
        fingerprint = [stat.st_size, stat.st_mtime_ns]
        target = self.thumbnail(row)
        if target.exists() and not force:
            if target.parent != self.root / 'thumbnails':
                if target.stat().st_mtime_ns >= stat.st_mtime_ns:
                    return target
            else:
                try:
                    if json.loads(target.with_suffix('.json').read_text()) == fingerprint:
                        return target
                except (OSError, ValueError):
                    pass
        key = hashlib.sha256(video_path.encode()).hexdigest()
        target = self.root / 'thumbnails' / (key + '.jpg')
        ffmpeg = shutil.which('ffmpeg')
        if not ffmpeg:
            ffmpeg = next((p for p in ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg'] if Path(p).is_file()), None)
        if not ffmpeg:
            raise OSError('FFmpeg is required to create missing thumbnails')
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_suffix('.part.jpg')
        try:
            for position in ('90', '0'):
                try:
                    _decoder = subprocess.Popen([ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
                        '-threads', '1', '-ss', position, '-i', video_path, '-an', '-sn',
                        '-vf', 'scale=256:256:force_original_aspect_ratio=increase,crop=256:256',
                        '-frames:v', '1', '-threads', '1', str(partial)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    _decoder_code = _decoder.wait(timeout=15)
                finally:
                    if _decoder is not None:
                        if _decoder.poll() is None:
                            _decoder.kill()
                        _decoder.wait()
                        _decoder = None
                if _decoder_code == 0 and partial.exists() and partial.stat().st_size > 0:
                    current = Path(video_path).stat()
                    if [current.st_size, current.st_mtime_ns] != fingerprint:
                        raise OSError('Video changed while generating its frame. Retry indexing.')
                    partial.replace(target)
                    stamp = target.with_suffix('.json.tmp')
                    stamp.write_text(json.dumps(fingerprint))
                    stamp.replace(target.with_suffix('.json'))
                    return target
            raise OSError('Could not extract a video thumbnail')
        finally:
            partial.unlink(missing_ok=True)

    def source(self, row):
        thumb = self.thumbnail(row)
        try:
            stat = thumb.stat()
            video = Path(row.get('video_path') or '').stat()
        except OSError:
            return None
        return json.dumps({'path': row.get('video_path'), 'thumbnail': str(thumb),
            'image': [stat.st_size, stat.st_mtime_ns], 'video': [video.st_size, video.st_mtime_ns]}, sort_keys=True)

    def indexed_ids(self):
        records = self.db.execute("""SELECT e.video_id, e.embedding FROM video_embeddings e JOIN videos v ON v.id=e.video_id
            WHERE e.model=? AND typeof(e.embedding)='blob' AND length(e.embedding)=2048
            AND json_extract(CASE WHEN json_valid(e.source_text) THEN e.source_text ELSE '{}' END, '$.path')=v.video_path""", (MODEL,))
        return {row['video_id'] for row in records if self.valid_vector(row['embedding']) is not None}

    def summary(self):
        total = self.db.execute('SELECT count(*) FROM videos').fetchone()[0]
        indexed = len(self.indexed_ids())
        return {'total': total, 'indexed': indexed, 'pending': max(0, total - indexed)}

    @staticmethod
    def valid_vector(blob):
        if not isinstance(blob, bytes) or len(blob) != 2048:
            return None
        import numpy as np
        vector = np.frombuffer(blob, dtype='<f4')
        return vector if np.isfinite(vector).all() and abs(float(np.linalg.norm(vector)) - 1) < .01 else None

    def plan(self, force=False):
        indexed = self.indexed_ids()
        rows = [dict(row) for row in self.db.execute('SELECT id, video_path FROM videos ORDER BY updated_at DESC')]
        stems = collections.Counter(Path(row.get('video_path') or '').stem for row in rows)
        self.ambiguous_stems = {stem for stem, count in stems.items() if count > 1}
        pending = [row for row in rows if force or row['id'] not in indexed]
        missing = sum(self.source(row) is None for row in pending)
        return {'ids': [row['id'] for row in pending], 'indexed': len(indexed), 'missing_thumbnails': missing, 'total': len(rows)}

    def index(self, video_id, force=False):
        row = self.db.execute('SELECT id, video_path FROM videos WHERE id = ?', (video_id,)).fetchone()
        if row is None:
            return {'indexed': False}
        row = dict(row)
        try:
            thumb = self.ensure_thumbnail(row, force)
            source = self.source(row)
            if source is None:
                raise OSError('Video is unavailable. Reconnect its drive and retry.')
            from PIL import Image
            with Image.open(thumb) as image:
                image.verify()
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            return {'indexed': False, 'error': str(error)}
        # Model/runtime failures stop the job; retrying every video cannot fix them.
        vector = self.encode('image', str(thumb))
        if source != self.source(row):
            return {'indexed': False}
        with self.db:
            # INSERT SELECT avoids orphan records if the video was removed during inference.
            cursor = self.db.execute('''INSERT INTO video_embeddings(video_id, source_text, embedding, model, created_at, updated_at)
                SELECT id, ?, ?, ?, datetime('now'), datetime('now') FROM videos WHERE id = ? AND video_path = ?
                ON CONFLICT(video_id) DO UPDATE SET source_text=excluded.source_text, embedding=excluded.embedding,
                model=excluded.model, updated_at=excluded.updated_at''',
                (source, vector.tobytes(), MODEL, video_id, row['video_path']))
        self.cache_version = None
        return {'indexed': cursor.rowcount > 0}

    def refresh(self):
        import numpy as np
        version = self.db.execute('PRAGMA data_version').fetchone()[0]
        if version == self.cache_version:
            return
        self.rows = [dict(row) for row in self.db.execute('SELECT * FROM videos')]
        stems = collections.Counter(Path(row.get('video_path') or '').stem for row in self.rows)
        self.ambiguous_stems = {stem for stem, count in stems.items() if count > 1}
        records = {r['video_id']: r for r in self.db.execute(
            'SELECT video_id, source_text, embedding FROM video_embeddings WHERE model = ?', (MODEL,))}
        self.matrix = np.zeros((len(self.rows), 512), dtype=np.float32)
        self.fields = [prepare_fields(lexical_fields(row)) for row in self.rows]
        for i, row in enumerate(self.rows):
            record = records.get(row['id'])
            if record is None:
                continue
            vector = self.valid_vector(record['embedding'])
            if vector is None:
                continue
            try:
                source = json.loads(record['source_text'])
                if not isinstance(source, dict) or source.get('path') != row.get('video_path'):
                    continue
                size = row.get('filesize') or 0
                if size and size != source['video'][0]:
                    continue
                if Path(row.get('video_path') or '').stem in self.ambiguous_stems:
                    key = hashlib.sha256(source['path'].encode()).hexdigest()
                    if source.get('thumbnail') != str(self.root / 'thumbnails' / (key + '.jpg')):
                        continue
            except (ValueError, TypeError, IndexError, KeyError):
                continue
            self.matrix[i] = vector
        self.indexed_count = int(np.count_nonzero(np.linalg.norm(self.matrix, axis=1)))
        self.cache_version = version

    def search(self, query, minimum=0.24):
        import numpy as np
        query = query.strip()
        if len(query) > 500:
            raise ValueError('Use a shorter description (up to 500 characters).')
        if not query:
            return []
        self.refresh()
        query_tokens = tokens(query)
        if not query_tokens or not self.rows:
            return []
        # Exact identifiers should not invoke image inference or admit visually similar items.
        lexical_scores = [lexical_score(query, query_tokens, self.fields[i], row.get('video_code') or '') for i, row in enumerate(self.rows)]
        code_query = any(score == 3 for score in lexical_scores)
        similarities = np.zeros(len(self.rows), dtype=np.float32)
        if not code_query and np.any(self.matrix):
            if query not in self.query_cache:
                self.query_cache[query] = self.encode('text', query)
                if len(self.query_cache) > 32:
                    self.query_cache.popitem(last=False)
            self.query_cache.move_to_end(query)
            similarities = self.matrix @ self.query_cache[query]
        # ponytail: linear vector scan; add ANN only when measured search latency requires it.
        cutoff = minimum
        hits = []
        for i, row in enumerate(self.rows):
            lexical = lexical_scores[i]
            visual = float(similarities[i])
            if code_query and lexical < 3:
                continue
            if lexical == 0 and visual < cutoff:
                continue
            hits.append({'video': row, 'score': lexical + max(0, visual), 'visual': visual, 'reason': 'Code' if lexical == 3 else 'Metadata' if lexical else 'Visual'})
        if not hits and not np.any(self.matrix) and not code_query:
            raise ValueError('No visual index yet. Run Index new / changed in Settings.')
        hits.sort(key=lambda hit: (-hit['score'], hit['video']['id']))
        return hits


def main():
    if len(sys.argv) < 3:
        raise SystemExit('Usage: visual_search_worker.py setup RUNTIME | serve RUNTIME DATABASE')
    command, root = sys.argv[1], Path(sys.argv[2])
    signal.signal(signal.SIGTERM, stop_worker)
    if command == 'verify':
        verify_runtime(root)
        return
    if command == 'setup':
        setup(root)
        return
    if command != 'serve' or len(sys.argv) != 4:
        raise SystemExit('Invalid command')
    try:
        os.nice(10)
    except (AttributeError, OSError):
        pass
    worker = Worker(sys.argv[3], root)
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            command = request['command']
            if command == 'summary':
                result = worker.summary()
            elif command == 'plan':
                result = worker.plan(request.get('force', False))
            elif command == 'index':
                result = worker.index(request['video_id'], request.get('force', False))
            elif command == 'search':
                minimum = float(request.get('minimum', .24))
                if not 0 <= minimum <= 1:
                    raise ValueError('Invalid relevance threshold')
                hits = worker.search(request['query'], minimum)
                result = {'hits': hits, 'indexed': getattr(worker, 'indexed_count', 0), 'total': len(worker.rows)}
            elif command == 'unload':
                result = worker.unload()
            else:
                raise ValueError('Unknown command')
            response = {'id': request['id'], 'result': result}
        except Exception as error:
            response = {'id': request.get('id'), 'error': str(error)}
        print(json.dumps(response, ensure_ascii=False), flush=True)
    worker.db.close()


if __name__ == '__main__':
    main()
