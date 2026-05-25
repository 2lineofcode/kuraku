# JavIt - Desktop 🇯🇵

(NSFW) Powerful Organize your local Japanese Adult Video (JAV)  wherever it without internet (offline)

Auto manage your local JAV like a boss 😎, search, explore, track, etc **just by drag drop your JAV folder into app**, see video how it work 😎😎

## Video Demo
![alt text](.screenshot/demo.gif)

## Screenshots

| Home | Search |
|---|---|
| ![](.screenshot/ss_home.png) | ![](.screenshot/ss_search.png) |

| Explore | Download |
|---|---|
| ![](.screenshot/ss_explore.png) | ![](.screenshot/ss_download.png) |



## Tech Stack
- **Framework**: [Flutter](https://flutter.dev/)
- **State Management**: [GetX](https://pub.dev/packages/get)
- **Database**: [SQFlite](https://pub.dev/packages/sqflite)
- **Video Player**: [Chewie](https://pub.dev/packages/chewie) & [video_player](https://pub.dev/packages/video_player)
- **Networking**: [Dio](https://pub.dev/packages/dio)

## Prerequisites

This project is currently developed and tested on macOS.

Install these first:

- macOS with Xcode + Command Line Tools
- Flutter SDK with Dart SDK `^3.5.3`
- CocoaPods
- Homebrew
- Python 3
- `gunzip` (usually already available on macOS)
- Homebrew native video dependencies:

```bash
brew install cocoapods python libiconv ffmpeg
```

Make sure Flutter desktop support is enabled:

```bash
flutter config --enable-macos-desktop
flutter doctor
```

## Local Setup

Create local env file and generate `lib/env.g.dart`:

```bash
cp .env.sample .env
flutter pub get
dart run enven
```

Run the app:

```bash
flutter run -d macos
```

On first run, JavIt will check for an `r18*.db` file in the app data directory. If it does not exist, the app will ask to download the R18 dump and convert it to SQLite using `python3` and `gunzip`.

## Troubleshooting

If macOS launch fails with:

```text
Library not loaded: /opt/homebrew/opt/libiconv/lib/libiconv.2.dylib
```

Reinstall the Homebrew native dependency and rebuild:

```bash
brew reinstall libiconv ffmpeg
brew link --overwrite libiconv
flutter clean
flutter pub get
dart run enven
flutter run -d macos
```

---

## 🤗 Contributors
i create this project just for hobbies while im free with flutter, and i just have a macbook, so i build for macos only, but feel free to open PR if you want to build to other platform :))
