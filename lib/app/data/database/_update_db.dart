import 'package:sqflite/sqflite.dart';

import '../../core/app_logging.dart';
import '../models/activity_entity.dart';
import '../models/search_site.dart';

mixin DBUpdate {
  // Version 1 lives in DBService.onCreate. Append new migrations; never edit released steps.
  static const _migrations = <int, ({String name, Future<void> Function(Database) run})>{
    2: (name: 'Create feature tables', run: _createLegacyFeatureTables),
    3: (name: 'Repair missing feature tables', run: _createLegacyFeatureTables),
    4: (name: 'Remove unused feature tables', run: _v4RemoveUnusedTables),
    5: (name: 'Restore feature tables', run: _createLegacyFeatureTables),
    6: (name: 'Link playlist items by ID', run: _v6PlaylistIds),
    7: (name: 'Add search history', run: _v7SearchHistory),
    8: (name: 'Add chat conversations and messages', run: _v8Chat),
    9: (name: 'Save chat activity summaries', run: _v9ChatActivity),
    10: (name: 'Cache title translations', run: _v10ChatTranslations),
    11: (name: 'Separate playlists and memberships', run: _v11Playlists),
    12: (name: 'Harden watch history and reconcile duration', run: _v12WatchSessions),
    13: (name: 'Pin chat conversations', run: _v13PinnedChats),
    14: (name: 'Separate todos, download logs and relapse events', run: _v14Activity),
    15: (name: 'Harden library integrity, caches and metadata', run: _v15Integrity),
    16: (name: 'Soft delete videos', run: _v16SoftDeleteVideos),
    17: (name: 'Preserve file identity across library moves', run: _v17FileIdentity),
    18: (name: 'Add library image albums', run: _v18ImageAlbums),
    19: (name: 'Add configurable search sites', run: _v19SearchSites),
  };

  static Future<void> _v19SearchSites(Database db) async {
    await db.execute('''CREATE TABLE search_site (
      name TEXT NOT NULL PRIMARY KEY COLLATE NOCASE CHECK(length(trim(name)) BETWEEN 1 AND 60 AND name = trim(name)),
      search_url TEXT NOT NULL CHECK(instr(search_url, '{code}') > 0),
      download_url TEXT NOT NULL CHECK(instr(download_url, '{code}') > 0)
    )''');
    for (final site in SearchSite.defaults) {
      await db.execute("INSERT INTO search_site VALUES ('${site.name}', '${site.searchUrl}', '${site.downloadUrl}')");
    }
  }

  static Future<void> _v18ImageAlbums(Database db) async {
    await db.execute("ALTER TABLE library ADD COLUMN images TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(images) AND json_type(images) = 'array')");
  }

  static int get version {
    var expected = 2;
    for (final current in _migrations.keys) {
      if (current != expected) throw StateError('Expected database migration v$expected, found v$current');
      expected++;
    }
    return expected - 1;
  }

  // sqflite wraps onCreate/onUpgrade and user_version in one transaction.
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1 || newVersion < oldVersion || newVersion > version) {
      throw StateError('Unsupported database upgrade: v$oldVersion -> v$newVersion (latest: v$version)');
    }
    for (var next = oldVersion + 1; next <= newVersion; next++) {
      final migration = _migrations[next]!;
      AppLog.logD('Database migration v$next: ${migration.name}');
      try {
        await migration.run(db);
      } catch (error) {
        AppLog.logE('Database migration v$next (${migration.name}) failed: $error');
        rethrow;
      }
    }
  }

  static Future<void> onDowngrade(Database db, int oldVersion, int newVersion) async {
    throw StateError('Database v$oldVersion is newer than supported v$newVersion. Open it with a newer app version.');
  }

  // Preserve the shared, idempotent repair used by legacy v2/v3/v5.
  static Future<void> _createLegacyFeatureTables(Database db) async {
    // watch sessions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS watch_session (
        id                          TEXT PRIMARY KEY,
        video_id                    TEXT,
        video_code                  TEXT,
        watched_seconds             INTEGER,
        created_at                  TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_watch_session_created_at ON watch_session(created_at);');

    // achievement unlock history
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievement_unlock (
        id                          TEXT PRIMARY KEY,
        achievement_key             TEXT UNIQUE,
        title                       TEXT,
        description                 TEXT,
        unlocked_at                 TEXT,
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_achievement_unlock_key ON achievement_unlock(achievement_key);');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_embeddings (
        video_id                     TEXT PRIMARY KEY,
        source_text                  TEXT,
        embedding                    TEXT,
        model                        TEXT,
        created_at                   TEXT,
        updated_at                   TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_video_embeddings_updated_at ON video_embeddings(updated_at);');

  }

  static Future<void> _v4RemoveUnusedTables(Database db) async {
    await db.execute('DROP TABLE IF EXISTS watch_next_item');
    await db.execute('DROP TABLE IF EXISTS watch_next_queue');
    await db.execute('DROP TABLE IF EXISTS health_snapshot');
  }

  static Future<void> _v6PlaylistIds(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(collection)');
    if (!columns.any((column) => column['name'] == 'playlist_id')) {
      await db.execute('ALTER TABLE collection ADD COLUMN playlist_id TEXT REFERENCES collection(id) ON DELETE CASCADE');
    }
    // Recover legacy groups that have video rows but no playlist header.
    await db.execute('''
      INSERT INTO collection (id, type, name, cover, created_at, updated_at)
      SELECT lower(hex(randomblob(16))), 'playlist', items.name, MAX(items.cover),
             MIN(items.created_at), MAX(items.updated_at)
      FROM collection AS items
      WHERE items.type = 'playlist' AND items.video_id IS NOT NULL AND items.playlist_id IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM collection AS header
          WHERE header.type = 'playlist' AND header.video_id IS NULL AND header.name IS items.name
        )
      GROUP BY items.name
    ''');
    await db.execute('''
      UPDATE collection AS items
      SET playlist_id = (
        SELECT header.id FROM collection AS header
        WHERE header.type = 'playlist' AND header.video_id IS NULL AND header.name IS items.name
        ORDER BY header.id LIMIT 1
      )
      WHERE items.type = 'playlist' AND items.video_id IS NOT NULL AND items.playlist_id IS NULL
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_collection_playlist_id ON collection(playlist_id)');
  }

  static Future<void> _v7SearchHistory(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS historical (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        query TEXT NOT NULL COLLATE NOCASE,
        updated_at INTEGER NOT NULL,
        UNIQUE(type, query)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_historical_recent ON historical(type, updated_at DESC)');
  }


  static Future<void> _v8Chat(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_conversation (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
        draft TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_activity_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_message (
        id TEXT NOT NULL PRIMARY KEY,
        conversation_id TEXT NOT NULL REFERENCES chat_conversation(id) ON DELETE CASCADE,
        position INTEGER NOT NULL CHECK(position >= 1),
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
        content TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL CHECK(status IN ('pending', 'streaming', 'completed', 'failed', 'cancelled')),
        provider TEXT,
        model TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(conversation_id, position)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_chat_recent ON chat_conversation(last_activity_at DESC, id)');
  }
  static Future<void> _v9ChatActivity(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(chat_message)');
    if (!columns.any((column) => column['name'] == 'activity')) {
      await db.execute("ALTER TABLE chat_message ADD COLUMN activity TEXT NOT NULL DEFAULT '{}'");
    }
  }

  static Future<void> _v10ChatTranslations(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_translation (
        source_text TEXT NOT NULL,
        target_language TEXT NOT NULL,
        translated_text TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (source_text, target_language)
      )
    ''');
  }

  static Future<void> _v11Playlists(Database db) async {
    final unsupported = await db.rawQuery("SELECT id FROM collection WHERE type IS NULL OR type != 'playlist' LIMIT 1");
    if (unsupported.isNotEmpty) throw StateError('Cannot migrate unsupported collection types; original data is preserved');
    await db.execute('''
      CREATE TABLE playlist (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        name TEXT NOT NULL COLLATE NOCASE UNIQUE
          CHECK(length(trim(name)) > 0 AND name = trim(name) AND lower(name) != 'favorite'),
        cover TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE playlist_item (
        playlist_id TEXT NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
        video_id TEXT NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (playlist_id, video_id)
      )
    ''');
    await db.execute('CREATE INDEX idx_playlist_item_video_id ON playlist_item(video_id)');
    await db.execute('''
      INSERT INTO playlist (id, name, cover, created_at, updated_at)
      SELECT id, trim(name), cover, COALESCE(created_at, CURRENT_TIMESTAMP), COALESCE(updated_at, CURRENT_TIMESTAMP)
      FROM collection WHERE video_id IS NULL
    ''');
    await db.execute('''
      INSERT INTO playlist_item (playlist_id, video_id, created_at)
      SELECT playlist_id, video_id, COALESCE(MIN(created_at), CURRENT_TIMESTAMP)
      FROM collection WHERE video_id IS NOT NULL
      GROUP BY playlist_id, video_id
    ''');
    await db.execute('DROP TABLE collection');
  }

  static Future<void> _v12WatchSessions(Database db) async {
    // History survives library deletion and can include videos opened outside the library.
    await db.execute('''
      CREATE TABLE watch_session_new (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        video_id TEXT,
        video_code TEXT,
        watched_seconds INTEGER NOT NULL CHECK(typeof(watched_seconds) = 'integer' AND watched_seconds > 0),
        created_at TEXT NOT NULL CHECK(length(created_at) >= 10)
      )
    ''');
    await db.execute('''
      INSERT INTO watch_session_new (id, video_id, video_code, watched_seconds, created_at)
      SELECT id, video_id, video_code, watched_seconds, created_at FROM watch_session
    ''');
    await db.execute('DROP TABLE watch_session');
    await db.execute('ALTER TABLE watch_session_new RENAME TO watch_session');
    await db.execute('CREATE INDEX idx_watch_session_created_at ON watch_session(created_at)');
    await db.execute('''
      UPDATE profile SET total_watch_duration = (SELECT COALESCE(SUM(watched_seconds), 0) FROM watch_session)
      WHERE id = '1'
    ''');
  }

  static Future<void> _v13PinnedChats(Database db) async {
    await db.execute('ALTER TABLE chat_conversation ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0 CHECK(is_pinned IN (0, 1))');
    await db.execute('DROP INDEX idx_chat_recent');
    await db.execute('CREATE INDEX idx_chat_recent ON chat_conversation(is_pinned DESC, last_activity_at DESC, id)');
  }

  static Future<void> _v14Activity(Database db) async {
    final unsupported = await db.rawQuery("SELECT id FROM activity WHERE type IS NULL OR type NOT IN ('todo', 'download', 'relapse') LIMIT 1");
    if (unsupported.isNotEmpty) throw StateError('Cannot migrate unsupported activity types; original data is preserved');
    await db.execute('''
      CREATE TABLE todo (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        title TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(title)) > 0 AND title = trim(title)),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_todo_recent ON todo(updated_at DESC, id)');
    await db.execute(r'''
      CREATE TABLE download_log (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        payload TEXT NOT NULL CHECK(CASE WHEN json_valid(payload) THEN json_type(payload) = 'object' ELSE 0 END),
        filename TEXT GENERATED ALWAYS AS (json_extract(payload, '$.filename')) STORED,
        url TEXT GENERATED ALWAYS AS (json_extract(payload, '$.url')) STORED,
        directory TEXT GENERATED ALWAYS AS (json_extract(payload, '$.dir')) STORED,
        status TEXT GENERATED ALWAYS AS (COALESCE(json_extract(payload, '$.ev'), json_extract(payload, '$.status'), 'unknown')) STORED,
        output_path TEXT GENERATED ALWAYS AS (json_extract(payload, '$.output_path')) STORED,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_download_log_recent ON download_log(updated_at DESC, id)');
    await db.execute('CREATE INDEX idx_download_log_filename ON download_log(filename COLLATE NOCASE)');
    await db.execute('''
      CREATE TABLE relapse_event (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        occurred_on TEXT NOT NULL CHECK(
          occurred_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
          AND date(occurred_on, '+0 days') IS occurred_on
        ),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_relapse_event_day ON relapse_event(occurred_on DESC, created_at DESC, id DESC)');
    await db.execute('CREATE INDEX idx_relapse_event_recent ON relapse_event(created_at DESC, id DESC)');
    for (final mapping in [('todo', 'todo', 'title'), ('download', 'download_log', 'payload'), ('relapse', 'relapse_event', 'occurred_on')]) {
      final content = mapping.$1 == 'todo' ? 'trim(content)' : 'content';
      await db.execute('''
        INSERT INTO ${mapping.$2} (id, ${mapping.$3}, created_at, updated_at)
        SELECT id, $content, COALESCE(created_at, CURRENT_TIMESTAMP), COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
        FROM activity WHERE type = '${mapping.$1}'
      ''');
    }
    await db.execute('DROP TABLE activity');
    // Read compatibility only; new writes go through the domain tables.
    await db.execute('''
      CREATE VIEW activity AS
      SELECT id, 'todo' AS type, title AS content, created_at, updated_at FROM todo
      UNION ALL
      SELECT id, 'download', payload, created_at, updated_at FROM download_log
      UNION ALL
      SELECT id, 'relapse', occurred_on, created_at, updated_at FROM relapse_event
    ''');
  }

  static Future<void> _v16SoftDeleteVideos(Database db) async {
    await db.execute('ALTER TABLE videos ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0 CHECK(is_deleted IN (0, 1))');
  }

  static Future<void> _v17FileIdentity(Database db) async {
    await db.execute('''
      CREATE TABLE video_file_identity (
        video_id TEXT NOT NULL PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
        filesize INTEGER NOT NULL CHECK(filesize > 0),
        modified_at INTEGER NOT NULL,
        fingerprint TEXT NOT NULL CHECK(length(fingerprint) = 64)
      )
    ''');
  }

  static Future<void> _v15Integrity(Database db) async {
    // Remove child tables before rebuilding videos; otherwise DROP triggers their cascades.
    await db.execute('CREATE TEMP TABLE playlist_item_backup AS SELECT * FROM playlist_item');
    await db.execute('DROP TABLE playlist_item');
    await db.execute('''
      CREATE TABLE videos_new (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        root_path TEXT NOT NULL CHECK(length(trim(root_path)) > 0),
        video_path TEXT NOT NULL UNIQUE CHECK(length(trim(video_path)) > 0),
        video_code TEXT, title TEXT, title_ja TEXT, description TEXT,
        fan_art TEXT, poster TEXT, trailer TEXT,
        actress TEXT CHECK(actress IS NULL OR CASE WHEN json_valid(actress) THEN json_type(actress) = 'array' ELSE 0 END),
        category TEXT CHECK(category IS NULL OR CASE WHEN json_valid(category) THEN json_type(category) = 'array' ELSE 0 END),
        release_date TEXT, release_date_formated TEXT,
        duration INTEGER NOT NULL DEFAULT 0 CHECK(typeof(duration) = 'integer' AND duration >= 0),
        duration_formated TEXT, studio TEXT, label TEXT, director TEXT, series TEXT,
        screenshot TEXT CHECK(screenshot IS NULL OR CASE WHEN json_valid(screenshot) THEN json_type(screenshot) = 'array' ELSE 0 END),
        view_count INTEGER NOT NULL DEFAULT 0 CHECK(typeof(view_count) = 'integer' AND view_count >= 0),
        site TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0 CHECK(is_favorite IN (0, 1)),
        filesize INTEGER NOT NULL DEFAULT 0 CHECK(typeof(filesize) = 'integer' AND filesize >= 0),
        quality TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      INSERT INTO videos_new
      SELECT id, root_path, video_path, video_code, title, title_ja, description, fan_art, poster, trailer,
        actress, category, release_date, release_date_formated, COALESCE(duration, 0), duration_formated,
        studio, label, director, series, screenshot, COALESCE(view_count, 0), site, COALESCE(is_favorite, 0),
        COALESCE(filesize, 0), quality, COALESCE(created_at, CURRENT_TIMESTAMP), COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
      FROM videos
    ''');
    await db.execute('DROP TABLE videos');
    await db.execute('ALTER TABLE videos_new RENAME TO videos');
    // UNIQUE(video_path) already provides its lookup index.
    for (final column in ['video_code', 'title', 'actress', 'category', 'release_date', 'duration', 'studio', 'label', 'director', 'series']) {
      await db.execute('CREATE INDEX idx_$column ON videos($column)');
    }
    await db.execute('CREATE INDEX idx_videos_root ON videos(root_path)');
    await db.execute('CREATE INDEX idx_videos_recent ON videos(created_at DESC, id)');
    await db.execute('''
      CREATE TABLE playlist_item (
        playlist_id TEXT NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
        video_id TEXT NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (playlist_id, video_id)
      )
    ''');
    await db.execute('INSERT INTO playlist_item SELECT * FROM playlist_item_backup');
    await db.execute('DROP TABLE playlist_item_backup');
    await db.execute('CREATE INDEX idx_playlist_item_video_id ON playlist_item(video_id)');

    await db.execute('''
      CREATE TABLE library_new (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        total_video INTEGER NOT NULL DEFAULT 0 CHECK(typeof(total_video) = 'integer' AND total_video >= 0),
        alias TEXT NOT NULL DEFAULT '',
        root_folder TEXT NOT NULL UNIQUE CHECK(length(trim(root_folder)) > 0),
        sub_folder TEXT CHECK(sub_folder IS NULL OR CASE WHEN json_valid(sub_folder) THEN json_type(sub_folder) = 'array' ELSE 0 END),
        videos TEXT CHECK(videos IS NULL OR CASE WHEN json_valid(videos) THEN json_type(videos) = 'array' ELSE 0 END),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      INSERT INTO library_new SELECT id, COALESCE(total_video, 0), COALESCE(alias, ''), root_folder, sub_folder, videos,
        COALESCE(created_at, CURRENT_TIMESTAMP), COALESCE(updated_at, created_at, CURRENT_TIMESTAMP) FROM library
    ''');
    await db.execute('DROP TABLE library');
    await db.execute('ALTER TABLE library_new RENAME TO library');

    await db.execute('''
      CREATE TABLE video_embeddings_new (
        video_id TEXT NOT NULL PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
        source_text TEXT NOT NULL,
        embedding BLOB NOT NULL CHECK(typeof(embedding) = 'blob' AND length(embedding) > 0 AND length(embedding) % 4 = 0),
        model TEXT NOT NULL CHECK(length(trim(model)) > 0),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    // Embeddings are rebuildable caches; retain supported vectors, discard orphan/legacy caches.
    await db.execute('''
      INSERT INTO video_embeddings_new
      SELECT e.video_id, e.source_text, e.embedding, e.model,
        COALESCE(e.created_at, CURRENT_TIMESTAMP), COALESCE(e.updated_at, e.created_at, CURRENT_TIMESTAMP)
      FROM video_embeddings e JOIN videos v ON v.id = e.video_id
      WHERE typeof(e.embedding) = 'blob' AND length(e.embedding) > 0 AND length(e.embedding) % 4 = 0
        AND e.source_text IS NOT NULL AND length(trim(e.model)) > 0
    ''');
    await db.execute('DROP TABLE video_embeddings');
    await db.execute('ALTER TABLE video_embeddings_new RENAME TO video_embeddings');
    await db.execute('CREATE INDEX idx_video_embeddings_updated_at ON video_embeddings(updated_at)');
    await db.execute('CREATE INDEX idx_watch_session_video ON watch_session(video_id, created_at)');

    await db.execute('''
      CREATE TABLE profile_new (
        id TEXT NOT NULL PRIMARY KEY CHECK(id = '1'),
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        total_watch_duration INTEGER NOT NULL DEFAULT 0 CHECK(typeof(total_watch_duration) = 'integer' AND total_watch_duration >= 0),
        badge_for_watch_duration TEXT NOT NULL DEFAULT '',
        badge_for_collection TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      INSERT INTO profile_new SELECT id, name, COALESCE(total_watch_duration, 0),
        COALESCE(badge_for_watch_duration, ''), COALESCE(badge_for_collection, ''),
        COALESCE(created_at, CURRENT_TIMESTAMP), COALESCE(updated_at, created_at, CURRENT_TIMESTAMP) FROM profile
    ''');
    await db.execute('DROP TABLE profile');
    await db.execute('ALTER TABLE profile_new RENAME TO profile');

    await db.execute('''
      CREATE TABLE achievement_unlock_new (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        achievement_key TEXT NOT NULL UNIQUE CHECK(length(trim(achievement_key)) > 0),
        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
        description TEXT NOT NULL DEFAULT '',
        unlocked_at TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      INSERT INTO achievement_unlock_new SELECT id, achievement_key, title, COALESCE(description, ''), unlocked_at,
        COALESCE(created_at, CURRENT_TIMESTAMP), COALESCE(updated_at, created_at, CURRENT_TIMESTAMP) FROM achievement_unlock
    ''');
    await db.execute('DROP TABLE achievement_unlock');
    await db.execute('ALTER TABLE achievement_unlock_new RENAME TO achievement_unlock');

    await db.execute('''
      CREATE TABLE historical_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK(length(trim(type)) > 0),
        query TEXT NOT NULL COLLATE NOCASE CHECK(length(trim(query)) > 0 AND query = trim(query)),
        updated_at INTEGER NOT NULL,
        UNIQUE(type, query)
      )
    ''');
    await db.execute('INSERT INTO historical_new SELECT id, type, query, updated_at FROM historical');
    await db.execute('DROP TABLE historical');
    await db.execute('ALTER TABLE historical_new RENAME TO historical');
    await db.execute('CREATE INDEX idx_historical_recent ON historical(type, updated_at DESC)');

    // Rebuild both chat tables together to preserve the cascade and all message positions.
    await db.execute('CREATE TEMP TABLE chat_message_backup AS SELECT * FROM chat_message');
    await db.execute('DROP TABLE chat_message');
    await db.execute('''
      CREATE TABLE chat_conversation_new (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
        draft TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        last_activity_at TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0 CHECK(is_pinned IN (0, 1))
      )
    ''');
    await db.execute('INSERT INTO chat_conversation_new SELECT * FROM chat_conversation');
    await db.execute('DROP TABLE chat_conversation');
    await db.execute('ALTER TABLE chat_conversation_new RENAME TO chat_conversation');
    await db.execute('CREATE INDEX idx_chat_recent ON chat_conversation(is_pinned DESC, last_activity_at DESC, id)');
    await db.execute('''
      CREATE TABLE chat_message (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        conversation_id TEXT NOT NULL REFERENCES chat_conversation(id) ON DELETE CASCADE,
        position INTEGER NOT NULL CHECK(typeof(position) = 'integer' AND position >= 1),
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
        content TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL CHECK(status IN ('pending', 'streaming', 'completed', 'failed', 'cancelled')),
        provider TEXT, model TEXT, error_message TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        activity TEXT NOT NULL DEFAULT '{}' CHECK(CASE WHEN json_valid(activity) THEN json_type(activity) = 'object' ELSE 0 END),
        UNIQUE(conversation_id, position)
      )
    ''');
    await db.execute('INSERT INTO chat_message SELECT * FROM chat_message_backup');
    await db.execute('DROP TABLE chat_message_backup');

    final payloadChecks = [
      for (final field in kDownloadStringFields) "(json_type(payload, '\$.$field') IS NULL OR json_type(payload, '\$.$field') IN ('text', 'null'))",
      for (final field in kDownloadIntegerFields) "(json_type(payload, '\$.$field') IS NULL OR json_type(payload, '\$.$field') IN ('integer', 'null'))",
      for (final field in kDownloadBooleanFields) "(json_type(payload, '\$.$field') IS NULL OR json_type(payload, '\$.$field') IN ('true', 'false', 'null'))",
    ].join(' AND ');
    await db.execute('DROP VIEW activity');
    await db.execute('''
      CREATE TABLE download_log_new (
        id TEXT NOT NULL PRIMARY KEY CHECK(length(trim(id)) > 0),
        payload TEXT NOT NULL CHECK(CASE WHEN json_valid(payload) THEN json_type(payload) = 'object' AND $payloadChecks ELSE 0 END),
        filename TEXT GENERATED ALWAYS AS (json_extract(payload, '\$.filename')) STORED,
        url TEXT GENERATED ALWAYS AS (json_extract(payload, '\$.url')) STORED,
        directory TEXT GENERATED ALWAYS AS (json_extract(payload, '\$.dir')) STORED,
        status TEXT GENERATED ALWAYS AS (COALESCE(json_extract(payload, '\$.ev'), json_extract(payload, '\$.status'), 'unknown')) STORED,
        output_path TEXT GENERATED ALWAYS AS (json_extract(payload, '\$.output_path')) STORED,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('INSERT INTO download_log_new (id, payload, created_at, updated_at) SELECT id, payload, created_at, updated_at FROM download_log');
    await db.execute('DROP TABLE download_log');
    await db.execute('ALTER TABLE download_log_new RENAME TO download_log');
    await db.execute('CREATE INDEX idx_download_log_recent ON download_log(updated_at DESC, id)');
    await db.execute('CREATE INDEX idx_download_log_filename ON download_log(filename COLLATE NOCASE)');
    await db.execute('''
      CREATE VIEW activity AS
      SELECT id, 'todo' AS type, title AS content, created_at, updated_at FROM todo
      UNION ALL SELECT id, 'download', payload, created_at, updated_at FROM download_log
      UNION ALL SELECT id, 'relapse', occurred_on, created_at, updated_at FROM relapse_event
    ''');
  }

}
