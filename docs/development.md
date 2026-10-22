# Development

[← README](../README.md)

## Requirements

- Flutter ≥3.47.0 and Dart ≥3.13.0 <4.0.0. CI uses Flutter 3.47.7.
- Git, Bash, and GNU Make. Run commands from the repository root; use Git Bash on Windows.
- Python 3 for R18 import and local catalog queries. Optional Visual Search needs Python 3.12–3.14 with pip and venv.

Build on the target OS. Current distribution targets are Apple Silicon macOS 26+, Ubuntu 22.04 x64, and Windows 10/11 x64.

## Platform setup

### macOS

Install Xcode and its Command Line Tools, then use Homebrew:

```bash
brew install cocoapods python@3.13 ffmpeg
flutter config --enable-macos-desktop
```

### Ubuntu 22.04 x64

Native headers are required even after `flutter pub get`:

```bash
sudo apt update
sudo apt install git make clang cmake ninja-build pkg-config libunwind-dev \
  libgtk-3-dev libmpv-dev libkeybinder-3.0-dev libjson-glib-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good libwebkit2gtk-4.1-dev \
  libopencore-amrnb0 libvo-amrwbenc0 libvpx7 libx265-199 libicu70 \
  python3 python3-pip python3-venv ffmpeg curl xdg-utils
flutter config --enable-linux-desktop
```

The bundled FFmpegKit libraries depend on Ubuntu 22.04's codec and ICU versions. Newer distributions may need a native library rebuild.

### Windows x64

1. Install Visual Studio 2022 with **Desktop development with C++** and the Windows SDK.
2. Enable Windows **Developer Mode** for Flutter plugin symlinks.
3. Install Git for Windows, GNU Make, Python (including pip/venv), and FFmpeg. Add their command-line tools to `PATH`.
4. In Git Bash, check `make --version`, then enable the desktop target:

```bash
flutter config --enable-windows-desktop
```

### Download tools

Install Chrome/Chromium for website capture and yt-dlp for YouTube downloads. FFmpeg is needed for HLS downloads. Keep command-line tools on `PATH`.

Downloader details: [Linux](../assets/bin/linux-x64/README.md) · [Windows](../assets/bin/windows-x64/README.md).

## Run

After cloning the repository and completing platform setup:

```bash
[ -f .env ] || cp .env.sample .env
make deps
make env
make doctor
make run
```

`make run` detects the host OS. Pass Flutter arguments with `make run ARGS="--release"`.

On first launch, choose **Download & Install** to import the R18 catalog. Wait for it to finish, then restart the app.

## macOS audio normalization

The local `media_kit_libs_macos_video` override downloads a checksum-pinned framework archive from [kuraku-libmpv](https://github.com/2lineofcode/kuraku-libmpv). It keeps the upstream libmpv/codecs and enables the FFmpeg filters needed for audio normalization. No extra playback tools are required at runtime.

To update it, build and verify a new artifact in that fork, publish a new immutable release, then update the version and SHA-256 in `packages/media_kit_libs_macos_video/macos/Makefile`. Keep the plugin override in the repository; do not patch the global pub cache.

## Configuration

Use [.env.sample](../.env.sample) as the starting point. Keep `APP_NAME=kuraku` unchanged: it identifies the app's data directory.

After editing `.env`, run `make env` and restart/rebuild. Enven embeds values into the app; do not distribute builds containing personal keys. Public CI uses `.env.sample`.

## Build & package

```bash
make install
```

This generates the environment, refreshes dependencies, builds a release, and installs or packages it. The build number uses `YYYYMMDD.sequence`; `pubspec.yaml` is updated only after build and installation/packaging succeed.

| Platform | Result |
|---|---|
| macOS | Installs `KuraKu.app` to `/Applications` (may request sudo) |
| Linux | Creates a `.deb` and SHA-256 checksum in `dist/` |
| Windows | Creates a portable ZIP and SHA-256 checksum in `dist/` |

Select a target explicitly with `make install TARGET=macos`, `TARGET=linux`, or `TARGET=windows`. This does not enable cross-compilation or upload a release.

For a build without installation or version changes:

```bash
make build
```

`make build` detects the host OS; override it with `TARGET=macos`, `TARGET=linux`, or `TARGET=windows`. Run `make deps` and `make env` first. Package an existing Linux build with `bash tool/package_linux.sh`; on Windows, run `./tool/package_windows.ps1` in PowerShell.

Run `make` or `make help` to list all targets. `ARGS="..."` forwards Flutter arguments for `run`, `build`, `analyze`, and `test`. `make clean` removes Flutter's `build/` and `.dart_tool/`; run `make deps` afterward.

## Checks

Run checks sequentially. Replace the example test with the affected test file; do not run the full suite for an unrelated change.

```bash
make analyze
make test TEST=test/app_dependencies_test.dart
python3 -B test/makefile_test.py
git diff --check
```

`make test` requires `TEST` (a file or directory), runs with `--concurrency=1`, and uses `nice -n 10` when available. Use `TEST=test` only when intentionally running the full suite. In Windows Git Bash, use `python -B` if Python is installed as `python`.

Open the live Flutter component gallery with `make run ARGS="-t tool/ui_catalog_flutter.dart"`.
See the [R18 query benchmark report](r18_query_benchmark.md) for historical measurements and reproduction commands using the current query test harness.

## Troubleshooting

| Problem | Check |
|---|---|
| Linux CMake cannot find GStreamer | Install `libgstreamer1.0-dev` and `libgstreamer-plugins-base1.0-dev` |
| Linux CMake cannot find keybinder | Install `libkeybinder-3.0-dev` |
| Windows plugin symlink error | Enable Developer Mode |
| `make` or another command is missing | Install it, check `PATH`, then reopen the terminal |
| App reports missing dependencies | Follow the startup dialog's guidance, then click **Check again** |

## CI & releases

| Trigger | Checks | Release build, package & smoke tests | GitHub Release |
|---|---|---|---|
| Push to `main` / PR targeting `main` | Yes | No | No |
| Push tag `v*` | Yes | Yes | DMG, .deb, ZIP, and checksums |
| Manual **Run workflow** | Yes | Yes | No |

Release tags must match the version in `pubspec.yaml`, for example `v1.0.2` for `1.0.2+20261017.83`. The Release workflow reuses all three platform workflows and publishes their packages together only after every platform succeeds. Manual runs upload Actions artifacts without publishing a release. Native build/startup failures are caught on tag or manual runs; use a manual run before tagging changes to native code.

Workflow configuration: [Release](../.github/workflows/release.yml) · [macOS](../.github/workflows/macos.yml) · [Linux](../.github/workflows/linux.yml) · [Windows](../.github/workflows/windows.yml).
