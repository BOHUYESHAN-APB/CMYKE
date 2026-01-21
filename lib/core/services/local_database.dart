import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class LocalDatabase {
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    final cached = _database;
    if (cached != null) {
      return cached;
    }
    final opening = _opening;
    if (opening != null) {
      return opening;
    }
    final future = _open();
    _opening = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } finally {
      if (identical(_opening, future)) {
        _opening = null;
      }
    }
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      try {
        final db = await opening;
        await db.close();
      } catch (_) {}
      _opening = null;
      _database = null;
      return;
    }
    final db = _database;
    if (db == null) {
      return;
    }
    await db.close();
    _database = null;
  }

  Future<Database> _open() async {
    final dbPath = await _databasePath();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 13,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: _createSchema,
          onUpgrade: _upgradeSchema,
        ),
      );
    }
    return openDatabase(
      dbPath,
      version: 13,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  Future<String> _databasePath() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(base.path, 'cmyke'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path.join(dir.path, 'cmyke.sqlite3');
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chat_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        mode TEXT NOT NULL DEFAULT 'standard'
      )
    ''');
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chat_messages_session_id ON chat_messages(session_id)',
    );

    await db.execute('''
      CREATE TABLE memory_collections (
        id TEXT PRIMARY KEY,
        tier TEXT NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        locked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE memory_records (
        id TEXT PRIMARY KEY,
        collection_id TEXT NOT NULL,
        tier TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        source_message_id TEXT,
        title TEXT,
        tags TEXT,
        embedding TEXT,
        embedding_model TEXT,
        session_id TEXT,
        scope TEXT,
        FOREIGN KEY(collection_id) REFERENCES memory_collections(id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_memory_records_collection_id ON memory_records(collection_id)',
    );
    await db.execute(
      'CREATE INDEX idx_memory_records_tier ON memory_records(tier)',
    );

    await db.execute('''
      CREATE TABLE providers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        base_url TEXT NOT NULL,
        model TEXT NOT NULL,
        protocol TEXT NOT NULL,
        api_key TEXT,
        capabilities TEXT,
        ws_url TEXT,
        audio_voice TEXT,
        audio_format TEXT,
        input_audio_format TEXT,
        input_sample_rate INTEGER,
        output_sample_rate INTEGER,
        audio_channels INTEGER,
        temperature REAL,
        top_p REAL,
        max_tokens INTEGER,
        context_window_tokens INTEGER,
        frequency_penalty REAL,
        presence_penalty REAL,
        seed INTEGER,
        enable_thinking INTEGER,
        embedding_model TEXT,
        embedding_base_url TEXT,
        embedding_api_key TEXT,
        notes TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_providers_kind ON providers(kind)',
    );

    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY,
        route TEXT NOT NULL,
        llm_provider_id TEXT,
        embedding_provider_id TEXT,
        vision_provider_id TEXT,
        tts_provider_id TEXT,
        stt_provider_id TEXT,
        realtime_provider_id TEXT,
        omni_provider_id TEXT,
        live3d_model_path TEXT,
        persona_mode TEXT,
        persona_level TEXT,
        persona_style TEXT,
        persona_prompt TEXT,
        enable_system_tts INTEGER NOT NULL DEFAULT 1,
        enable_system_stt INTEGER NOT NULL DEFAULT 1,
        pet_mode INTEGER NOT NULL DEFAULT 0,
        pet_follow_cursor INTEGER NOT NULL DEFAULT 1,
        motion_agent_enabled INTEGER NOT NULL DEFAULT 0,
        motion_agent_provider_id TEXT,
        motion_basic_count INTEGER NOT NULL DEFAULT 9,
        motion_agent_cooldown_seconds INTEGER NOT NULL DEFAULT 12,
        memory_agent_enabled INTEGER NOT NULL DEFAULT 0,
        memory_agent_provider_id TEXT,
        memory_agent_cooldown_seconds INTEGER NOT NULL DEFAULT 20
      )
    ''');
  }

  Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE providers ADD COLUMN embedding_base_url TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE providers ADD COLUMN embedding_api_key TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE app_settings ADD COLUMN live3d_model_path TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE memory_records ADD COLUMN session_id TEXT');
      await db.execute('ALTER TABLE memory_records ADD COLUMN scope TEXT');
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE providers ADD COLUMN context_window_tokens INTEGER',
      );
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE app_settings ADD COLUMN persona_mode TEXT');
      await db.execute('ALTER TABLE app_settings ADD COLUMN persona_level TEXT');
      await db.execute('ALTER TABLE app_settings ADD COLUMN persona_style TEXT');
      await db.execute('ALTER TABLE app_settings ADD COLUMN persona_prompt TEXT');
    }
    if (oldVersion < 8) {
      await db.execute(
        "ALTER TABLE chat_sessions ADD COLUMN mode TEXT NOT NULL DEFAULT 'standard'",
      );
    }
    if (oldVersion < 9) {
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN enable_system_tts INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN enable_system_stt INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 10) {
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN pet_mode INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN pet_follow_cursor INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 11) {
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN motion_agent_enabled INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN motion_agent_provider_id TEXT',
      );
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN motion_basic_count INTEGER NOT NULL DEFAULT 9',
      );
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN motion_agent_cooldown_seconds INTEGER NOT NULL DEFAULT 12',
      );
    }
    if (oldVersion < 12) {
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN memory_agent_enabled INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN memory_agent_provider_id TEXT',
      );
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN memory_agent_cooldown_seconds INTEGER NOT NULL DEFAULT 20',
      );
    }
    if (oldVersion < 13) {
      await db.execute(
        'ALTER TABLE app_settings ADD COLUMN embedding_provider_id TEXT',
      );
    }
  }
}
