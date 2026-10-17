<img src="assets/app_icon.png" width="96" alt="KuraKu app icon">

# KuraKu 🇯🇵

> **NSFW** — A Desktop app for organizing, searching, and playing your personal Japanese Adult Video (JAV) collection.

Add local or external-drive folders, scan videos, enrich recognized codes with R18 metadata, and manage everything in one place. Built with Flutter, GetX, SQLite, and media_kit.

![KuraKu walkthrough: Home, Search, Explore, and Download](.screenshot/demo.gif)

## Features

- Library scanning, automatic updates, metadata, favorites, playlists, and multi-selection.
- Search by code, title, actress, category, or optional offline CLIP Visual Search.
- Playback with mini player, fullscreen, subtitles, screenshots, and watch tracking.
- Website, HLS, direct-file, and YouTube downloads.
- Large-file and duplicate tools, quality scanning, SQL editor, and activity stats.
- AI chat with local catalog queries, title translation, and optional web search.
- English and Bahasa Indonesia; change language in **Settings → Appearance**.

## Platforms & Downloads

| Platform | Current support |
|---|---|
| macOS | Apple Silicon; bundled downloader requires macOS 26+ |
| Linux | Ubuntu 22.04 x64; FFmpegKit requires this baseline's codec/ICU libraries |
| Windows | Planned |

Get macOS DMGs from [GitHub Releases](https://github.com/2lineofcode/kuraku/releases); Linux CI provides `.deb` artifacts. On macOS, drag KuraKu to Applications; unsigned builds may need **Privacy & Security → Open Anyway**. On Linux, install with `sudo apt install ./KuraKu-<version>-linux-x64.deb`.

Python 3 is required for database setup and local queries. Install Chrome/Chromium for website capture and yt-dlp for YouTube. Downie integration is macOS-only.

## Development

Use Flutter `>=3.47.0` and Dart `>=3.13.0 <4.0.0` (CI: Flutter `3.47.7`). Clone this repository, then install your platform's native dependencies.

**macOS:** install Xcode and Command Line Tools, then:

```bash
brew install cocoapods python@3.13 ffmpeg
flutter config --enable-macos-desktop
```

**Ubuntu 22.04 x64:** native headers are required even after `flutter pub get`:

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev \
  libkeybinder-3.0-dev libjson-glib-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good \
  libwebkit2gtk-4.1-dev libopencore-amrnb0 libvo-amrwbenc0 \
  python3 python3-venv ffmpeg curl xdg-utils
flutter config --enable-linux-desktop
```

From the repository root:

```bash
[ -f .env ] || cp .env.sample .env
flutter pub get
dart run enven
flutter doctor -v
./run.sh
```

`run.sh` selects the host platform. For Linux CMake errors, `audioplayers_linux` needs the GStreamer development packages above; `hotkey_manager_linux` needs `libkeybinder-3.0-dev`.

## Build & Checks

- Run `./publish.sh` on the target OS: macOS installs to `/Applications/KuraKu.app`; Linux creates a `.deb` and SHA-256 checksum in `dist/`. The script updates the build number but does not upload releases.
- For a Linux bundle without version changes: `flutter build linux --release --no-tree-shake-icons`, then `bash tool/package_linux.sh`. Distribute the complete bundle, including `lib/` and `data/`.
- Commit dependency lockfiles. Run `flutter analyze --no-pub` and affected tests with `nice -n 10 flutter test --no-pub --concurrency=1 test/<affected_test>.dart`.
- CI builds both supported platforms. A `v<major.minor.patch>` tag matching `pubspec.yaml` publishes the macOS release; Linux currently uploads Actions artifacts only.
- Linux downloader source revision: [assets/linux-x64/README.md](assets/linux-x64/README.md).

## First Run & Data

Accept **Download & Install** to fetch and import the R18 catalog; this can take several minutes. Keep the app open until it finishes, then restart. Missing dependencies show recovery instructions at startup.

App data contains `kuraku.db`, `r18_YYYYMMDD.db`, caches, and optional `semantic_runtime`. It lives under the system Documents directory: `KuraKu` on macOS and hidden `.KuraKu` on Linux (possibly `~/.KuraKu`). Linux migrates the old folder automatically; if both names exist, startup stops without overwriting either. Press Ctrl+H to show hidden folders. Keep `APP_NAME=kuraku` as the storage identity.

Linux drag-out updates paths for same-filesystem moves. Cross-filesystem or moves exceeding ten seconds need a destination rescan. Notifications require a desktop notification service. App shortcuts use Command on macOS and Ctrl on Linux; open the shortcut panel with Command/Ctrl + `/`.

## Optional Setup

**Visual Search:** **Settings → Visual Search → Set up → Index new / changed**. Requires Python 3.12–3.14 with venv support and downloads about 155 MB of models plus Python dependencies. Search in English; indexing/search runs offline after setup and pauses during playback. Results compare one frame per video and may miss scenes.

**AI chat:** open AI settings in the chat toolbar to set the provider, Base URL, model, and API key. Settings are saved in AppPref and apply immediately without restarting or rebuilding. The provider must support HTTPS OpenAI-compatible chat completions, streaming, and tool calls. Add `TAVILY_API_KEY` to `.env` for web search, then run `dart run enven` and restart/rebuild. Exact local queries work without an API key.

AI requests may include conversation history and selected library/catalog metadata; web search sends queries to Tavily. Enven embeds keys into builds, so do not distribute builds containing personal credentials. Public CI builds use `.env.sample` without personal keys.

Contributions toward existing features and additional Desktop platforms are welcome.
