import os
from pathlib import Path
import subprocess
import tempfile
import textwrap


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


if __name__ == '__main__':
    test_release_version()
    print('Release version checks passed')
