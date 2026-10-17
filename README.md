<img src="assets/app_icon.png" width="80" alt="KuraKu app icon">

# KuraKu 🇯🇵

[![macOS CI and Release](https://github.com/2lineofcode/kuraku/actions/workflows/macos.yml/badge.svg)](https://github.com/2lineofcode/kuraku/actions/workflows/macos.yml)
[![Linux x64 CI](https://github.com/2lineofcode/kuraku/actions/workflows/linux.yml/badge.svg)](https://github.com/2lineofcode/kuraku/actions/workflows/linux.yml)
[![Windows x64 CI](https://github.com/2lineofcode/kuraku/actions/workflows/windows.yml/badge.svg)](https://github.com/2lineofcode/kuraku/actions/workflows/windows.yml)

**NSFW** · Organize, search, play, and download your personal JAV collection.

![KuraKu demo](.screenshot/demo.gif)

## Download

| Platform | Requirements | Download |
|---|---|---|
| macOS | Apple Silicon, macOS 26+ | [DMG](https://github.com/2lineofcode/kuraku/releases) |
| Linux | Ubuntu 22.04 x64 | [.deb artifact](https://github.com/2lineofcode/kuraku/actions/workflows/linux.yml) |
| Windows | Windows 10/11 x64 | [ZIP artifact](https://github.com/2lineofcode/kuraku/actions/workflows/windows.yml) |

macOS: drag to Applications; unsigned builds may need **Privacy & Security → Open Anyway**. Linux: `sudo apt install ./KuraKu-<version>-linux-x64.deb`. Windows: extract the full ZIP and run `kuraku.exe`.

Install Python 3. On first launch, choose **Download & Install** to set up the R18 catalog, then restart.

## Development

[Development guide](docs/development.md) — platform dependencies, setup, build, and checks.

```bash
[ -f .env ] || cp .env.sample .env
flutter pub get
dart run enven
make run
```
