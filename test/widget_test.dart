import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:aprendizaje/data/aula_puntos_backup.dart';
import 'package:aprendizaje/data/aula_puntos_database.dart';
import 'package:aprendizaje/main.dart';

late AulaPuntosDatabase database;

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await AulaPuntosDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() => database.close());

  Future<void> settleDatabase(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(AulaPuntosApp(database: database));
    await settleDatabase(tester);
  }

  test(
    'group and attendance changes persist with a retry queue entry',
    () async {
      final group = (await database.groups()).first;
      final sessionId = await database.ensureSession(
        groupId: group['group_id']! as int,
        name: 'Sesion test',
        date: DateTime(2026, 11, 20),
      );
      final students = await database.studentsForSession(
        groupId: group['group_id']! as int,
        sessionId: sessionId,
      );
      final studentId = students.first['student_id']! as int;

      await database.updateAttendance(
        sessionId: sessionId,
        studentId: studentId,
        status: 'late',
      );
      await database.addParticipation(
        sessionId: sessionId,
        studentId: studentId,
        points: 2,
      );

      final updated = await database.studentsForSession(
        groupId: group['group_id']! as int,
        sessionId: sessionId,
      );
      expect(updated.first['attendance'], 'late');
      expect(updated.first['points'], 2);
      expect(await database.pendingChangesCount(), greaterThanOrEqualTo(3));
    },
  );

  test(
    'group records survive closing and reopening the SQLite database',
    () async {
      final filePath = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'aula-puntos-${DateTime.now().microsecondsSinceEpoch}.db',
      ).path;
      final persistentDb = await AulaPuntosDatabase.open(
        factory: databaseFactoryFfi,
        databasePath: filePath,
      );
      await persistentDb.saveGroup(
        name: 'Persistente',
        program: 'Desarrollo de Software',
        course: 'Flutter',
        period: '2026-II',
        sectionCode: 'PERSIST-01',
      );
      await persistentDb.close();

      final reopenedDb = await AulaPuntosDatabase.open(
        factory: databaseFactoryFfi,
        databasePath: filePath,
      );
      expect(
        (await reopenedDb.groups()).any(
          (group) => group['name'] == 'Persistente',
        ),
        isTrue,
      );
      expect(await reopenedDb.pendingChangesCount(), greaterThan(0));
      await reopenedDb.close();
      await File(filePath).delete();
    },
  );

  test('backup JSON round-trips roster records', () {
    final backup = AulaPuntosBackup(
      groupName: 'Grupo demo',
      groupProgram: 'Desarrollo de Software',
      course: 'Flutter',
      period: '2026-II',
      sectionCode: 'DA-2026-01',
      sessionName: 'Sesion demo',
      sessionDate: DateTime(2026, 11, 13),
      students: const [
        BackupStudent(
          name: 'Andrea Salazar',
          code: '20241052',
          attendance: 'present',
          points: 8,
        ),
      ],
    );

    final restored = AulaPuntosBackup.decode(backup.encode());

    expect(restored.groupName, 'Grupo demo');
    expect(restored.groupProgram, 'Desarrollo de Software');
    expect(restored.course, 'Flutter');
    expect(restored.period, '2026-II');
    expect(restored.sectionCode, 'DA-2026-01');
    expect(restored.sessionDate, DateTime(2026, 11, 13));
    expect(restored.students.single.code, '20241052');
    expect(restored.students.single.points, 8);
  });

  test('backup JSON rejects duplicate student codes and unknown status', () {
    final duplicateCodes = AulaPuntosBackup(
      groupName: 'Grupo demo',
      sessionName: 'Sesion demo',
      sessionDate: DateTime(2026, 11, 13),
      students: const [
        BackupStudent(
          name: 'Andrea',
          code: '20241052',
          attendance: 'present',
          points: 1,
        ),
        BackupStudent(
          name: 'Bruno',
          code: '20241052',
          attendance: 'absent',
          points: 0,
        ),
      ],
    );
    final unknownStatus = AulaPuntosBackup(
      groupName: 'Grupo demo',
      sessionName: 'Sesion demo',
      sessionDate: DateTime(2026, 11, 13),
      students: const [
        BackupStudent(
          name: 'Andrea',
          code: '20241052',
          attendance: 'unknown',
          points: 1,
        ),
      ],
    );

    expect(
      () => AulaPuntosBackup.decode(duplicateCodes.encode()),
      throwsFormatException,
    );
    expect(
      () => AulaPuntosBackup.decode(unknownStatus.encode()),
      throwsFormatException,
    );
  });

  testWidgets('instructor can open attendance and participation', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Buenos dias, Jorge 👋'), findsOneWidget);

    await tester.ensureVisible(find.text('Registrar asistencia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar asistencia'));
    await tester.pumpAndSettle();
    expect(find.text('Control de asistencia'), findsOneWidget);
    expect(find.text('Andrea Salazar'), findsOneWidget);
  });

  testWidgets('participation page awards a point', (tester) async {
    await pumpApp(tester);

    await tester.ensureVisible(find.text('Asignar participacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asignar participacion'));
    await tester.pumpAndSettle();
    expect(find.text('Puntuacion de participacion'), findsOneWidget);
    expect(find.text('8 puntos acumulados'), findsOneWidget);

    await tester.tap(find.byTooltip('Sumar un punto a Andrea Salazar'));
    await settleDatabase(tester);
    expect(find.text('9 puntos acumulados'), findsOneWidget);
  });

  testWidgets('reports filter students by name or institutional code', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.ensureVisible(find.text('Consultar reportes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar reportes'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('report-student-filter')),
      '20241052',
    );
    await tester.pumpAndSettle();

    expect(find.text('Andrea Salazar'), findsOneWidget);
    expect(find.text('Bruno Quispe'), findsNothing);
    expect(find.text('1 registros incluidos'), findsOneWidget);
  });

  testWidgets('offline mode is clearly shown by the app', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('En linea'));
    await tester.pumpAndSettle();

    expect(find.text('Sin conexion'), findsOneWidget);
    expect(find.textContaining('Modo sin conexion:'), findsOneWidget);
  });

  testWidgets('instructor can create, edit, and delete a group', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-group-button')));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo Grupo SENATI'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Grupo de prueba');
    await tester.enterText(fields.at(1), 'Desarrollo de Software');
    await tester.enterText(fields.at(2), 'Flutter');
    await tester.enterText(fields.at(3), '2026-II');
    await tester.enterText(fields.at(4), 'DA-2026-TEST');
    await tester.tap(find.text('Guardar'));
    await settleDatabase(tester);
    expect(find.text('Grupo de prueba'), findsOneWidget);
    expect(find.textContaining('DA-2026-TEST'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Editar Grupo de prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar Grupo de prueba'));
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(0), 'Grupo actualizado');
    await tester.tap(find.text('Guardar cambios'));
    await settleDatabase(tester);
    expect(find.text('Grupo actualizado'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Eliminar Grupo actualizado'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar Grupo actualizado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar').last);
    await settleDatabase(tester);
    expect(find.text('Grupo actualizado'), findsNothing);
  });

  testWidgets('selecting a group switches to that group roster', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fundamentos de Programacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fundamentos de Programacion'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(find.text('0 estudiantes'), findsOneWidget);
    expect(find.text('Andrea Salazar'), findsNothing);
  });
}
