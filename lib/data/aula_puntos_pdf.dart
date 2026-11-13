import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class AulaPuntosPdfStudent {
  const AulaPuntosPdfStudent({
    required this.name,
    required this.attendance,
    required this.points,
  });

  final String name;
  final String attendance;
  final int points;
}

Future<Uint8List> createAulaPuntosPdfReport({
  required String groupName,
  required String program,
  required String course,
  required String period,
  required String sectionCode,
  required String sessionName,
  required String sessionDate,
  required String generatedAt,
  required String criteria,
  required int studentCount,
  required int totalPoints,
  required Map<String, int> attendanceCounts,
  required List<AulaPuntosPdfStudent> students,
}) async {
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            'AULA PUNTOS - Reporte academico',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Text('Grupo: $groupName'),
        pw.Text('Programa academico: $program'),
        pw.Text('Asignatura / curso: $course'),
        pw.Text('Periodo: $period'),
        pw.Text('Codigo de seccion: $sectionCode'),
        pw.Text('Sesion: $sessionName'),
        pw.Text('Fecha de sesion: $sessionDate'),
        pw.Text('Generado: $generatedAt'),
        pw.Text('Criterios: $criteria'),
        pw.SizedBox(height: 12),
        pw.Text(
          'Resumen',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.TableHelper.fromTextArray(
          context: context,
          headers: const ['Indicador', 'Total'],
          data: [
            ['Estudiantes incluidos', '$studentCount'],
            ['Puntos acumulados', '$totalPoints'],
            for (final entry in attendanceCounts.entries)
              [entry.key, '${entry.value}'],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Detalle por estudiante',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.TableHelper.fromTextArray(
          context: context,
          headers: const ['Estudiante', 'Asistencia', 'Puntos'],
          data: [
            for (final student in students)
              [student.name, student.attendance, '${student.points}'],
          ],
        ),
      ],
    ),
  );
  return document.save();
}
