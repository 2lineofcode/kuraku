import ctypes
from contextlib import closing
import shutil
import sqlite3
import subprocess
import time
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    binary = root / 'build/windows/x64/runner/Release/kuraku.exe'
    documents = ctypes.create_unicode_buffer(32768)
    assert ctypes.windll.shell32.SHGetFolderPathW(None, 5, None, 0, documents) == 0
    data = Path(documents.value) / 'KuraKu'
    if data.exists():
        raise RuntimeError('Run on a clean CI account; refusing to touch existing KuraKu data')
    process = subprocess.Popen([str(binary)], cwd=binary.parent)
    try:
        deadline = time.monotonic() + 60
        ready = False
        database = data / 'kuraku.db'
        while time.monotonic() < deadline and process.poll() is None:
            if database.exists():
                try:
                    with closing(sqlite3.connect(f'{database.as_uri()}?mode=ro', uri=True)) as connection:
                        ready = connection.execute("SELECT 1 FROM sqlite_master WHERE name = 'chat_translation'").fetchone() is not None
                except sqlite3.OperationalError:
                    pass
            if ready:
                time.sleep(3)
                break
            time.sleep(.25)
        assert ready and process.poll() is None, f'Windows startup failed: ready={ready}, exit={process.poll()}'
        print('Windows startup created the current SQLite schema and remained running with bundled playback libraries.')
    finally:
        if process.poll() is None:
            subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'], check=False, capture_output=True)
        process.wait(timeout=10)
        if data.exists():
            shutil.rmtree(data)


if __name__ == '__main__':
    main()
