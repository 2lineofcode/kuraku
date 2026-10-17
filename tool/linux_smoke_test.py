import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import tempfile
import time


def main():
    root = Path(__file__).resolve().parents[1]
    binary = root / 'build/linux/x64/release/bundle/kuraku'
    with tempfile.TemporaryDirectory(prefix='kuraku-linux-smoke-') as directory:
        temporary = Path(directory)
        config = temporary / 'config'
        documents = temporary / 'Documents'
        config.mkdir()
        documents.mkdir()
        (config / 'user-dirs.dirs').write_text(f'XDG_DOCUMENTS_DIR="{documents}"\n')
        environment = {
            **os.environ, 'XDG_CONFIG_HOME': str(config),
            'XDG_DATA_HOME': str(temporary / 'data'), 'GDK_BACKEND': 'x11',
            'LIBGL_ALWAYS_SOFTWARE': 'true',
        }
        with (temporary / 'app.log').open('w+') as log:
            process = subprocess.Popen(
                ['xvfb-run', '-a', '-s', '-screen 0 1280x900x24', 'dbus-run-session', '--', str(binary)],
                env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
            )
            try:
                database = documents / '.KuraKu/kuraku.db'
                deadline = time.monotonic() + 45
                ready = False
                while time.monotonic() < deadline and process.poll() is None:
                    if database.exists():
                        with sqlite3.connect(f'{database.as_uri()}?mode=ro', uri=True) as connection:
                            ready = connection.execute("SELECT 1 FROM sqlite_master WHERE name = 'chat_translation'").fetchone() is not None
                        if ready:
                            time.sleep(3)
                            break
                    time.sleep(.25)
                log.seek(0)
                output = log.read()
                assert ready and process.poll() is None, output
                assert 'dlopen(libffmpegkit.so) failed' not in output, output
                assert 'Could not start KuraKu' not in output, output
                assert 'Unhandled Exception' not in output, output
                print('Linux native startup reached the current database schema and remained running.')
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=10)


if __name__ == '__main__':
    main()
