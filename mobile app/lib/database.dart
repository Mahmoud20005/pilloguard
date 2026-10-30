import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async =>
      _database ??= await _initDB('sleep_data.db');

  Future<Database> _initDB(String filePath) async {
    final path = join(await getDatabasesPath(), filePath);
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE SleepSessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startTime TEXT NOT NULL,
        endTime TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE SnoreEvents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        confidence REAL NOT NULL,
        FOREIGN KEY (sessionId) REFERENCES SleepSessions (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE SensorReadings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        heartRate INTEGER,
        spO2 INTEGER,
        temperature REAL,
        axisX REAL,
        axisY REAL,
        axisZ REAL,
        FOREIGN KEY (sessionId) REFERENCES SleepSessions (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE SleepSessions RENAME TO SleepSessions_old');
      await db.execute('''
        CREATE TABLE SleepSessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          startTime TEXT NOT NULL,
          endTime TEXT
        )
      ''');
      await db.execute('''
        INSERT INTO SleepSessions (id, startTime, endTime)
        SELECT id, startTime, NULLIF(endTime, startTime)
        FROM SleepSessions_old
      ''');
      await db.execute('DROP TABLE SleepSessions_old');
      await db.execute('ALTER TABLE SensorReadings ADD COLUMN temperature REAL');
    }
  }

  Future<int> createSession(DateTime startTime) async {
    final db = await database;
    return db.insert('SleepSessions', {'startTime': startTime.toIso8601String()});
  }

  Future<void> endSession(int sessionId, DateTime endTime) async {
    final db = await database;
    await db.update(
      'SleepSessions',
      {'endTime': endTime.toIso8601String()},
      where: 'id = ? AND endTime IS NULL',
      whereArgs: [sessionId],
    );
  }

  Future<void> insertSnoreEvent(int sessionId, double confidence) async {
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'Must be between 0 and 1.');
    }
    final db = await database;
    await db.insert('SnoreEvents', {
      'sessionId': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
      'confidence': confidence,
    });
  }

  Future<void> insertSensorReading(
    int sessionId,
    Map<String, dynamic> telemetry,
  ) async {
    final db = await database;
    await db.insert('SensorReadings', {
      'sessionId': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
      'heartRate': (telemetry['heart_rate'] as num?)?.toInt(),
      'spO2': (telemetry['spo2'] as num?)?.toInt(),
      'temperature': (telemetry['temperature'] as num?)?.toDouble(),
      'axisX': (telemetry['accel_x'] as num?)?.toDouble(),
      'axisY': (telemetry['accel_y'] as num?)?.toDouble(),
      'axisZ': (telemetry['accel_z'] as num?)?.toDouble(),
    });
  }

  Future<Map<String, dynamic>?> getLatestSession() async {
    final db = await database;
    final result = await db.query('SleepSessions', orderBy: 'id DESC', limit: 1);
    return result.isEmpty ? null : result.first;
  }

  Future<List<Map<String, dynamic>>> getSessionData(int sessionId) async {
    final db = await database;
    return db.query(
      'SensorReadings',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getSnoreEvents(int sessionId) async {
    final db = await database;
    return db.query(
      'SnoreEvents',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }
}
