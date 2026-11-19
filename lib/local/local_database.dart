import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Base local de Mi-Market. Un archivo SQLite por instalacion.
/// Todos los registros de negocio estan separados por el UID de Firebase.
/// No se guardan contrasenas ni tokens de autenticacion en estas tablas.
class LocalDatabase {
  LocalDatabase._(this.database);

  static const String fileName = 'mimarket_offline_v1.db';
  static const int schemaVersion = 1;

  final Database database;

  /// Para Android/iOS. No se llama aun desde main.dart en esta etapa.
  static Future<LocalDatabase> open() async {
    final folder = await getDatabasesPath();
    return openWithFactory(databaseFactory, path.join(folder, fileName));
  }

  /// Permite realizar pruebas SQLite reales con sqflite_common_ffi.
  static Future<LocalDatabase> openWithFactory(
    DatabaseFactory factory,
    String databasePath,
  ) async {
    final db = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _createSchema,
      ),
    );
    return LocalDatabase._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE productos_local (
        owner_uid TEXT NOT NULL,
        id TEXT NOT NULL,
        payload TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),
        modified_at INTEGER NOT NULL,
        PRIMARY KEY (owner_uid, id)
      )
    ''');
    await db.execute('''
      CREATE TABLE pedidos_local (
        owner_uid TEXT NOT NULL,
        id TEXT NOT NULL,
        payload TEXT NOT NULL,
        modified_at INTEGER NOT NULL,
        PRIMARY KEY (owner_uid, id)
      )
    ''');
    await db.execute('''
      CREATE TABLE carrito_local (
        owner_uid TEXT NOT NULL,
        producto_id TEXT NOT NULL,
        producto_payload TEXT NOT NULL,
        cantidad INTEGER NOT NULL CHECK (cantidad > 0),
        PRIMARY KEY (owner_uid, producto_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE operaciones_pendientes (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT NOT NULL UNIQUE,
        owner_uid TEXT NOT NULL,
        entity_type TEXT NOT NULL CHECK (entity_type IN ('producto', 'pedido')),
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL CHECK (action IN ('upsert', 'delete')),
        payload TEXT,
        created_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX pendientes_por_usuario
      ON operaciones_pendientes (owner_uid, sequence)
    ''');
  }

  Future<void> close() => database.close();
}
