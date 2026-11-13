import 'package:flutter_test/flutter_test.dart';
import 'package:aprendizaje/data/aula_puntos_pdf.dart';

void main() {
  test(
    'creates a valid PDF report',
    () async {
      final bytes = await createAulaPuntosPdfReport(
        groupName: 'Grupo demo',
        program: 'Desarrollo de Software',
        course: 'Flutter',
        period: '2026-II',
        sectionCode: 'DA-2026-01',
        sessionName: 'Sesion demo',
        sessionDate: '13/11/2026',
        generatedAt: '2026-11-13T10:00:00',
        criteria: 'Estudiante: todos; fechas: todas',
        studentCount: 1,
        totalPoints: 8,
        attendanceCounts: const {'Presente': 1},
        students: const [
          AulaPuntosPdfStudent(
            name: 'Andrea Salazar',
            attendance: 'Presente',
            points: 8,
          ),
        ],
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(500));
    },
  );
}
