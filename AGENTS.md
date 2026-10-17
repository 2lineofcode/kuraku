# AGENTS.md

This file provides guidance to agents when working with code in this repository.

### **Language & Communication**

- Always respond in Bahasa Indonesia (Casual/Santai)
- Keep technical terms in English, don't force weird Indonesian translations

### **Code Style**

- **No Formatter**: NEVER use any code formatters
- **Follow Existing Pattern**: If the codebase has a specific pattern (indentation, bracket style, naming convention), follow it exactly
- **Keep It Simple**: Avoid over-engineering. If it can be done in 10 lines, don't make it 50
- **Readability First**: Write code that's easy for humans to read, not just "works"
- **remove compile file**: if you compile code, please remove, example `__pycache__`

### **Documentation**

- Minimalist comments. Don't explain the obvious
- BAD example: `// increment i by 1` → i++
- GOOD example: `// workaround for bug in library X v2.1`
- Comments language: English

### **Problem Solving**

- **Think First**: Explain the logic before giving code
- **Edge Cases**: Always consider error handling and edge cases
- **No YOLO Code**: Don't blindly copypaste from the internet without understanding
- **Clarify Ambiguity**: If anything is ambiguous, ask for clarification first. Do not execute unless you are 100% sure you understand the requirements.

### **Tools & Commands**

- Read the file content first before editing
- When in doubt, ask before executing

### **Language Separation**

- Respond in Bahasa Indonesia (Casual), but code elements (comments, vars, docs) MUST be in English.

## Project Overview

kuraku is a Flutter desktop application for managing JAV (Japanese Adult Video) content using GetX state management.

## Critical Setup Requirements

- **External R18 Database**: App requires downloading external database dumps from AWS S3 on first run
- **Python Dependencies**: Uses Python script (assets/r18_database_importer.py) to convert PostgreSQL dumps to SQLite
- **Database Detection**: App checks for r18\*.db files in app directory on startup, shows download dialog if missing
- **Environment Configuration**: Uses enven package to generate env.g.dart from .env file

## Database Architecture

- **Dual Database System**: Uses both kuraku.db (main app data) and r18\*.db (external content database)
- **Versioned External DB**: R18 database files are versioned by date in filename (r18_YYYYMMDD.db format)
- **Database Indexes**: Extensive indexing on videos table for performance (video_path, video_code, title, actress, etc.)
- **JSON Storage**: Complex fields (actress, category, screenshot) stored as JSON strings in SQLite

## Adult Content Management Patterns

- **Video Code Validation**: Complex validation system with blacklisted prefixes (TK, 7, 9, K9, FTKT, etc.) and suffixes (BOD, DOD, Ta, etc.)
- **Subtitle Detection**: Automatic detection of English (-en), Indonesian (-id, indo), and uncensored (-un, -rm) content
- **Actress Name Formatting**: Special formatting logic for Japanese names with number removal and capitalization
- **Video Quality Mapping**: Specific resolution mappings (3840x2160=4K, 1920x1080=FHD, etc.) with portrait variants
- **Content Organization**: External drive detection with platform-specific logic (Windows drives > E:, macOS /Volumes/, Linux /media|/mnt)

## GetX Architecture Patterns

- **Service Initialization**: Critical service initialization order - AppSettingService before DBService
- **Hotkey Management**: Must unregister all hotkeys on app startup using hotkey_manager
- **Fullscreen Handling**: Requires Get.forceAppUpdate() when entering/leaving fullscreen mode
- **Dependency Injection**: Uses Get.putAsync() with permanent: true for core services

## Code Style & Linting (Non-Standard)

- **Print Statements Allowed**: avoid_print: false (unusual for Flutter apps)
- **Constant Identifiers Allowed**: constant_identifier_names: false (allows non-const identifiers)
- **Relative Imports Required**: prefer_relative_imports: true (enforced)
- **Single Quotes Required**: prefer_single_quotes: true (enforced)
- **Relaxed Curly Braces**: curly_braces_in_flow_control_structures: false
- **TODO Comments Ignored**: todo: ignore (no warnings for TODO comments)
- **Protected Members Allowed**: invalid_use_of_protected_member: ignore

## External API Integration

- **Image URLs**: Generated via proxy API (kuraku-api.vercel.app) for DMM content
- **Video Trailers**: Direct URLs to external video hosting (njavtv.com, missav.live, javmost.com)
- **Actress Data**: Proxy API for actress photos from DMM (pics.dmm.co.jp/mono/actjpgs)

## Platform-Specific Behaviors

- **Window Management**: Implements WindowListener for fullscreen and close events
- **External Drive Logic**: Platform-specific detection for removable media
- **Audio Notifications**: Plays notification sounds for download completion (assets/download_complete.mp3)
- **Shell Commands**: Uses process_run for executing gunzip and python scripts

## Testing Considerations

- **Targeted Tests Only**: When adding or changing unit tests, run only the affected test files and directly related regression tests. Do not run the full suite unless the user explicitly requests it.
- **Low Local Load**: Run local Flutter tests sequentially with `nice -n 10 flutter test --no-pub --concurrency=1 test/affected_test.dart`. Do not run tests, analysis, or builds in parallel.
- **Avoid Repeated Work**: After related checks pass, rerun only when new changes or failures require it. Keep Python workers and database fixtures alive within a test instead of recreating them for every query, and close them in teardown.

- **Database Dependencies**: Tests require both main and R18 databases to be present
- **External Services**: Tests may fail if external APIs (DMM, JAV sites) are unavailable
- **File System Access**: Tests need appropriate permissions for external drives and file operations

## Development Commands

- **Build Commands**: Standard Flutter build (flutter build macos)
- **Database Setup**: Requires manual download of R18 database dump on first run
- **Python Dependencies**: Ensure Python 3 and required libraries for database conversion
