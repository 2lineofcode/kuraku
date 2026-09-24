import 'package:sqflite/sqflite.dart';

import '../../core/app_logging.dart';

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
  };

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

}
