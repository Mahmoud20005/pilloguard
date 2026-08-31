import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sleep_data.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';

    await db.execute('''
CREATE TABLE SleepSessions (
  id $idType,
  startTime $textType,
  endTime $textType
)
''');

    await db.execute('''
CREATE TABLE SnoreEvents (
  id $idType,
  sessionId $integerType,
  timestamp $textType,
  confidence $realType,
  FOREIGN KEY (sessionId) REFERENCES SleepSessions (id)
)
''');

    await db.execute('''
CREATE TABLE SensorReadings (
  id $idType,
  sessionId $integerType,
  timestamp $textType,
  heartRate $integerType,
  spO2 $integerType,
  axisX $realType,
  axisY $realType,
  axisZ $realType,
  FOREIGN KEY (sessionId) REFERENCES SleepSessions (id)
)
''');
  }

  Future<int> createSession(DateTime startTime) async {
    final db = await instance.database;
    return await db.insert('SleepSessions', {
      'startTime': startTime.toIso8601String(),
      'endTime': startTime.toIso8601String(), // Will be updated later
    });
  }

  Future<void> endSession(int sessionId, DateTime endTime) async {
    final db = await instance.database;
    await db.update(
      'SleepSessions',
      {'endTime': endTime.toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> insertSnoreEvent(int sessionId, double confidence) async {
    final db = await instance.database;
    await db.insert('SnoreEvents', {
      'sessionId': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
      'confidence': confidence,
    });
  }

  Future<void> insertSensorReading(
    int sessionId,
    int hr,
    int spo2,
    double ax,
    double ay,
    double az,
  ) async {
    final db = await instance.database;
    await db.insert('SensorReadings', {
      'sessionId': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
      'heartRate': hr,
      'spO2': spo2,
      'axisX': ax,
      'axisY': ay,
      'axisZ': az,
    });
  }

  Future<List<Map<String, dynamic>>> getSessionData(int sessionId) async {
    final db = await instance.database;
    return await db.query(
      'SensorReadings',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<Map<String, dynamic>?> getLatestSession() async {
    final db = await instance.database;
    final result = await db.query(
      'SleepSessions',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }
}
