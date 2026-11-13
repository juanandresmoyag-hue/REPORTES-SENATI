import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AulaPuntosDatabase {
  AulaPuntosDatabase._(this._database);

  final Database _database;
  int _operationCounter = 0;

  static const _sampleStudents = [
    ('Andrea Salazar', '20241052', 'AS', 0, 8),
    ('Bruno Quispe', '20241067', 'BQ', 0, 5),
    ('Camila Rojas', '20241081', 'CR', 1, 12),
    ('Diego Huaman', '20241094', 'DH', 2, 3),
    ('Elena Paredes', '20241103', 'EP', 0, 10),
  ];

  static Future<AulaPuntosDatabase> open({
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final resolvedPath =
        databasePath ??
        path.join(await dbFactory.getDatabasesPath(), 'aula_puntos.db');
    final database = await dbFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onOpen: _seedIfEmpty,
      ),
    );
    return AulaPuntosDatabase._(database);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE groups (
        group_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        program TEXT NOT NULL,
        course TEXT NOT NULL,
        period TEXT NOT NULL,
        section_code TEXT NOT NULL COLLATE NOCASE UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE students (
        student_id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        initials TEXT NOT NULL,
        UNIQUE(group_id, code)
      )
    ''');
    await db.execute('''
      CREATE TABLE sessions (
        session_id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        session_date TEXT NOT NULL,
        UNIQUE(group_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE attendance (
        attendance_id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
        student_id INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
        status TEXT NOT NULL CHECK(status IN ('present', 'late', 'absent', 'excused')),
        updated_at TEXT NOT NULL,
        UNIQUE(session_id, student_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE attendance_audit (
        audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
        student_id INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
        old_status TEXT,
        new_status TEXT NOT NULL CHECK(new_status IN ('present', 'late', 'absent', 'excused')),
        changed_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE participation (
        participation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
        student_id INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
        points INTEGER NOT NULL CHECK(points != 0),
        operation_id TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        queue_id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending', 'synchronized', 'error')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_students_group ON students(group_id)');
    await db.execute(
      'CREATE INDEX idx_sessions_group_date ON sessions(group_id, session_date)',
    );
    await db.execute(
      'CREATE INDEX idx_sync_queue_status ON sync_queue(status, queue_id)',
    );
  }

  static Future<void> _seedIfEmpty(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM groups'),
    );
    if (count != 0) return;

    await db.transaction((txn) async {
      final mainGroupId = await txn.insert('groups', {
        'name': 'Desarrollo de Aplicaciones',
        'program': 'Desarrollo de Software',
        'course': 'Aplicaciones para Dispositivos Moviles',
        'period': '2026-II',
        'section_code': 'DA-2026-II',
      });
      final otherGroups = [
        {
          'name': 'Fundamentos de Programacion',
          'program': 'Desarrollo de Software',
          'course': 'Fundamentos de Programacion',
          'period': '2026-II',
          'section_code': 'FP-2026-II',
        },
        {
          'name': 'Diseno Web',
          'program': 'Diseno y Desarrollo Web',
          'course': 'Diseno Web',
          'period': '2026-II',
          'section_code': 'DW-2026-II',
        },
      ];
      for (final group in otherGroups) {
        await txn.insert('groups', group);
      }

      final sessionId = await txn.insert('sessions', {
        'group_id': mainGroupId,
        'name': 'Sesion 08 · 13 nov 2026',
        'session_date': '2026-11-13',
      });
      for (final student in _sampleStudents) {
        final studentId = await txn.insert('students', {
          'group_id': mainGroupId,
          'name': student.$1,
          'code': student.$2,
          'initials': student.$3,
        });
        final status = switch (student.$4) {
          1 => 'late',
          2 => 'absent',
          _ => 'present',
        };
        await txn.insert('attendance', {
          'session_id': sessionId,
          'student_id': studentId,
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        if (student.$5 > 0) {
          await txn.insert('participation', {
            'session_id': sessionId,
            'student_id': studentId,
            'points': student.$5,
            'operation_id': 'seed-$studentId',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }
    });
  }

  Future<List<Map<String, Object?>>> groups() async {
    return _database.query('groups', orderBy: 'name COLLATE NOCASE');
  }

  Future<int> saveGroup({
    int? id,
    required String name,
    required String program,
    required String course,
    required String period,
    required String sectionCode,
  }) async {
    final values = {
      'name': name.trim(),
      'program': program.trim(),
      'course': course.trim(),
      'period': period.trim(),
      'section_code': sectionCode.trim(),
    };
    final groupId = await _database.transaction((txn) async {
      final savedId = id ?? await txn.insert('groups', values);
      if (id != null) {
        await txn.update(
          'groups',
          values,
          where: 'group_id = ?',
          whereArgs: [id],
        );
      }
      await _enqueueInTransaction(txn, _nextOperationId(), 'group', {
        'entity_id': savedId,
        'action': id == null ? 'create' : 'update',
        ...values,
      });
      return savedId;
    });
    return groupId;
  }

  Future<void> deleteGroup(int id) async {
    await _database.transaction((txn) async {
      final group = await txn.query(
        'groups',
        where: 'group_id = ?',
        whereArgs: [id],
      );
      if (group.isEmpty) return;
      await txn.insert('sync_queue', {
        'operation_id': _nextOperationId(),
        'entity_type': 'group',
        'payload': jsonEncode({'action': 'delete', 'group_id': id}),
        'status': 'pending',
        'created_at': _now(),
        'updated_at': _now(),
      });
      await txn.delete('groups', where: 'group_id = ?', whereArgs: [id]);
    });
  }

  Future<int> ensureSession({
    required int groupId,
    required String name,
    required DateTime date,
  }) async {
    final existing = await _database.query(
      'sessions',
      columns: ['session_id'],
      where: 'group_id = ? AND name = ?',
      whereArgs: [groupId, name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.single['session_id']! as int;
    }
    return _database.transaction((txn) async {
      final sessionId = await txn.insert('sessions', {
        'group_id': groupId,
        'name': name,
        'session_date': _dateOnly(date),
      });
      await _enqueueInTransaction(txn, _nextOperationId(), 'session', {
        'session_id': sessionId,
        'group_id': groupId,
        'name': name,
        'session_date': _dateOnly(date),
      });
      return sessionId;
    });
  }

  Future<List<Map<String, Object?>>> studentsForSession({
    required int groupId,
    required int sessionId,
  }) async {
    return _database.rawQuery(
      '''
      SELECT s.student_id, s.name, s.code, s.initials,
        COALESCE(a.status, 'present') AS attendance,
        COALESCE(SUM(p.points), 0) AS points
      FROM students s
      LEFT JOIN attendance a
        ON a.student_id = s.student_id AND a.session_id = ?
      LEFT JOIN participation p
        ON p.student_id = s.student_id AND p.session_id = ?
      WHERE s.group_id = ?
      GROUP BY s.student_id
      ORDER BY s.name COLLATE NOCASE
      ''',
      [sessionId, sessionId, groupId],
    );
  }

  Future<void> updateAttendance({
    required int sessionId,
    required int studentId,
    required String status,
  }) async {
    final now = _now();
    final operationId = _nextOperationId();
    await _database.transaction((txn) async {
      final current = await txn.query(
        'attendance',
        columns: ['status'],
        where: 'session_id = ? AND student_id = ?',
        whereArgs: [sessionId, studentId],
        limit: 1,
      );
      final oldStatus = current.isEmpty ? null : current.single['status'];
      await txn.insert('attendance', {
        'session_id': sessionId,
        'student_id': studentId,
        'status': status,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (oldStatus != status) {
        await txn.insert('attendance_audit', {
          'session_id': sessionId,
          'student_id': studentId,
          'old_status': oldStatus,
          'new_status': status,
          'changed_at': now,
        });
      }
      await _enqueueInTransaction(txn, operationId, 'attendance', {
        'session_id': sessionId,
        'student_id': studentId,
        'old_status': oldStatus,
        'status': status,
      });
    });
  }

  Future<void> addParticipation({
    required int sessionId,
    required int studentId,
    required int points,
  }) async {
    if (points == 0) return;
    final now = _now();
    final operationId = _nextOperationId();
    await _database.transaction((txn) async {
      final totals = await txn.rawQuery(
        'SELECT COALESCE(SUM(points), 0) AS total FROM participation '
        'WHERE session_id = ? AND student_id = ?',
        [sessionId, studentId],
      );
      final total = totals.single['total']! as int;
      if (total + points < 0) {
        throw StateError('Los puntos del estudiante no pueden ser negativos.');
      }
      await txn.insert('participation', {
        'session_id': sessionId,
        'student_id': studentId,
        'points': points,
        'operation_id': operationId,
        'created_at': now,
      });
      await _enqueueInTransaction(txn, operationId, 'participation', {
        'session_id': sessionId,
        'student_id': studentId,
        'points': points,
      });
    });
  }

  Future<int> pendingChangesCount() async {
    return Sqflite.firstIntValue(
          await _database.rawQuery(
            "SELECT COUNT(*) FROM sync_queue WHERE status IN ('pending', 'error')",
          ),
        ) ??
        0;
  }

  Future<void> markPendingAsError() async {
    final now = _now();
    await _database.update('sync_queue', {
      'status': 'error',
      'updated_at': now,
    }, where: "status = 'pending'");
  }

  Future<int> importGroup({
    required String name,
    required String program,
    required String course,
    required String period,
    required String sectionCode,
    required String sessionName,
    required DateTime sessionDate,
    required List<Map<String, Object?>> students,
  }) async {
    final now = _now();
    return _database.transaction((txn) async {
      final existing = await txn.query(
        'groups',
        columns: ['group_id'],
        where: 'name = ?',
        whereArgs: [name.trim()],
        limit: 1,
      );
      final groupData = {
        'name': name.trim(),
        'program': program.trim().isEmpty
            ? 'Importado desde respaldo'
            : program.trim(),
        'course': course.trim().isEmpty ? name.trim() : course.trim(),
        'period': period.trim().isEmpty
            ? _dateOnly(sessionDate)
            : period.trim(),
        'section_code': sectionCode.trim().isEmpty
            ? 'IMPORTADO-${DateTime.now().microsecondsSinceEpoch}'
            : sectionCode.trim(),
      };
      final groupId = existing.isEmpty
          ? await txn.insert('groups', groupData)
          : existing.single['group_id']! as int;
      if (existing.isNotEmpty) {
        await txn.update(
          'groups',
          groupData,
          where: 'group_id = ?',
          whereArgs: [groupId],
        );
        await txn.delete(
          'students',
          where: 'group_id = ?',
          whereArgs: [groupId],
        );
      }

      final sessionId = await txn.insert('sessions', {
        'group_id': groupId,
        'name': sessionName,
        'session_date': _dateOnly(sessionDate),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final resolvedSession = await txn.query(
        'sessions',
        columns: ['session_id'],
        where: 'group_id = ? AND name = ?',
        whereArgs: [groupId, sessionName],
        limit: 1,
      );
      final actualSessionId = resolvedSession.isEmpty
          ? sessionId
          : resolvedSession.single['session_id']! as int;

      for (var index = 0; index < students.length; index++) {
        final student = students[index];
        final studentId = await txn.insert('students', {
          'group_id': groupId,
          'name': student['name'],
          'code': student['code'],
          'initials': student['initials'],
        });
        await txn.insert('attendance', {
          'session_id': actualSessionId,
          'student_id': studentId,
          'status': student['attendance'],
          'updated_at': now,
        });
        final points = student['points']! as int;
        if (points > 0) {
          await txn.insert('participation', {
            'session_id': actualSessionId,
            'student_id': studentId,
            'points': points,
            'operation_id': 'import-$actualSessionId-$studentId',
            'created_at': now,
          });
        }
      }
      final operationId = _nextOperationId();
      await _enqueueInTransaction(txn, operationId, 'group_import', {
        'group_id': groupId,
        'session_id': actualSessionId,
        'student_count': students.length,
      });
      return groupId;
    });
  }

  Future<void> _enqueueInTransaction(
    Transaction txn,
    String operationId,
    String entityType,
    Map<String, Object?> payload,
  ) async {
    final now = _now();
    await txn.insert('sync_queue', {
      'operation_id': operationId,
      'entity_type': entityType,
      'payload': jsonEncode(payload),
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
  }

  String _nextOperationId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${_operationCounter++}';

  String _now() => DateTime.now().toUtc().toIso8601String();

  String _dateOnly(DateTime value) => value.toIso8601String().substring(0, 10);

  Future<void> close() => _database.close();
}
