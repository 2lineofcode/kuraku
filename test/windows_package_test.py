import hashlib
from pathlib import Path
import struct
import zipfile


def pe_machine(data):
    assert data[:2] == b'MZ', 'Missing DOS header'
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[offset:offset + 4] == b'PE\0\0', 'Missing PE header'
    return struct.unpack_from('<H', data, offset + 4)[0]


def main():
    root = Path(__file__).resolve().parents[1]
    downloader = root / 'assets/bin/windows-x64/kuraku.exe'
    assert pe_machine(downloader.read_bytes()) == 0x8664, 'Downloader must be Windows x64'
    readme = (downloader.parent / 'README.md').read_text()
    assert hashlib.sha256(downloader.read_bytes()).hexdigest() in readme, 'Downloader checksum changed'
    archives = list((root / 'dist').glob('*-windows-x64.zip'))
    assert archives, 'Build and package Windows before running the package check'
    for archive in archives:
        checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
        assert (Path(str(archive) + '.sha256')).read_text().strip() == f'{checksum}  {archive.name}'
        with zipfile.ZipFile(archive) as bundle:
            assert bundle.testzip() is None
            names = bundle.namelist()
            assert 'data/flutter_assets/assets/bin/macos-arm64/kuraku' not in names, 'macOS downloader must not be bundled'
            assert 'data/flutter_assets/assets/bin/linux-x64/kuraku' not in names, 'Linux downloader must not be bundled'
            for name in ['kuraku.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'libffmpegkit.dll',
                         'vcruntime140.dll', 'msvcp140.dll', 'data/app.so', 'data/icudtl.dat',
                         'data/flutter_assets/assets/bin/windows-x64/kuraku.exe']:
                assert name in names, f'Missing {name}'
            assert any('sqlite3' in name and name.endswith('.dll') for name in names)
            for name in names:
                if name.endswith('.dll') or name == 'kuraku.exe':
                    assert pe_machine(bundle.read(name)) == 0x8664, f'{name} must be x64'
    print('Windows package has valid checksums and includes x64 runtime libraries.')


if __name__ == '__main__':
    main()
