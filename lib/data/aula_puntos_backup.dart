import 'dart:convert';

class BackupStudent {
  const BackupStudent({
    required this.name,
    required this.code,
    required this.attendance,
    required this.points,
  });

  final String name;
  final String code;
  final String attendance;
  final int points;
}

class AulaPuntosBackup {
  const AulaPuntosBackup({
    required this.groupName,
    required this.sessionName,
    required this.sessionDate,
    required this.students,
    this.groupProgram = '',
    this.course = '',
    this.period = '',
    this.sectionCode = '',
  });

  static const format = 'aula-puntos-backup';
  static const version = 1;
  static const attendanceValues = {'present', 'late', 'absent', 'excused'};

  final String groupName;
  final String groupProgram;
  final String course;
  final String period;
  final String sectionCode;
  final String sessionName;
  final DateTime sessionDate;
  final List<BackupStudent> students;

  String encode() {
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'group': {
        'name': groupName,
        'program': groupProgram,
        'course': course,
        'period': period,
        'sectionCode': sectionCode,
      },
      'session': {'name': sessionName, 'date': _dateOnly(sessionDate)},
      'students': [
        for (final student in students)
          {
            'name': student.name,
            'code': student.code,
            'attendance': student.attendance,
            'points': student.points,
          },
      ],
    });
  }

  static AulaPuntosBackup decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('El archivo no contiene JSON valido.');
    }

    final root = _requireMap(decoded, 'raiz');
    if (root['format'] != format) {
      throw const FormatException(
        'El archivo no corresponde a un respaldo de Aula Puntos.',
      );
    }
    if (root['version'] != version) {
      throw const FormatException('La version del respaldo no es compatible.');
    }

    final group = _requireMap(root['group'], 'group');
    final session = _requireMap(root['session'], 'session');
    final groupName = _requireText(group['name'], 'group.name');
    final groupProgram = _optionalText(group['program'], 'group.program');
    final course = _optionalText(group['course'], 'group.course');
    final period = _optionalText(group['period'], 'group.period');
    final sectionCode = _optionalText(
      group['sectionCode'],
      'group.sectionCode',
    );
    final sessionName = _requireText(session['name'], 'session.name');
    final dateText = _requireText(session['date'], 'session.date');
    final sessionDate = DateTime.tryParse(dateText);
    if (sessionDate == null || _dateOnly(sessionDate) != dateText) {
      throw const FormatException(
        'session.date debe tener el formato AAAA-MM-DD.',
      );
    }

    final rawStudents = root['students'];
    if (rawStudents is! List) {
      throw const FormatException('students debe ser una lista.');
    }
    final students = <BackupStudent>[];
    final seenCodes = <String>{};
    for (var index = 0; index < rawStudents.length; index++) {
      final student = _requireMap(rawStudents[index], 'students[$index]');
      final name = _requireText(student['name'], 'students[$index].name');
      final code = _requireText(student['code'], 'students[$index].code');
      final attendance = _requireText(
        student['attendance'],
        'students[$index].attendance',
      );
      if (!attendanceValues.contains(attendance)) {
        throw FormatException(
          'Estado de asistencia no permitido para el estudiante $code.',
        );
      }
      final points = student['points'];
      if (points is! int || points < 0) {
        throw FormatException(
          'Los puntos de $code deben ser un entero no negativo.',
        );
      }
      if (!seenCodes.add(code.toLowerCase())) {
        throw FormatException('El codigo de estudiante $code esta duplicado.');
      }
      students.add(
        BackupStudent(
          name: name,
          code: code,
          attendance: attendance,
          points: points,
        ),
      );
    }

    return AulaPuntosBackup(
      groupName: groupName,
      groupProgram: groupProgram,
      course: course,
      period: period,
      sectionCode: sectionCode,
      sessionName: sessionName,
      sessionDate: sessionDate,
      students: List.unmodifiable(students),
    );
  }

  static Map<String, dynamic> _requireMap(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('$field debe ser un objeto JSON.');
  }

  static String _requireText(Object? value, String field) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw FormatException('$field es obligatorio.');
  }

  static String _optionalText(Object? value, String field) {
    if (value == null) return '';
    if (value is String) return value.trim();
    throw FormatException('$field debe ser texto.');
  }

  static String _dateOnly(DateTime value) {
    final date = value.toIso8601String();
    return date.substring(0, 10);
  }
}
