import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabase {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _open();
    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) {
      return;
    }
    await db.close();
    _database = null;
  }

  Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = await _databasePath();
    return openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
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
        updated_at TEXT NOT NULL
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
        frequency_penalty REAL,
        presence_penalty REAL,
        seed INTEGER,
        enable_thinking INTEGER,
        embedding_model TEXT,
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
        vision_provider_id TEXT,
        tts_provider_id TEXT,
        stt_provider_id TEXT,
        realtime_provider_id TEXT,
        omni_provider_id TEXT
      )
    ''');
  }
}
