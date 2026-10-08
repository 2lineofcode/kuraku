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
            'git': 'echo "${COMMIT_COUNT:-1}"',
            'date': 'echo 20261008',
            'flutter': '''
if [ "$1" = build ]; then
  echo "$*" >> "$CALL_LOG"
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

        for scenario in ['missing_bundle', 'build_failure', 'copy_failure', 'success', 'needs_sudo', 'repeat', 'new_day', 'invalid_version', 'future_date', 'invalid_count']:
            version = {
                'repeat': '1.2.3+20261008.59',
                'new_day': '1.2.3+20261007.59',
                'invalid_version': 'invalid',
                'future_date': '1.2.3+20261009.1',
            }.get(scenario, '1.0.0+1')
            original = f'name: javit\nversion: {version}\n# keep this comment\n'
            (root / 'pubspec.yaml').write_text(original)
            env_content = "APP_NAME='JavIt'\n"
            (root / '.env').write_text(env_content)
            log = root / 'calls'
            log.write_text('')
            apps.chmod(0o555 if scenario == 'needs_sudo' else 0o755)
            result = subprocess.run(
                ['bash', str(root / 'publish.sh'), 'macos'],
                env={**os.environ, 'PATH': f'{commands}:{os.environ["PATH"]}',
                     'SCENARIO': scenario, 'CALL_LOG': str(log),
                     'COMMIT_COUNT': 'invalid' if scenario == 'invalid_count' else '1'},
                capture_output=True, text=True,
            )
            assert (result.returncode == 0) == (scenario in ['success', 'needs_sudo', 'repeat', 'new_day']), result.stderr
            calls = log.read_text().splitlines()
            assert ('copy' in calls) == (scenario in ['copy_failure', 'success', 'needs_sudo', 'repeat', 'new_day'])
            assert ('sudo' in calls) == (scenario == 'needs_sudo' and not os.access(apps, os.W_OK))
            assert ('Installed:' in result.stdout) == (result.returncode == 0)
            assert (root / '.env').read_text() == env_content
            assert not list(root.glob('pubspec.yaml.*'))
            if scenario in ['missing_bundle', 'build_failure', 'copy_failure', 'invalid_version', 'future_date', 'invalid_count']:
                assert (root / 'pubspec.yaml').read_text() == original
            else:
                expected = '1.2.3+20261008.60' if scenario == 'repeat' else (
                    '1.2.3+20261008.1' if scenario == 'new_day' else '1.0.0+20261008.1')
                assert (root / 'pubspec.yaml').read_text() == original.replace(version, expected)
                name, number = expected.split('+')
                assert f'build macos --release --no-tree-shake-icons --build-name={name} --build-number={number}' in calls
            apps.chmod(0o755)


if __name__ == '__main__':
    test_publish()
    print('publish checks passed')
