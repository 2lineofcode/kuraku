import os
from pathlib import Path
import subprocess
import tempfile


def test_publish():
    script = (Path(__file__).resolve().parents[1] / 'publish.sh').read_text()
    with tempfile.TemporaryDirectory(prefix='publish test ') as directory:
        root = Path(directory)
        apps = root / 'Applications'
        apps.mkdir()
        script = script.replace('/Applications', str(apps))
        # Quote the directory check too, since the test path contains spaces.
        script = script.replace(f'[ -w {apps} ]', f'[ -w "{apps}" ]')
        (root / 'publish.sh').write_text(script)
        commands = root / 'bin'
        commands.mkdir()
        mocks = {
            'dart': 'exit 0',
            'git': 'echo 1',
            'flutter': '''
if [ "$1" = build ]; then
  [ "$SCENARIO" != build_failure ] || exit 1
  if [ "$SCENARIO" != missing_bundle ]; then
    mkdir -p build/macos/Build/Products/Release/javit.app
  fi
fi
''',
            'ditto': '''
echo copy >> "$CALL_LOG"
[ "$SCENARIO" != copy_failure ] || exit 1
mkdir -p "$2"
''',
            'sudo': 'echo sudo >> "$CALL_LOG"\nexec "$@"',
        }
        for name, body in mocks.items():
            command = commands / name
            command.write_text('#!/usr/bin/env bash\nset -e\n' + body + '\n')
            command.chmod(0o755)

        for scenario in ['missing_bundle', 'build_failure', 'copy_failure', 'success', 'needs_sudo']:
            (root / 'pubspec.yaml').write_text('version: 1.0.0+1\n')
            (root / '.env').write_text("APP_VER='old'\n")
            log = root / 'calls'
            log.write_text('')
            apps.chmod(0o555 if scenario == 'needs_sudo' else 0o755)
            result = subprocess.run(
                ['bash', str(root / 'publish.sh'), 'macos'],
                env={**os.environ, 'PATH': f'{commands}:{os.environ["PATH"]}',
                     'SCENARIO': scenario, 'CALL_LOG': str(log)},
                capture_output=True, text=True,
            )
            assert (result.returncode == 0) == (scenario in ['success', 'needs_sudo']), result.stderr
            calls = log.read_text().splitlines()
            assert ('copy' in calls) == (scenario not in ['missing_bundle', 'build_failure'])
            assert ('sudo' in calls) == (scenario == 'needs_sudo' and not os.access(apps, os.W_OK))
            assert ('Installed:' in result.stdout) == (result.returncode == 0)
            apps.chmod(0o755)


if __name__ == '__main__':
    test_publish()
    print('publish checks passed')
