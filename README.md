# JavIt Desktop 🇯🇵

> **NSFW** — A macOS desktop app for organizing and playing a local Japanese Adult Video (JAV) collection.

JavIt turns video folders on your Mac or external drives into a searchable personal library. Add a folder, let the app scan its videos, enrich recognized video codes with metadata, then browse, search, play, and manage the collection from one place.

![JavIt demo](.screenshot/demo.gif)

## What It Does

- Add a library by selecting or drag-and-dropping a video folder.
- Scan supported local video files and keep registered libraries in sync.
- Detect JAV video codes from filenames and look up matching metadata from the local R18 database.
- Browse recent releases, recently added videos, favorites, most watched videos, unwatched videos, and random picks.
- Search the local collection by video code, title, path, actress, category, and other filters.
- Play local files with playlist support, mini player, fullscreen, playback speed, volume persistence, and watch tracking.
- Explore metadata by actress, series, category, and year.
- Find large files and possible duplicates, scan video quality, and manage simple todos.
- Search and download supported releases from the Download page.

## How It Works

```text
Local video folders
        |
        v
Scan files and detect video codes
        |
        +--> R18 database lookup for metadata
        |
        v
javit.db personal library
        |
        v
Home, Search, Explore, Tools, and Player
```

JavIt uses two SQLite databases:

- **`javit.db`** stores your libraries, local video records, favorites, collections, watch sessions, achievements, activities, and search indexes.
- **`r18_YYYYMMDD.db`** is the external metadata catalog used to enrich recognized JAV files with titles, actresses, categories, studios, artwork, trailers, and more.

Files without a recognized code are still added to the library as local videos using their filename as the title.

## Search Modes

The Search page has two modes:

- **Regular search** searches the local video records directly.
- **Visual Search** uses local CLIP ViT-B/32 INT8 image/text embeddings plus exact metadata matching. Search descriptions in English, such as `a bright room` or `a forest`. Regular search remains available without model setup.

Use **Settings → Visual Search → Set up → Index new / changed**. Setup requires Python 3.12–3.14 (macOS 14+ for the pinned runtime wheels) and downloads about 155 MB of pinned, checksum-verified model/tokenizer files plus an isolated Python runtime environment. Setup tests image and text inference before marking the feature ready; failed or cancelled setup can be retried. Subsequent indexing/search stays offline. FFmpeg creates one 256-pixel frame when a cached thumbnail is unavailable; short videos fall back to their first frame. Offline/unreadable files are skipped and reported. Run **Index new / changed** again to retry them.

Indexing processes one video at a time, saves each vector immediately, and pauses while an internal player is open. **Stop** preserves completed work; restart with **Index new / changed**. Search is also suspended while a player is open to prioritize playback. Only one encoder is loaded at a time, and the worker exits after 30 idle seconds. A cold search includes model startup; repeated queries reuse cached embeddings. Vectors use 2 KB of binary float32 data each, excluding SQLite overhead. Metadata updates are read from the database without re-encoding images.

Visual search sees only one frame, so it can miss scenes or return visually similar but incorrect results. Results use fixed Strict / Balanced / Broad similarity cutoffs and relevance ordering, not a confidence percentage. Each result distinguishes Code, Metadata and Visual matches. Search shows index coverage; matching sensitivity is saved independently per tab. Existing hash-based indexes are ignored and replaced incrementally; **Rebuild frames & index** regenerates frames and visual embeddings. Changed video files are detected during indexing; thumbnail fingerprints prevent reuse after replacement. Whole-video understanding and multilingual visual queries are not provided by this lightweight version.

### Visual search checks

```bash
flutter test test/local_semantic_worker_test.dart test/page_search_tabs_test.dart test/visual_search_settings_test.dart
# RUNTIME is the app data directory's semantic_runtime folder.
"$RUNTIME/venv/bin/python" -B test/semantic_worker_test.py
"$RUNTIME/venv/bin/python" -B test/semantic_search_benchmark.py "$RUNTIME"
```

The optional benchmark expects these files in `RUNTIME/images` from the public [Transformers.js fixtures](https://huggingface.co/datasets/Xenova/transformers.js-docs/tree/main): `cats.jpg`, `corgi.jpg`, `airport.jpg`, `astronaut.png`, `beach.png`, `bread.png`, `butterfly.jpg`, `house.jpg`, `moraine-lake.png`, `sam-car.png`. It evaluates top-1 ranking without the cutoff and reports how many candidates pass Balanced. Its 10,000-row timing corpus repeats those ten embeddings; it does not measure real-library accuracy.

On the development M1 8 GB, one run ranked all 10 expected images first, with 8 passing Balanced. It measured 35 ms median cached search, 85–92 ms for subsequent uncached text queries, 713 ms for the first search, and 309 MiB process peak RSS. Image encoding took about 62–185 ms after model startup. These are worker-only measurements, excluding IPC, video frame extraction and Flutter rendering. Results depend on hardware, query and collection.

Model source: [Xenova's CLIP ONNX conversion](https://huggingface.co/Xenova/clip-vit-base-patch32) of [OpenAI CLIP](https://github.com/openai/CLIP), under the [MIT license](https://github.com/openai/CLIP/blob/main/LICENSE). The license is downloaded alongside checksum-verified weights. Python dependencies retain their respective licenses.

## Screenshots

| Home | Search |
|---|---|
| ![Home](.screenshot/ss_home.png) | ![Search](.screenshot/ss_search.png) |

| Explore | Download |
|---|---|
| ![Explore](.screenshot/ss_explore.png) | ![Download](.screenshot/ss_download.png) |

## Tech Stack

- [Flutter](https://flutter.dev/) desktop
- [GetX](https://pub.dev/packages/get) for state management and dependency injection
- [SQFlite](https://pub.dev/packages/sqflite) for local SQLite storage
- [media_kit](https://pub.dev/packages/media_kit) and libmpv for playback
- [Dio](https://pub.dev/packages/dio) for networking and downloads

## Requirements

JavIt is currently developed and tested on macOS. Install the following first:

- macOS with Xcode and Command Line Tools
- Flutter SDK with Dart SDK `^3.5.3`
- CocoaPods
- Homebrew
- Python 3
- `gunzip` (usually available on macOS)

Install the native dependencies:

```bash
brew install cocoapods python libiconv ffmpeg
```

Enable Flutter desktop support and verify the environment:

```bash
flutter config --enable-macos-desktop
flutter doctor
```

## Local Setup

Create the local environment file, fetch packages, and generate `lib/env.g.dart`:

```bash
cp .env.sample .env
flutter pub get
dart run enven
```

Run the macOS app:

```bash
flutter run -d macos
```

## AgnesAI Chat

Set these values in your local `.env`:

```dotenv
AGNES_API_KEY=your_key_here
AGNES_BASE_URL=https://apihub.agnes-ai.com/v1
AGNES_MODEL=agnes-2.5-flash
```

After changing the environment, regenerate it and restart the app:

```bash
dart run enven
flutter run -d macos
```

To verify authentication and streaming with a short test prompt:

```bash
dart run tool/agnes_smoke_test.dart
```

Chat uses hybrid local knowledge from the active `javit.db` and R18 snapshot. Exact lookups such as `Berapa jumlah video saya?`, `Tampilkan favorit saya`, or `cek kode TEST-123` run locally without an API key. Other questions go to AgnesAI; when needed, it selects a read-only SQL query and summarizes the result. Complex questions still incur API latency. Replies stream with Stop and Retry controls and are saved locally. Library access uses the `query_local` tool, separate from `web_search`; SQL is never sent to the search provider. The collapsible Thinking panel shows actual activity summaries (not private model reasoning), expands while working, and collapses automatically when the response finishes. Activity summaries and duration are saved with each reply.

The chat composer supports `/status`, `/help`, `/new`, `/stop`, `/r18`, `/filter`, `/similar`, `/translate`, and `/clear` commands without calling the model. `/clear` deletes messages and the draft only in the active conversation. Type `/` to filter commands; use arrow keys to select, Tab to complete, Enter to run, or Escape to dismiss. `/status` reports configuration, not a live connectivity check. `/r18`, `/filter`, `/similar`, and `/translate` fill editable prompts with the first placeholder selected; the same templates appear on the welcome screen. `/translate` prepares a normal chat translation request; the per-row Translate action uses the persistent title cache.

For title/topic discovery, Agnes expands the search phrase into Japanese and English equivalents and calls `search_local_titles`. It searches original Japanese titles, English titles, and cached `machine_translation` entries, including records without English titles. Results retain the Japanese title and show which field matched. This is translated keyword search, not a semantic similarity index or an automatic translation of the entire catalog. Missing cached translations do not prevent Japanese-title matching. Use `/r18` or the Japanese-title template on the welcome screen; its topic placeholder is selected for replacement. Title searches load 25 records per database page with no total result cap, ordered by newest release date and then Code; unknown dates come last. Next/Previous read the database directly without another model call; the search and current page survive chat reload. Copy includes the current page. Tables share the chat vertical scroll and only scroll horizontally themselves. Legacy DVD ID headers display as Code. The chat header provides New and Delete actions, with confirmation before deletion.

Search supports multiple required concepts (AND, with translated synonyms inside each concept), excluded terms, and “not in my library.” Similar reads the reference code's real title/description first, then matches translated themes across titles and descriptions; match fields and search terms explain the results. It keeps newest-first ordering rather than claiming a semantic similarity score. The Similar row action prepares an editable prompt. Translate opens an Indonesian translation dialog for Japanese titles, with retry on failure. Successful translations are cached in `javit.db` by source title and language and reused across chats; migration 10 creates this cache on restart without changing R18 data.

Local knowledge uses Python's standard SQLite library, without model downloads or indexing. Only selected library/catalog metadata is exposed; filesystem paths, other chats, and embeddings are excluded. Complex requests send conversation history, the allowed schema, and bounded query results to AgnesAI. Local lookup results also become part of that conversation history. Queries cannot write data, attach arbitrary databases, or read arbitrary files; they stop after ten seconds and return at most 500 rows with bounded text. Video lists are rendered directly as Image, Code, Title (followed by any additional fields), paginated at 25 rows per page. Covers are fetched in batches from library/R18 metadata and use the shared cached thumbnail widget; missing covers show a placeholder. Only the current page mounts image widgets; copying a reply includes every loaded row. Large result tables are abbreviated in subsequent model context, while the full result stays saved in chat. Missing databases or rejected queries are reported rather than treated as empty results.

Web search uses [Tavily Search](https://docs.tavily.com/documentation/api-reference/endpoint/search). Set `TAVILY_API_KEY` in `.env`, run `dart run enven`, and restart. Agnes can request `web_search`; JavIt executes the search and sends up to five result excerpts back for a sourced answer. Only the search query goes to Tavily. This is search, not a full browser or arbitrary URL reader. Search failures and missing keys are reported without fabricated results. Each model turn has at most two search rounds and three queries; Stop cancels both provider and model requests. Local lookups still work without a search key. Verify after setup with `dart run tool/agnes_smoke_test.dart --web`.

Checks: `python3 -B test/chat_knowledge_test.py` and `flutter test test/chat_knowledge_test.dart test/page_chat_response_test.dart`.

`.env` and `lib/env.g.dart` are ignored by Git. Enven embeds configuration in the desktop build: use a personal key for local builds, and do not distribute a build containing your key. Shared builds need a backend proxy or per-user credentials.

API reference: https://agnes-ai.com/en/docs/agnes-25-flash

## First Run and R18 Database Setup

On launch, JavIt looks for an `r18*.db` file in its app data directory. If one is missing, the app shows a **Download & Install** prompt.

The setup process downloads the R18 dump, extracts it with `gunzip`, then runs `r18_to_javit.py` with Python to create the SQLite database. The import can take several minutes; keep the application open until it finishes, then restart the app.

## Troubleshooting

If the macOS app fails to launch with the following error:

```text
Library not loaded: /opt/homebrew/opt/libiconv/lib/libiconv.2.dylib
```

Reinstall the native dependencies and rebuild:

```bash
brew reinstall libiconv ffmpeg
brew link --overwrite libiconv
flutter clean
flutter pub get
dart run enven
flutter run -d macos
```

## Contributing

JavIt started as a hobby project and currently targets macOS. Contributions and pull requests, including work toward other desktop platforms, are welcome.
