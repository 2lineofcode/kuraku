import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap


def test_build_events():
    root = Path(__file__).resolve().parents[1]
    for platform in ['macos', 'linux', 'windows']:
        workflow = (root / f'.github/workflows/{platform}.yml').read_text()
        steps = re.split(r'^      - ', workflow.split('\n  release:', 1)[0], flags=re.M)[1:]
        build_steps = 0
        for step in steps:
            condition = re.search(r'^        if: (.+)$', step, re.M)
            if step.startswith(('name: Analyze', 'name: Test')):
                assert condition is None, (platform, step)
            if not any(marker in step for marker in [
                'flutter build ', 'name: Package DMG', 'actions/upload-artifact@',
                'tool/linux_smoke_test.py', 'tool/windows_smoke_test.py',
            ]):
                continue
            build_steps += 1
            assert condition is not None, (platform, step)
            expression = condition.group(1).replace('github.ref_type', '"$REF_TYPE"').replace('github.event_name', '"$EVENT_NAME"')
            for event, ref_type, expected in [
                ('push', 'branch', False), ('pull_request', 'branch', False),
                ('push', 'tag', True), ('workflow_dispatch', 'branch', True),
                ('workflow_dispatch', 'tag', True),
            ]:
                result = subprocess.run(
                    ['bash', '-c', f'[[ {expression} ]]'],
                    env={**os.environ, 'REF_TYPE': ref_type, 'EVENT_NAME': event},
                    capture_output=True, text=True,
                )
                assert result.returncode in [0, 1], result.stderr
                assert (result.returncode == 0) == expected, (platform, event, ref_type, step)
        assert build_steps == 3, (platform, build_steps)


def test_release_version():
    workflow = (Path(__file__).resolve().parents[1] / '.github/workflows/macos.yml').read_text()
    script = workflow.split('      - name: Validate version\n        run: |\n', 1)[1].split('\n      - uses:', 1)[0]
    script = textwrap.dedent(script)
    cases = [
        ('1.0.0+20261015.77', 'tag', 'v1.0.0', True),
        ('1.0.0', 'tag', 'v1.0.0', True),
        ('1.0.0+1', 'branch', 'feature/test', True),
        ('1.0.0+1', 'tag', 'v2.0.0', False),
        ('1.0.0+1', 'tag', 'v1.0.0-beta.1', False),
        ('invalid', 'branch', 'main', False),
        ('', 'tag', 'v', False),
    ]
    with tempfile.TemporaryDirectory(prefix='kuraku release test ') as directory:
        root = Path(directory)
        output = root / 'env'
        for version, kind, ref, valid in cases:
            (root / 'pubspec.yaml').write_text(f'version: {version}\n')
            output.write_text('')
            result = subprocess.run(
                ['bash', '-euo', 'pipefail', '-c', script], cwd=root,
                env={**os.environ, 'GITHUB_REF_TYPE': kind, 'GITHUB_REF_NAME': ref, 'GITHUB_ENV': str(output)},
                capture_output=True, text=True,
            )
            assert (result.returncode == 0) == valid, (version, ref, result.stderr)
            assert output.read_text() == ('APP_VERSION=1.0.0\n' if valid else '')


def test_release_packages():
    root = Path(__file__).resolve().parents[1]
    workflow = (root / '.github/workflows/release.yml').read_text()
    assert 'needs: [macos, linux, windows]' in workflow
    for platform in ['macos', 'linux', 'windows']:
        assert f'uses: ./.github/workflows/{platform}.yml' in workflow
        platform_workflow = (root / f'.github/workflows/{platform}.yml').read_text()
        assert '  workflow_call:' in platform_workflow
        assert '    tags:' not in platform_workflow
    script = textwrap.dedent(workflow.split('        run: |\n', 1)[1])
    for scenario in ['success', 'corrupt', 'missing']:
        with tempfile.TemporaryDirectory(prefix='kuraku release packages ') as directory:
            fixture = Path(directory)
            dist = fixture / 'dist'
            dist.mkdir()
            packages = ['KuraKu-1.0.2-macos-arm64.dmg', 'KuraKu-1.0.2-linux-x64.deb', 'KuraKu-1.0.2-windows-x64.zip']
            for name in packages:
                content = name.encode()
                (dist / name).write_bytes(content)
                (dist / f'{name}.sha256').write_text(f'{hashlib.sha256(content).hexdigest()}  {name}\n')
            if scenario == 'corrupt':
                (dist / packages[1]).write_bytes(b'corrupt')
            elif scenario == 'missing':
                (dist / packages[1]).unlink()
                (dist / f'{packages[1]}.sha256').unlink()
            commands = fixture / 'bin'
            commands.mkdir()
            gh = commands / 'gh'
            gh.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "$CALL_LOG"\n')
            gh.chmod(0o755)
            log = fixture / 'calls'
            result = subprocess.run(
                ['bash', '-euo', 'pipefail', '-c', script], cwd=fixture,
                env={**os.environ, 'PATH': f'{commands}:{os.environ["PATH"]}', 'CALL_LOG': str(log), 'RELEASE_TAG': 'v1.0.2'},
                capture_output=True, text=True,
            )
            assert (result.returncode == 0) == (scenario == 'success'), result.stderr
            assert log.exists() == (scenario == 'success')
            if log.exists():
                arguments = log.read_text().splitlines()
                assert arguments[:3] == ['release', 'create', 'v1.0.2']
                for name in packages:
                    assert f'./{name}' in arguments
                    assert f'./{name}.sha256' in arguments


def test_packaging_architecture():
    workflow = (Path(__file__).resolve().parents[1] / '.github/workflows/macos.yml').read_text()
    command = next(line.strip() for line in workflow.splitlines() if line.strip().startswith('xcrun lipo '))
    with tempfile.TemporaryDirectory(prefix='kuraku packaging test ') as directory:
        binary = Path(directory) / 'Contents/MacOS/KuraKu'
        binary.parent.mkdir(parents=True)
        for architecture in ['arm64', 'x86_64']:
            subprocess.run(
                ['xcrun', 'clang', '-arch', architecture, '-x', 'c', '-', '-o', str(binary)],
                input='int main(void) { return 0; }\n', text=True, check=True, capture_output=True,
            )
            result = subprocess.run(
                ['bash', '-euo', 'pipefail', '-c', command],
                env={**os.environ, 'app': directory}, capture_output=True, text=True,
            )
            assert (result.returncode == 0) == (architecture == 'arm64'), result.stderr


if __name__ == '__main__':
    test_build_events()
    test_release_version()
    test_release_packages()
    test_packaging_architecture()
    print('Build events, release version, package publishing, and architecture checks passed')
