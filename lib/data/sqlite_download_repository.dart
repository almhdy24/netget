import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../core/constants.dart';
import '../core/segment_planner.dart';
import '../core/utils.dart';
import '../models/download_status.dart';
import '../models/download_task.dart';
import 'download_repository.dart';

/// SQLite-backed task repository.
///
/// Implements atomic row mutations for tasks and segments, replacing the
/// O(N) full-list JSON rewrite with transactions. Migrates existing
/// `netget_tasks.json` on first run with `.bak` safety.
class SqliteDownloadRepository implements DownloadRepository {
  final Database? _preopenedDb;
  final String? _customDbPath;
  final File? _jsonMigrationSource;
  Database? _db;

  SqliteDownloadRepository({
    Database? database,
    String? customDbPath,
    File? jsonMigrationSource,
  }) : _preopenedDb = database,
       _customDbPath = customDbPath,
       _jsonMigrationSource = jsonMigrationSource;

  Future<Database> get database async {
    if (_preopenedDb != null) return _preopenedDb;
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (_customDbPath != null) {
      path = _customDbPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      path = p.join(docsDir.path, 'netget_tasks.db');
    }

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
        await _migrateFromJsonIfExists(db);
      },
      onOpen: (db) async {
        // Run migration if tables exist but json migration has not yet run
        await _migrateFromJsonIfExists(db);
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        file_name TEXT NOT NULL,
        save_path TEXT NOT NULL,
        total_bytes INTEGER NOT NULL,
        downloaded_bytes INTEGER NOT NULL,
        status TEXT NOT NULL,
        resumable INTEGER NOT NULL,
        speed_bps REAL NOT NULL DEFAULT 0.0,
        error_message TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        category TEXT NOT NULL,
        connection_count INTEGER NOT NULL,
        etag TEXT,
        last_modified TEXT,
        referrer TEXT,
        queue_name TEXT NOT NULL,
        elapsed_seconds INTEGER NOT NULL DEFAULT 0,
        rev INTEGER NOT NULL DEFAULT 0,
        checksum_expected TEXT,
        checksum_actual TEXT,
        checksum_algorithm TEXT,
        pause_reason TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS segments (
        task_id TEXT NOT NULL,
        index_num INTEGER NOT NULL,
        start_byte INTEGER NOT NULL,
        end_byte INTEGER NOT NULL,
        downloaded_bytes INTEGER NOT NULL,
        is_completed INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (task_id, index_num),
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS queues (
        name TEXT PRIMARY KEY,
        is_active INTEGER NOT NULL DEFAULT 1,
        speed_limit_bps INTEGER NOT NULL DEFAULT 0,
        allowed_networks TEXT NOT NULL DEFAULT 'any',
        schedule_start TEXT,
        schedule_stop TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS schedules (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        queue_name TEXT,
        trigger_time TEXT NOT NULL,
        window_start TEXT,
        window_end TEXT,
        repeat_days TEXT,
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS usage_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        task_id TEXT NOT NULL,
        bytes INTEGER NOT NULL,
        network_type TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateFromJsonIfExists(Database db) async {
    File? jsonFile = _jsonMigrationSource;
    if (jsonFile == null) {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        jsonFile = File(p.join(docsDir.path, 'netget_tasks.json'));
      } catch (_) {
        return;
      }
    }

    if (!await jsonFile.exists()) return;

    try {
      final raw = await jsonFile.readAsString();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          // Backup copy before touching anything
          final bakFile = File('${jsonFile.path}.bak');
          await jsonFile.copy(bakFile.path);

          await db.transaction((txn) async {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                try {
                  final task = DownloadTask.fromJson(item);
                  await _insertTask(txn, task);
                } catch (e) {
                  debugPrint('Migration error for task item: $e');
                }
              }
            }
          });

          // Mark migrated
          final migratedFile = File('${jsonFile.path}.migrated');
          await NetGetUtils.safeRenameFile(jsonFile, migratedFile);
        }
      }
    } catch (e, st) {
      debugPrint('JSON to SQLite migration failed safely: $e\n$st');
    }
  }

  static Future<void> _insertTask(
    DatabaseExecutor db,
    DownloadTask task,
  ) async {
    await db.insert('tasks', {
      'id': task.id,
      'url': task.url,
      'file_name': task.fileName,
      'save_path': task.savePath,
      'total_bytes': task.totalBytes,
      'downloaded_bytes': task.downloadedBytes,
      'status': task.status.name,
      'resumable': task.resumable ? 1 : 0,
      'speed_bps': task.speedBytesPerSec,
      'error_message': task.errorMessage,
      'created_at': task.createdAt.toIso8601String(),
      'completed_at': task.completedAt?.toIso8601String(),
      'category': task.category.name,
      'connection_count': task.connectionCount,
      'etag': task.etag,
      'last_modified': task.lastModified,
      'referrer': task.referrer,
      'queue_name': task.queueName,
      'elapsed_seconds': task.elapsedSeconds,
      'rev': task.rev,
      'checksum_expected': task.checksumExpected,
      'checksum_actual': task.checksumActual,
      'checksum_algorithm': task.checksumAlgorithm,
      'pause_reason': task.pauseReason,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (task.segments.isNotEmpty) {
      final now = DateTime.now().toIso8601String();
      for (final s in task.segments) {
        await db.insert('segments', {
          'task_id': task.id,
          'index_num': s.index,
          'start_byte': s.startByte,
          'end_byte': s.endByte,
          'downloaded_bytes': s.downloadedBytes,
          'is_completed': s.isCompleted ? 1 : 0,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  @override
  Future<List<DownloadTask>> loadTasks() async {
    final db = await database;

    final taskRows = await db.query('tasks', orderBy: 'created_at DESC');
    final segmentRows = await db.query('segments', orderBy: 'index_num ASC');

    final segmentsByTaskId = <String, List<DownloadSegment>>{};
    for (final row in segmentRows) {
      final taskId = row['task_id'] as String;
      final seg = DownloadSegment(
        index: row['index_num'] as int,
        startByte: row['start_byte'] as int,
        endByte: row['end_byte'] as int,
        downloadedBytes: row['downloaded_bytes'] as int,
        isCompleted: (row['is_completed'] as int) == 1,
      );
      segmentsByTaskId.putIfAbsent(taskId, () => []).add(seg);
    }

    final tasks = <DownloadTask>[];
    for (final row in taskRows) {
      final id = row['id'] as String;
      final fileName = row['file_name'] as String;
      var status = DownloadStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => DownloadStatus.queued,
      );

      // Sanitize interrupted tasks on restart
      if (status == DownloadStatus.downloading ||
          status == DownloadStatus.queued) {
        status = DownloadStatus.paused;
      }

      final task = DownloadTask(
        id: id,
        url: row['url'] as String,
        fileName: fileName,
        savePath: row['save_path'] as String,
        totalBytes: row['total_bytes'] as int,
        downloadedBytes: row['downloaded_bytes'] as int,
        status: status,
        resumable: (row['resumable'] as int) == 1,
        speedBytesPerSec: 0.0,
        errorMessage: row['error_message'] as String?,
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.now(),
        completedAt: row['completed_at'] != null
            ? DateTime.tryParse(row['completed_at'] as String)
            : null,
        category: DownloadCategory.values.firstWhere(
          (c) => c.name == row['category'],
          orElse: () => NetGetUtils.classifyCategory(fileName),
        ),
        connectionCount: row['connection_count'] as int,
        etag: row['etag'] as String?,
        lastModified: row['last_modified'] as String?,
        referrer: row['referrer'] as String?,
        queueName: row['queue_name'] as String,
        elapsedSeconds: row['elapsed_seconds'] as int? ?? 0,
        rev: row['rev'] as int? ?? 0,
        checksumExpected: row['checksum_expected'] as String?,
        checksumActual: row['checksum_actual'] as String?,
        checksumAlgorithm: row['checksum_algorithm'] as String?,
        pauseReason: row['pause_reason'] as String?,
        segments: segmentsByTaskId[id] ?? const [],
      );
      tasks.add(task);
    }

    return tasks;
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    final db = await database;
    await db.transaction((txn) async {
      await _insertTask(txn, task);
    });
  }

  @override
  Future<void> saveTasks(List<DownloadTask> tasks) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final task in tasks) {
        await _insertTask(txn, task);
      }
    });
  }

  @override
  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('segments', where: 'task_id = ?', whereArgs: [id]);
      await txn.delete('tasks', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
