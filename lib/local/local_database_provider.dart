import 'local_database.dart';

/// Una única base SQLite por proceso. Reintenta abrirla si falló el inicio.
/// No cambia el esquema ni cierra la base mientras hay pantallas activas.
class LocalDatabaseProvider {
  LocalDatabaseProvider._();

  static Future<LocalDatabase>? _opening;

  static Future<LocalDatabase> get database async {
    final opening = _opening ??= LocalDatabase.open();
    try {
      return await opening;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }
}
