# Aula Puntos

Aplicacion Flutter para gestionar grupos y registrar asistencia y participacion academica, con almacenamiento local SQLite para uso sin conexion.

## Ejecutar

```sh
flutter pub get
flutter run
```

En Windows, Linux y macOS se usa SQLite FFI; en Android e iOS, el plugin nativo SQLite. La base `aula_puntos.db` se crea en el directorio de datos de la aplicacion. El primer inicio carga grupos y estudiantes de demostracion.

## Funcionalidad local

- CRUD de grupos: nombre, programa, curso, periodo y codigo de seccion. SQLite impone unicidad de nombre y codigo.
- Listas de estudiantes separadas por grupo; el grupo seleccionado determina las operaciones de las pantallas.
- Sesiones unicas por grupo, asistencia unica por estudiante/sesion y validacion de estados en la base.
- Cambios de asistencia y puntos guardados en transacciones. El historial local de asistencia registra cambios de estado.
- Importacion JSON transaccional y exportacion de respaldo; reportes CSV y PDF filtrados, sin codigos institucionales.
- Cola SQLite persistente para cambios pendientes/error. El reintento no marca cambios sincronizados si no hay servicio remoto.

## Seguridad, sincronizacion y despliegue

La app conserva cambios localmente y sigue funcionando sin internet, pero todavia no sincroniza con un servidor. El estado de conexion es una demostracion manual; la cola se almacena localmente y no se pierde al cerrar la app. Sin API, reintentar solo marca la cola con error y explica que no hay backend conectado.

No hay autenticacion ni roles; no uses la app ni sus respaldos con datos personales reales. SQLite local no esta cifrado. Aun se requiere un backend ASP.NET Core con autenticacion/autorizacion, hash seguro, HTTPS, SQL Server, aislamiento de datos por instructor, auditoria remota, sincronizacion idempotente y resolucion de conflictos, ademas de politicas institucionales de respaldo/retencion.

SQLite funciona con el plugin nativo en Android/iOS, con FFI en Windows/macOS/Linux y con SQLite WASM persistido en IndexedDB en Flutter Web. El servicio web requiere los archivos `web/sqlite3.wasm` y `web/sqflite_sw.js` generados por `flutter pub run sqflite_common_ffi_web:setup`; ambos se incluyen en el proyecto. Los reportes PDF incluyen el grupo, la sesion, la fecha de generacion, los criterios aplicados, los totales validados y los estudiantes filtrados, sin codigos institucionales.

El entorno disponible tiene .NET SDK 9.0.200; esta fase no crea una API .NET, conforme al alcance local elegido.
