import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:aprendizaje/data/aula_puntos_backup.dart';
import 'package:aprendizaje/data/aula_puntos_database.dart';
import 'package:aprendizaje/data/aula_puntos_pdf.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startApplication();
}

Future<void> _startApplication() async {
  try {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final database = await AulaPuntosDatabase.open();
    runApp(AulaPuntosApp(database: database));
  } on Object catch (error) {
    runApp(_StartupErrorApp(error: error, retry: _startApplication));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.retry});

  final Object error;
  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aula Puntos',
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.storage_rounded,
                      color: Color(0xFF3767D5),
                      size: 36,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudo iniciar Aula Puntos',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No se pudo abrir la base de datos local. '
                      'Revisa la consola y los archivos requeridos para esta plataforma.',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      error.toString(),
                      style: const TextStyle(
                        color: Color(0xFFCC4D4D),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => retry(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum AttendanceStatus { present, late, absent, excused }

enum SyncState { synchronized, pending, error }

extension AttendanceStatusLabel on AttendanceStatus {
  String get label => switch (this) {
    AttendanceStatus.present => 'Presente',
    AttendanceStatus.late => 'Tardanza',
    AttendanceStatus.absent => 'Falta',
    AttendanceStatus.excused => 'Justificado',
  };

  Color get color => switch (this) {
    AttendanceStatus.present => const Color(0xFF16845B),
    AttendanceStatus.late => const Color(0xFFB76A12),
    AttendanceStatus.absent => const Color(0xFFCC4D4D),
    AttendanceStatus.excused => const Color(0xFF5972B5),
  };
}

class StudentRecord {
  StudentRecord({
    required this.id,
    required this.name,
    required this.code,
    required this.initials,
    required this.color,
    this.attendance = AttendanceStatus.present,
    this.points = 0,
  });

  int id;
  final String name;
  final String code;
  final String initials;
  final Color color;
  AttendanceStatus attendance;
  int points;
}

class _ReportExportData {
  const _ReportExportData({
    required this.students,
    required this.attendanceCounts,
    required this.totalPoints,
  });

  final List<StudentRecord> students;
  final Map<AttendanceStatus, int> attendanceCounts;
  final int totalPoints;
}

class InstructorGroup {
  InstructorGroup({
    this.id,
    required this.name,
    required this.program,
    required this.course,
    required this.period,
    required this.sectionCode,
    List<StudentRecord>? students,
  }) : students = students ?? [];

  int? id;
  String name;
  String program;
  String course;
  String period;
  String sectionCode;
  final List<StudentRecord> students;
}

class AulaPuntosApp extends StatelessWidget {
  const AulaPuntosApp({super.key, required this.database});

  final AulaPuntosDatabase database;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF172B4D);
    return MaterialApp(
      title: 'Aula Puntos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3767D5),
          surface: const Color(0xFFF6F8FC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8FC),
          foregroundColor: navy,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE9EDF4)),
          ),
        ),
      ),
      home: InstructorHome(database: database),
    );
  }
}

class InstructorHome extends StatefulWidget {
  const InstructorHome({super.key, required this.database});

  final AulaPuntosDatabase database;

  @override
  State<InstructorHome> createState() => _InstructorHomeState();
}

class _InstructorHomeState extends State<InstructorHome> {
  int _selectedPage = 0;
  String _selectedGroup = 'Desarrollo de Aplicaciones';
  String _selectedSession = 'Sesion 08 · 13 nov 2026';
  DateTime _sessionDate = DateTime(2026, 11, 13);
  int? _activeSessionId;
  DateTimeRange? _reportDateRange;
  String _reportStudentQuery = '';
  bool _isOnline = true;
  bool _isLoading = true;
  int _pendingChanges = 0;
  SyncState _syncState = SyncState.synchronized;
  List<StudentRecord> _students = [];
  final List<InstructorGroup> _groups = [];

  InstructorGroup get _activeGroup =>
      _groups.firstWhere((group) => group.name == _selectedGroup);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final records = await widget.database.groups();
      _groups
        ..clear()
        ..addAll(records.map(_groupFromRow));
      if (_groups.isEmpty || !mounted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final selected = _groups.firstWhere(
        (group) => group.name == _selectedGroup,
        orElse: () => _groups.first,
      );
      _selectedGroup = selected.name;
      await _loadGroupContext(selected);
      final pending = await widget.database.pendingChangesCount();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _pendingChanges = pending;
          _syncState = pending == 0
              ? SyncState.synchronized
              : SyncState.pending;
        });
      }
    } on DatabaseException catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        _notify('No se pudieron cargar los datos locales: $error');
      }
    }
  }

  InstructorGroup _groupFromRow(Map<String, Object?> row) => InstructorGroup(
    id: row['group_id']! as int,
    name: row['name']! as String,
    program: row['program']! as String,
    course: row['course']! as String,
    period: row['period']! as String,
    sectionCode: row['section_code']! as String,
  );

  StudentRecord _studentFromRow(Map<String, Object?> row, int index) {
    const colors = [
      Color(0xFFF4E4D9),
      Color(0xFFE0E9FA),
      Color(0xFFE4EFE4),
      Color(0xFFF1E6F5),
      Color(0xFFF7EBCF),
    ];
    return StudentRecord(
      id: row['student_id']! as int,
      name: row['name']! as String,
      code: row['code']! as String,
      initials: row['initials']! as String,
      color: colors[index % colors.length],
      attendance: AttendanceStatus.values.byName(row['attendance']! as String),
      points: row['points']! as int,
    );
  }

  static const _pages = [
    'Panel principal',
    'Asistencia',
    'Participacion',
    'Reportes',
    'Grupos',
  ];

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshPendingCount() async {
    final pending = await widget.database.pendingChangesCount();
    if (!mounted) return;
    setState(() {
      _pendingChanges = pending;
      _syncState = pending == 0 ? SyncState.synchronized : SyncState.pending;
    });
  }

  Future<void> _loadGroupContext(InstructorGroup group) async {
    if (group.id == null) return;
    final sessionId = await widget.database.ensureSession(
      groupId: group.id!,
      name: _selectedSession,
      date: _sessionDate,
    );
    final rows = await widget.database.studentsForSession(
      groupId: group.id!,
      sessionId: sessionId,
    );
    if (!mounted) return;
    setState(() {
      _activeSessionId = sessionId;
      group.students
        ..clear()
        ..addAll([
          for (var index = 0; index < rows.length; index++)
            _studentFromRow(rows[index], index),
        ]);
      _students = group.students;
    });
  }

  void _toggleConnection() {
    setState(() => _isOnline = !_isOnline);
    _notify(_isOnline ? 'Conexion disponible.' : 'Modo sin conexion activado.');
  }

  void _retrySync() {
    if (!_isOnline) {
      _notify('Conectate a internet antes de reintentar.');
      return;
    }
    widget.database
        .markPendingAsError()
        .then((_) async {
          await _refreshPendingCount();
          if (mounted) {
            setState(() => _syncState = SyncState.error);
            _notify(
              'No hay un backend conectado. Los cambios locales se conservan; '
              'no se marco ninguno como sincronizado.',
            );
          }
        })
        .onError((Object error, StackTrace stackTrace) {
          if (mounted) _notify('No se pudo actualizar la cola local: $error');
        });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _buildSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(wide),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 36 : 20,
                        12,
                        wide ? 36 : 20,
                        28,
                      ),
                      child: _buildSelectedPage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide ? null : _buildBottomNavigation(),
      floatingActionButton: _selectedPage == 4
          ? FloatingActionButton(
              key: const ValueKey('create-group-button'),
              tooltip: 'Nuevo grupo',
              onPressed: _createGroup,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 248,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 28, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brand(),
          const SizedBox(height: 40),
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 12),
            child: Text(
              'MENU PRINCIPAL',
              style: TextStyle(
                color: Color(0xFF8994A8),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          for (var index = 0; index < _pages.length; index++)
            _navItem(index, expanded: true),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FD),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  _isOnline ? Icons.cloud_done_outlined : Icons.cloud_off,
                  color: _isOnline
                      ? const Color(0xFF16845B)
                      : const Color(0xFFB76A12),
                  size: 19,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _syncDescription,
                    style: const TextStyle(fontSize: 11, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF3767D5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 11),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AULA PUNTOS',
              style: TextStyle(
                color: Color(0xFF172B4D),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            Text(
              'SENATI · Instructor',
              style: TextStyle(color: Color(0xFF8490A4), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(bool wide) {
    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 36 : 20, 18, wide ? 36 : 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F8FC),
        border: Border(bottom: BorderSide(color: Color(0xFFE9EDF4))),
      ),
      child: Row(
        children: [
          if (!wide) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF3767D5),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'AULA PUNTOS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
                fontSize: 13,
              ),
            ),
          ] else
            Text(
              _pages[_selectedPage],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          const Spacer(),
          Tooltip(
            message: 'Cambiar estado de conexion (demostracion)',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _toggleConnection,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _isOnline
                      ? const Color(0xFFE8F5EE)
                      : const Color(0xFFFFF4D9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isOnline ? Icons.wifi : Icons.wifi_off,
                      color: _isOnline
                          ? const Color(0xFF16845B)
                          : const Color(0xFFB76A12),
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isOnline ? 'En linea' : 'Sin conexion',
                      style: TextStyle(
                        color: _isOnline
                            ? const Color(0xFF16845B)
                            : const Color(0xFFB76A12),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFE0E9FA),
            child: const Text(
              'JL',
              style: TextStyle(
                color: Color(0xFF3767D5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 9),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jorge Luque',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Instructor',
                  style: TextStyle(fontSize: 10, color: Color(0xFF8490A4)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    const icons = [
      Icons.grid_view_rounded,
      Icons.fact_check_outlined,
      Icons.stars_rounded,
      Icons.bar_chart_rounded,
      Icons.groups_2_outlined,
    ];
    return NavigationBar(
      selectedIndex: _selectedPage,
      onDestinationSelected: (index) => setState(() => _selectedPage = index),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      destinations: List.generate(
        _pages.length,
        (index) => NavigationDestination(
          icon: Icon(icons[index]),
          label: _pages[index],
        ),
      ),
    );
  }

  Widget _navItem(int index, {required bool expanded}) {
    const icons = [
      Icons.grid_view_rounded,
      Icons.fact_check_outlined,
      Icons.stars_rounded,
      Icons.bar_chart_rounded,
      Icons.groups_2_outlined,
    ];
    final selected = _selectedPage == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedPage = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF3FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icons[index],
                size: 19,
                color: selected
                    ? const Color(0xFF3767D5)
                    : const Color(0xFF8490A4),
              ),
              if (expanded) ...[
                const SizedBox(width: 12),
                Text(
                  _pages[index],
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF3767D5)
                        : const Color(0xFF536176),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPage() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final page = switch (_selectedPage) {
      0 => _dashboard(),
      1 => _attendancePage(),
      2 => _participationPage(),
      3 => _reportsPage(),
      _ => _groupsPage(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isOnline || _syncState != SyncState.synchronized) ...[
          _syncBanner(),
          const SizedBox(height: 14),
        ],
        page,
      ],
    );
  }

  String get _syncDescription {
    if (!_isOnline) return 'Sin conexion\n$_pendingChanges cambios pendientes';
    return switch (_syncState) {
      SyncState.synchronized => 'En linea\nDatos sincronizados',
      SyncState.pending => 'Pendiente\n$_pendingChanges cambios por enviar',
      SyncState.error =>
        'Error de sincronizacion\n$_pendingChanges cambios pendientes',
    };
  }

  Widget _syncBanner() {
    final hasError = _syncState == SyncState.error;
    final color = hasError ? const Color(0xFFCC4D4D) : const Color(0xFFB76A12);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            Icon(
              hasError ? Icons.sync_problem : Icons.cloud_upload_outlined,
              color: color,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isOnline
                    ? '$_pendingChanges cambios pendientes. La sincronizacion requiere conectar el backend.'
                    : 'Modo sin conexion: $_pendingChanges cambios pendientes guardados localmente.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            if (_isOnline)
              TextButton(
                onPressed: _retrySync,
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pageIntro(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF7C879A), fontSize: 13),
        ),
      ],
    );
  }

  Widget _selectionBar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 22,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _selector(
              icon: Icons.groups_2_outlined,
              label: 'GRUPO',
              value: _selectedGroup,
              options: _groups.map((group) => group.name).toList(),
              onChanged: _selectGroup,
            ),
            _selector(
              icon: Icons.event_outlined,
              label: 'SESION',
              value: _selectedSession,
              options: {
                _selectedSession,
                'Sesion 08 · 13 nov 2026',
                'Sesion 07 · 06 nov 2026',
                'Sesion 06 · 30 oct 2026',
              }.toList(),
              onChanged: _setSelectedSession,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectGroup(String name) async {
    final selected = _groups.firstWhere((group) => group.name == name);
    setState(() {
      _selectedGroup = name;
      _students = [];
    });
    try {
      await _loadGroupContext(selected);
      await _refreshPendingCount();
    } on DatabaseException catch (error) {
      if (mounted) _notify('No se pudieron cargar los estudiantes: $error');
    }
  }

  Future<void> _updateAttendance(
    StudentRecord student,
    AttendanceStatus status,
  ) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      _notify('No hay una sesion activa para guardar la asistencia.');
      return;
    }
    try {
      await widget.database.updateAttendance(
        sessionId: sessionId,
        studentId: student.id,
        status: status.name,
      );
      if (!mounted) return;
      setState(() => student.attendance = status);
      await _refreshPendingCount();
    } on DatabaseException catch (error) {
      _notify('No se pudo guardar la asistencia: $error');
    }
  }

  Future<void> _adjustParticipation(StudentRecord student, int amount) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      _notify('No hay una sesion activa para guardar los puntos.');
      return;
    }
    try {
      await widget.database.addParticipation(
        sessionId: sessionId,
        studentId: student.id,
        points: amount,
      );
      if (!mounted) return;
      setState(() => student.points += amount);
      await _refreshPendingCount();
    } on DatabaseException catch (error) {
      _notify('No se pudieron guardar los puntos: $error');
    } on StateError catch (error) {
      _notify(error.message);
    }
  }

  Future<void> _setSelectedSession(String value) async {
    setState(() {
      _selectedSession = value;
      _sessionDate = switch (value) {
        'Sesion 07 · 06 nov 2026' => DateTime(2026, 11, 6),
        'Sesion 06 · 30 oct 2026' => DateTime(2026, 10, 30),
        _ => DateTime(2026, 11, 13),
      };
    });
    try {
      await _loadGroupContext(_activeGroup);
      await _refreshPendingCount();
    } on DatabaseException catch (error) {
      if (mounted) _notify('No se pudo abrir la sesion: $error');
    }
  }

  Widget _selector({
    required IconData icon,
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: const Color(0xFF66748A)),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8994A8),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
            DropdownButton<String>(
              value: value,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: const TextStyle(
                color: Color(0xFF172B4D),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              items: options
                  .map(
                    (option) =>
                        DropdownMenuItem(value: option, child: Text(option)),
                  )
                  .toList(),
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _dashboard() {
    final present = _students
        .where((student) => student.attendance == AttendanceStatus.present)
        .length;
    final totalPoints = _students.fold<int>(
      0,
      (total, student) => total + student.points,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageIntro(
          'Buenos dias, Jorge 👋',
          'Aqui tienes el resumen de tu actividad academica.',
        ),
        const SizedBox(height: 20),
        _selectionBar(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 900
                ? 4
                : constraints.maxWidth > 560
                ? 2
                : 1;
            return _responsiveGrid(
              columns: columns,
              children: [
                _statCard(
                  'Estudiantes',
                  '${_students.length}',
                  'En el grupo seleccionado',
                  Icons.groups_2_outlined,
                  const Color(0xFF3767D5),
                ),
                _statCard(
                  'Asistencia',
                  _students.isEmpty
                      ? '0%'
                      : '${((present / _students.length) * 100).round()}%',
                  '$present presentes hoy',
                  Icons.fact_check_outlined,
                  const Color(0xFF16845B),
                ),
                _statCard(
                  'Participaciones',
                  '$totalPoints pts',
                  'Puntos acumulados hoy',
                  Icons.stars_rounded,
                  const Color(0xFFDA951E),
                ),
                _statCard(
                  'Sesiones',
                  '08',
                  'Periodo academico actual',
                  Icons.calendar_month_outlined,
                  const Color(0xFF8259B5),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 740;
            final quickActions = _quickActions();
            final sessionCard = _sessionCard();
            if (stacked) {
              return Column(
                children: [
                  sessionCard,
                  const SizedBox(height: 16),
                  quickActions,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: sessionCard),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: quickActions),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _studentSummary(),
      ],
    );
  }

  Widget _responsiveGrid({
    required int columns,
    required List<Widget> children,
  }) {
    return GridView.count(
      crossAxisCount: columns,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: columns == 1
          ? 2.5
          : columns == 2
          ? 1.7
          : 1.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _statCard(
    String title,
    String value,
    String detail,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                const Icon(Icons.more_horiz, color: Color(0xFF9AA4B3)),
              ],
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF8994A8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sesion de hoy',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                _tag(
                  'EN CURSO',
                  const Color(0xFFE8F5EE),
                  const Color(0xFF16845B),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _selectedGroup,
              style: const TextStyle(color: Color(0xFF8994A8), fontSize: 11),
            ),
            const SizedBox(height: 16),
            _sessionDetail(
              Icons.menu_book_outlined,
              'Tema',
              'Interfaces adaptables con Flutter',
            ),
            const SizedBox(height: 11),
            _sessionDetail(
              Icons.calendar_today_outlined,
              'Fecha',
              'Viernes, 13 de noviembre · 08:00',
            ),
            const SizedBox(height: 11),
            _sessionDetail(
              Icons.people_outline,
              'Asistencia',
              '${_students.length} estudiantes registrados',
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _selectedPage = 1),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('Ir al control de asistencia'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionDetail(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF8490A4)),
        const SizedBox(width: 9),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Color(0xFF8490A4)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _quickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Accesos rapidos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            _actionButton(
              icon: Icons.fact_check_outlined,
              title: 'Registrar asistencia',
              subtitle: 'Marca el estado por estudiante',
              onTap: () => setState(() => _selectedPage = 1),
            ),
            const SizedBox(height: 9),
            _actionButton(
              icon: Icons.stars_rounded,
              title: 'Asignar participacion',
              subtitle: 'Reconoce aportes en clase',
              onTap: () => setState(() => _selectedPage = 2),
            ),
            const SizedBox(height: 9),
            _actionButton(
              icon: Icons.insert_chart_outlined,
              title: 'Consultar reportes',
              subtitle: 'Revisa el avance del grupo',
              onTap: () => setState(() => _selectedPage = 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF3FF),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: const Color(0xFF3767D5), size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF8994A8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8994A8)),
          ],
        ),
      ),
    );
  }

  Widget _studentSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Resumen de estudiantes',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedPage = 1),
                  child: const Text('Ver asistencia'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final student in _students.take(3)) ...[
              _studentRow(student, compact: true),
              if (student != _students.take(3).last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attendancePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageIntro(
          'Control de asistencia',
          'Registra y actualiza la asistencia de cada estudiante.',
        ),
        const SizedBox(height: 18),
        _selectionBar(),
        const SizedBox(height: 14),
        _attendanceSummary(),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Lista de estudiantes',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${_students.length} estudiantes',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8994A8),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                for (var index = 0; index < _students.length; index++) ...[
                  _studentRow(_students[index]),
                  if (index < _students.length - 1) const Divider(height: 20),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFF8994A8)),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Los cambios de asistencia se guardan en esta sesion.',
                style: TextStyle(fontSize: 10, color: Color(0xFF8994A8)),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                _refreshPendingCount();
                _notify('Asistencia de la sesion guardada localmente.');
              },
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _attendanceSummary() {
    final counts = {
      AttendanceStatus.present: 0,
      AttendanceStatus.late: 0,
      AttendanceStatus.absent: 0,
      AttendanceStatus.excused: 0,
    };
    for (final student in _students) {
      counts[student.attendance] = counts[student.attendance]! + 1;
    }
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final status in AttendanceStatus.values)
          _tag(
            '${status.label} ${counts[status]}',
            status.color.withValues(alpha: .1),
            status.color,
          ),
      ],
    );
  }

  Widget _studentRow(StudentRecord student, {bool compact = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 9 : 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: student.color,
            child: Text(
              student.initials,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF536176),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  student.code,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF8994A8),
                  ),
                ),
              ],
            ),
          ),
          if (compact) ...[
            _tag(
              student.attendance.label,
              student.attendance.color.withValues(alpha: .1),
              student.attendance.color,
            ),
            const SizedBox(width: 14),
            Text(
              '${student.points} pts',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ] else
            DropdownButton<AttendanceStatus>(
              value: student.attendance,
              underline: const SizedBox.shrink(),
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              items: AttendanceStatus.values
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: _tag(
                        status.label,
                        status.color.withValues(alpha: .1),
                        status.color,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (status) {
                if (status != null) _updateAttendance(student, status);
              },
            ),
        ],
      ),
    );
  }

  Widget _participationPage() {
    final totalPoints = _students.fold<int>(
      0,
      (total, student) => total + student.points,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageIntro(
          'Puntuacion de participacion',
          'Reconoce las contribuciones de tus estudiantes.',
        ),
        const SizedBox(height: 18),
        _selectionBar(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: Color(0xFFDA951E)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Actividad',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8994A8),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Participacion en clase',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                _tag(
                  '+1 punto por aporte',
                  const Color(0xFFFFF4D9),
                  const Color(0xFFB76A12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Estudiantes',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '$totalPoints pts en total',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8994A8),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                for (var index = 0; index < _students.length; index++) ...[
                  _participationRow(_students[index]),
                  if (index < _students.length - 1) const Divider(height: 20),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _participationRow(StudentRecord student) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: student.color,
            child: Text(
              student.initials,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${student.points} puntos acumulados',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF8994A8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restar un punto a ${student.name}',
            onPressed: student.points == 0
                ? null
                : () => _adjustParticipation(student, -1),
            icon: const Icon(Icons.remove_circle_outline),
            color: const Color(0xFF8994A8),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${student.points}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Sumar un punto a ${student.name}',
            onPressed: () => _adjustParticipation(student, 1),
            icon: const Icon(Icons.add, size: 19),
          ),
        ],
      ),
    );
  }

  List<StudentRecord> get _filteredReportStudents {
    final query = _reportStudentQuery.trim().toLowerCase();
    final range = _reportDateRange;
    final dateMatches =
        range == null ||
        (!_sessionDate.isBefore(range.start) &&
            !_sessionDate.isAfter(
              DateTime(
                range.end.year,
                range.end.month,
                range.end.day,
                23,
                59,
                59,
              ),
            ));
    if (!dateMatches) return const [];
    if (query.isEmpty) return List.unmodifiable(_students);
    return List.unmodifiable(
      _students
          .where(
            (student) =>
                student.name.toLowerCase().contains(query) ||
                student.code.toLowerCase().contains(query),
          )
          .toList(),
    );
  }

  Widget _reportFilters() {
    final range = _reportDateRange;
    final dateLabel = range == null
        ? 'Rango de fechas'
        : '${_dateLabel(range.start)} – ${_dateLabel(range.end)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                key: const ValueKey('report-student-filter'),
                decoration: const InputDecoration(
                  labelText: 'Estudiante',
                  hintText: 'Nombre o codigo',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) =>
                    setState(() => _reportStudentQuery = value),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickReportDateRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(dateLabel),
            ),
            if (range != null)
              TextButton(
                onPressed: () => setState(() => _reportDateRange = null),
                child: const Text('Limpiar fechas'),
              ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _pickReportDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _reportDateRange,
      helpText: 'Filtrar sesiones por fecha',
    );
    if (range != null && mounted) {
      setState(() => _reportDateRange = range);
    }
  }

  Future<void> _exportBackup() async {
    final backup = AulaPuntosBackup(
      groupName: _selectedGroup,
      groupProgram: _activeGroup.program,
      course: _activeGroup.course,
      period: _activeGroup.period,
      sectionCode: _activeGroup.sectionCode,
      sessionName: _selectedSession,
      sessionDate: _sessionDate,
      students: [
        for (final student in _students)
          BackupStudent(
            name: student.name,
            code: student.code,
            attendance: student.attendance.name,
            points: student.points,
          ),
      ],
    );
    try {
      final result = await FilePicker.saveFile(
        fileName: 'aula_puntos_backup.json',
        bytes: Uint8List.fromList(utf8.encode(backup.encode())),
        mimeType: 'application/json',
        dialogTitle: 'Exportar respaldo de Aula Puntos',
      );
      if (result != null && mounted) {
        _notify('Respaldo JSON exportado.');
      }
    } on PlatformException catch (error) {
      if (mounted) _notify('No se pudo exportar el respaldo: ${error.message}');
    }
  }

  Future<void> _importBackup() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Importar respaldo de Aula Puntos',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      final fileLength = await file.length();
      if (fileLength == null) {
        _notify('No se pudo verificar el tamaño del respaldo.');
        return;
      }
      if (fileLength > 10 * 1024 * 1024) {
        _notify('El respaldo supera el limite de 10 MB.');
        return;
      }
      final backup = AulaPuntosBackup.decode(await file.xFile.readAsString());
      final matchingGroupIndex = _groups.indexWhere(
        (group) =>
            group.name.trim().toLowerCase() ==
            backup.groupName.trim().toLowerCase(),
      );
      if (backup.sectionCode.isNotEmpty &&
          _groups.asMap().entries.any(
            (entry) =>
                entry.key != matchingGroupIndex &&
                entry.value.sectionCode.trim().toLowerCase() ==
                    backup.sectionCode.trim().toLowerCase(),
          )) {
        _notify(
          'No se pudo importar: el codigo de seccion ya pertenece a otro grupo.',
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reemplazar datos del grupo'),
          content: Text(
            'Se importaran ${backup.students.length} estudiantes de '
            '${backup.groupName} para ${backup.sessionName}. '
            'Los datos de ejemplo actuales seran reemplazados.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final importedStudents = <Map<String, Object?>>[];
      for (final student in backup.students) {
        importedStudents.add({
          'name': student.name,
          'code': student.code,
          'initials': _initials(student.name),
          'attendance': student.attendance,
          'points': student.points,
        });
      }
      await widget.database.importGroup(
        name: backup.groupName,
        program: backup.groupProgram,
        course: backup.course,
        period: backup.period,
        sectionCode: backup.sectionCode,
        sessionName: backup.sessionName,
        sessionDate: backup.sessionDate,
        students: importedStudents,
      );
      final records = await widget.database.groups();
      if (!mounted) return;
      setState(() {
        _groups
          ..clear()
          ..addAll(records.map(_groupFromRow));
        _selectedGroup = backup.groupName;
        _selectedSession = backup.sessionName;
        _sessionDate = backup.sessionDate;
      });
      await _loadGroupContext(_activeGroup);
      await _refreshPendingCount();
      _notify('Respaldo importado y guardado localmente.');
    } on FormatException catch (error) {
      if (mounted) _notify('No se pudo importar el archivo: ${error.message}');
    } on PlatformException catch (error) {
      if (mounted) _notify('No se pudo leer el archivo: ${error.message}');
    } on DatabaseException catch (error) {
      if (mounted) _notify('No se pudo guardar el respaldo importado: $error');
    }
  }

  String _initials(String name) {
    final names = name.trim().split(RegExp(r'\s+'));
    return names
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();
  }

  _ReportExportData? _validatedReportData() {
    final students = _filteredReportStudents;
    final attendanceCounts = {
      for (final status in AttendanceStatus.values) status: 0,
    };
    for (final student in students) {
      attendanceCounts[student.attendance] =
          attendanceCounts[student.attendance]! + 1;
    }
    final totalByStatus = attendanceCounts.values.fold<int>(
      0,
      (total, count) => total + count,
    );
    final totalPoints = students.fold<int>(
      0,
      (total, student) => total + student.points,
    );
    if (totalByStatus != students.length ||
        students.any((student) => student.points < 0)) {
      _notify('No se exporto: los totales no coinciden con los registros.');
      return null;
    }

    return _ReportExportData(
      students: students,
      attendanceCounts: attendanceCounts,
      totalPoints: totalPoints,
    );
  }

  Future<void> _exportReportCsv() async {
    final report = _validatedReportData();
    if (report == null) return;
    final rows = <List<String>>[
      ['Grupo', _selectedGroup],
      ['Programa academico', _activeGroup.program],
      ['Asignatura / curso', _activeGroup.course],
      ['Periodo', _activeGroup.period],
      ['Codigo de seccion', _activeGroup.sectionCode],
      ['Sesion', _selectedSession],
      ['Fecha de sesion', _dateLabel(_sessionDate)],
      ['Generado', DateTime.now().toIso8601String()],
      [
        'Criterios',
        'Estudiante: ${_reportStudentQuery.isEmpty ? 'todos' : _reportStudentQuery}; '
            'fechas: ${_reportDateRange == null ? 'todas' : dateRangeLabel(_reportDateRange!)}',
      ],
      ['Total de estudiantes incluidos', '${report.students.length}'],
      ['Total de puntos', '${report.totalPoints}'],
      for (final status in AttendanceStatus.values)
        [
          'Total ${status.label.toLowerCase()}',
          '${report.attendanceCounts[status]}',
        ],
      [],
      ['Estudiante', 'Asistencia', 'Puntos'],
      for (final student in report.students)
        [student.name, student.attendance.label, '${student.points}'],
    ];
    final csv =
        '\uFEFF${rows.map((row) => row.map(_csvCell).join(',')).join('\r\n')}';
    try {
      final result = await FilePicker.saveFile(
        fileName: 'aula_puntos_reporte.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
        dialogTitle: 'Exportar reporte del grupo',
      );
      if (result != null && mounted) _notify('Reporte CSV exportado.');
    } on PlatformException catch (error) {
      if (mounted) _notify('No se pudo exportar el reporte: ${error.message}');
    }
  }

  Future<void> _exportReportPdf() async {
    final report = _validatedReportData();
    if (report == null) return;
    try {
      final bytes = await createAulaPuntosPdfReport(
        groupName: _selectedGroup,
        program: _activeGroup.program,
        course: _activeGroup.course,
        period: _activeGroup.period,
        sectionCode: _activeGroup.sectionCode,
        sessionName: _selectedSession,
        sessionDate: _dateLabel(_sessionDate),
        generatedAt: DateTime.now().toIso8601String(),
        criteria:
            'Estudiante: ${_reportStudentQuery.isEmpty ? 'todos' : _reportStudentQuery}; '
            'fechas: ${_reportDateRange == null ? 'todas' : dateRangeLabel(_reportDateRange!)}',
        studentCount: report.students.length,
        totalPoints: report.totalPoints,
        attendanceCounts: {
          for (final status in AttendanceStatus.values)
            status.label: report.attendanceCounts[status]!,
        },
        students: [
          for (final student in report.students)
            AulaPuntosPdfStudent(
              name: student.name,
              attendance: student.attendance.label,
              points: student.points,
            ),
        ],
      );
      final result = await FilePicker.saveFile(
        fileName: 'aula_puntos_reporte.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Exportar reporte del grupo',
      );
      if (result != null && mounted) _notify('Reporte PDF exportado.');
    } on PlatformException catch (error) {
      if (mounted) _notify('No se pudo exportar el reporte: ${error.message}');
    } on Exception catch (error) {
      if (mounted) _notify('No se pudo generar el reporte PDF: $error');
    }
  }

  String dateRangeLabel(DateTimeRange range) =>
      '${_dateLabel(range.start)}–${_dateLabel(range.end)}';

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  Widget _reportsPage() {
    final students = _filteredReportStudents;
    final present = students
        .where((student) => student.attendance == AttendanceStatus.present)
        .length;
    final points = students.fold<int>(
      0,
      (total, student) => total + student.points,
    );
    final percentage = students.isEmpty
        ? 0
        : ((present / students.length) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageIntro(
          'Reportes',
          'Consulta resultados por grupo, sesion, fecha y estudiante.',
        ),
        const SizedBox(height: 18),
        _selectionBar(),
        const SizedBox(height: 12),
        _reportFilters(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _exportReportCsv,
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Exportar reporte CSV'),
            ),
            OutlinedButton.icon(
              onPressed: _exportReportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exportar reporte PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _exportBackup,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Exportar respaldo JSON'),
            ),
            OutlinedButton.icon(
              onPressed: _importBackup,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Importar respaldo JSON'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 650 ? 3 : 1;
            return _responsiveGrid(
              columns: columns,
              children: [
                _statCard(
                  'Asistencia del grupo',
                  '$percentage%',
                  '${students.length} registros incluidos',
                  Icons.fact_check_outlined,
                  const Color(0xFF16845B),
                ),
                _statCard(
                  'Puntos asignados',
                  '$points',
                  'Acumulado de estudiantes filtrados',
                  Icons.stars_rounded,
                  const Color(0xFFDA951E),
                ),
                _statCard(
                  'Estudiantes',
                  '${students.length}',
                  'Coinciden con los filtros',
                  Icons.groups_2_outlined,
                  const Color(0xFF3767D5),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Detalle por estudiante',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  '$_selectedGroup · $_selectedSession · ${_dateLabel(_sessionDate)} · '
                  '${students.length} registros',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF8994A8),
                  ),
                ),
                const Divider(height: 24),
                if (students.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text('No hay registros para estos filtros.'),
                    ),
                  )
                else
                  for (final student in students)
                    _studentRow(student, compact: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createGroup() => _showGroupForm();

  Future<void> _editGroup(InstructorGroup group) =>
      _showGroupForm(group: group);

  Future<void> _showGroupForm({InstructorGroup? group}) async {
    final result = await showDialog<InstructorGroup>(
      context: context,
      builder: (context) =>
          _GroupFormDialog(initialGroup: group, existingGroups: _groups),
    );
    if (result == null || !mounted) return;

    final duplicate = _groups.any(
      (existing) =>
          !identical(existing, group) &&
          (existing.name.trim().toLowerCase() ==
                  result.name.trim().toLowerCase() ||
              existing.sectionCode.trim().toLowerCase() ==
                  result.sectionCode.trim().toLowerCase()),
    );
    if (duplicate) {
      _notify('Ya existe un grupo con ese nombre o codigo de seccion.');
      return;
    }

    try {
      final id = await widget.database.saveGroup(
        id: group?.id,
        name: result.name,
        program: result.program,
        course: result.course,
        period: result.period,
        sectionCode: result.sectionCode,
      );
      setState(() {
        if (group == null) {
          result.id = id;
          _groups.add(result);
          _selectedGroup = result.name;
          _students = result.students;
        } else {
          final wasSelected = _selectedGroup == group.name;
          group
            ..name = result.name
            ..program = result.program
            ..course = result.course
            ..period = result.period
            ..sectionCode = result.sectionCode;
          if (wasSelected) {
            _selectedGroup = group.name;
            _students = group.students;
          }
        }
      });
      if (group == null) await _loadGroupContext(result);
      await _refreshPendingCount();
      _notify(
        group == null
            ? 'Grupo creado y guardado.'
            : 'Grupo actualizado y guardado.',
      );
    } on DatabaseException catch (error) {
      _notify('No se pudo guardar el grupo: $error');
    }
  }

  Future<void> _deleteGroup(InstructorGroup group) async {
    if (_groups.length == 1) {
      _notify('Debe quedar al menos un grupo en la lista.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text(
          'Se eliminara "${group.name}" y sus ${group.students.length} '
          'estudiantes del prototipo. Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.database.deleteGroup(group.id!);
      setState(() {
        _groups.remove(group);
        if (_selectedGroup == group.name) {
          _selectedGroup = _groups.first.name;
          _students = _activeGroup.students;
        }
      });
      if (_selectedGroup == _activeGroup.name) {
        await _loadGroupContext(_activeGroup);
      }
      await _refreshPendingCount();
      _notify('Grupo eliminado.');
    } on DatabaseException catch (error) {
      _notify('No se pudo eliminar el grupo: $error');
    }
  }

  Widget _groupsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageIntro(
          'Mis grupos',
          'Crea, consulta y administra tus grupos academicos.',
        ),
        const SizedBox(height: 18),
        if (_groups.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Todavia no tienes grupos. Crea uno para comenzar.',
                ),
              ),
            ),
          ),
        for (final group in _groups)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                _selectGroup(group.name);
                _notify('Grupo seleccionado: ${group.name}');
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: group.name == _selectedGroup
                            ? const Color(0xFFDFE9FF)
                            : const Color(0xFFEEF3FF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.groups_2_outlined,
                        color: Color(0xFF3767D5),
                      ),
                    ),
                    const SizedBox(width: 13),
                    IconButton(
                      tooltip: 'Editar ${group.name}',
                      onPressed: () => _editGroup(group),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Eliminar ${group.name}',
                      onPressed: () => _deleteGroup(group),
                      icon: const Icon(Icons.delete_outline),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  group.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (group.name == _selectedGroup) ...[
                                const SizedBox(width: 8),
                                _tag(
                                  'SELECCIONADO',
                                  const Color(0xFFE8F5EE),
                                  const Color(0xFF16845B),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Programa: ${group.program} | Asignatura: ${group.course}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF536176),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Periodo: ${group.period} | Seccion: ${group.sectionCode} | '
                            '${group.students.length} estudiantes',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF8994A8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tag(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GroupFormDialog extends StatefulWidget {
  const _GroupFormDialog({required this.existingGroups, this.initialGroup});

  final List<InstructorGroup> existingGroups;
  final InstructorGroup? initialGroup;

  @override
  State<_GroupFormDialog> createState() => _GroupFormDialogState();
}

class _GroupFormDialogState extends State<_GroupFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _programController;
  late final TextEditingController _courseController;
  late final TextEditingController _periodController;
  late final TextEditingController _sectionCodeController;

  @override
  void initState() {
    super.initState();
    final group = widget.initialGroup;
    _nameController = TextEditingController(text: group?.name);
    _programController = TextEditingController(text: group?.program);
    _courseController = TextEditingController(text: group?.course);
    _periodController = TextEditingController(text: group?.period);
    _sectionCodeController = TextEditingController(text: group?.sectionCode);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _programController.dispose();
    _courseController.dispose();
    _periodController.dispose();
    _sectionCodeController.dispose();
    super.dispose();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'Este campo es obligatorio.'
      : null;

  String? _uniqueName(String? value) {
    final required = _required(value);
    if (required != null) return required;
    final normalized = value!.trim().toLowerCase();
    final duplicate = widget.existingGroups.any(
      (group) =>
          !identical(group, widget.initialGroup) &&
          group.name.trim().toLowerCase() == normalized,
    );
    return duplicate ? 'Ya existe un grupo con ese nombre.' : null;
  }

  String? _uniqueSectionCode(String? value) {
    final required = _required(value);
    if (required != null) return required;
    final normalized = value!.trim().toLowerCase();
    final duplicate = widget.existingGroups.any(
      (group) =>
          !identical(group, widget.initialGroup) &&
          group.sectionCode.trim().toLowerCase() == normalized,
    );
    return duplicate ? 'Este codigo de seccion ya esta en uso.' : null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initialGroup;
    Navigator.pop(
      context,
      InstructorGroup(
        name: _nameController.text.trim(),
        program: _programController.text.trim(),
        course: _courseController.text.trim(),
        period: _periodController.text.trim(),
        sectionCode: _sectionCodeController.text.trim(),
        students: initial?.students,
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialGroup != null;
    return AlertDialog(
      title: Text(editing ? 'Editar Grupo SENATI' : 'Nuevo Grupo SENATI'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(
                  label: 'Nombre del Grupo',
                  controller: _nameController,
                  validator: _uniqueName,
                  hint: 'Ej. NRC_2044',
                ),
                _field(
                  label: 'Programa Academico',
                  controller: _programController,
                  validator: _required,
                  hint: 'Ej. 2026-20',
                ),
                _field(
                  label: 'Asignatura / Curso',
                  controller: _courseController,
                  validator: _required,
                  hint: 'Nombre de la asignatura',
                ),
                _field(
                  label: 'Periodo',
                  controller: _periodController,
                  validator: _required,
                  hint: 'Ej. 2026-I',
                ),
                _field(
                  label: 'Codigo de Seccion',
                  controller: _sectionCodeController,
                  validator: _uniqueSectionCode,
                  hint: 'Ej. 2026-20-202601',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(editing ? 'Guardar cambios' : 'Guardar'),
        ),
      ],
    );
  }
}
