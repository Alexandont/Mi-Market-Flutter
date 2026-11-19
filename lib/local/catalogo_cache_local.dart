import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/producto_model.dart';
import 'local_database.dart';
import 'offline_store.dart';

/// Cache del catalogo remoto completo, separada por usuario.
///
/// ATENCION: [guardarSnapshotRemoto] recibe SOLO snapshots completos, no
/// resultados de filtros/busquedas. Nunca genera operaciones pendientes.
/// Mantiene intocables las entidades con operaciones offline no confirmadas,
/// incluido un borrado pendiente (tombstone).
class CatalogoCacheLocal {
  CatalogoCacheLocal(this._local);

  final LocalDatabase _local;

  Future<List<ProductoModel>> leer(String uid) =>
      OfflineStore(_local).obtenerProductos(uid);

  Future<void> guardarSnapshotRemoto(
    String uid,
    List<ProductoModel> productos,
  ) async {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Se requiere usuario autenticado');
    }

    // Rechazar un snapshot incompleto antes de abrir una transaccion.
    final nuevos = <String, ProductoModel>{};
    for (final producto in productos) {
      if (producto.id.trim().isEmpty) {
        throw ArgumentError('El snapshot contiene un producto sin ID');
      }
      if (nuevos.containsKey(producto.id)) {
        throw ArgumentError('ID duplicado en snapshot: ${producto.id}');
      }
      nuevos[producto.id] = producto;
    }

    final ahora = DateTime.now().millisecondsSinceEpoch;
    await _local.database.transaction((txn) async {
      final cola = await txn.query(
        'operaciones_pendientes',
        columns: ['entity_id'],
        where: 'owner_uid = ? AND entity_type = ?',
        whereArgs: [uid, 'producto'],
      );
      final protegidos = cola
          .map((fila) => fila['entity_id'] as String)
          .toSet();

      final guardados = await txn.query(
        'productos_local',
        columns: ['id'],
        where: 'owner_uid = ?',
        whereArgs: [uid],
      );

      // Un snapshot remoto completo elimina las entradas obsoletas, pero
      // nunca descarta un cambio local que todavia esta en la outbox.
      for (final fila in guardados) {
        final id = fila['id'] as String;
        if (protegidos.contains(id) || nuevos.containsKey(id)) continue;
        await txn.delete(
          'productos_local',
          where: 'owner_uid = ? AND id = ?',
          whereArgs: [uid, id],
        );
      }

      for (final producto in nuevos.values) {
        if (protegidos.contains(producto.id)) continue;
        await txn.insert('productos_local', {
          'owner_uid': uid,
          'id': producto.id,
          'payload': jsonEncode(producto.toJson()),
          'deleted': 0,
          'modified_at': producto.actualizadoEn == 0
              ? ahora
              : producto.actualizadoEn,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
