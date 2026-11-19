import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/pedido_model.dart';
import '../models/producto_model.dart';
import 'local_database.dart';
import 'operacion_pendiente.dart';

/// Una linea del carrito local. No se sincroniza con Firebase en esta etapa.
class CarritoLocalItem {
  const CarritoLocalItem({required this.producto, required this.cantidad});
  final ProductoModel producto;
  final int cantidad;
}

/// Acceso al almacenamiento local con patron "transactional outbox".
/// Una modificacion y su operacion pendiente se confirman atomicamente.
/// NUNCA se debe eliminar una operacion antes de confirmar la escritura remota.
class OfflineStore {
  OfflineStore(this._local);

  final LocalDatabase _local;
  final Uuid _uuid = const Uuid();

  Database get _db => _local.database;

  void _validarUid(String uid) {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Se requiere un UID autenticado');
    }
  }

  void _validarId(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Se requiere ID estable antes de guardar',
      );
    }
  }

  Future<void> _enqueue(
    Transaction txn, {
    required String uid,
    required String entidad,
    required String idEntidad,
    required String accion,
    Map<String, dynamic>? payload,
  }) async {
    await txn.insert('operaciones_pendientes', {
      'operation_id': _uuid.v4(),
      'owner_uid': uid,
      'entity_type': entidad,
      'entity_id': idEntidad,
      'action': accion,
      'payload': payload == null ? null : jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'last_error': null,
    });
  }

  /// Inserta/actualiza un producto y registra la sincronizacion pendiente.
  /// El producto DEBE traer un ID antes de entrar aqui.
  Future<void> guardarProducto(String uid, ProductoModel producto) async {
    _validarUid(uid);
    _validarId(producto.id);
    final payload = producto.toJson();
    await _db.transaction((txn) async {
      await txn.insert('productos_local', {
        'owner_uid': uid,
        'id': producto.id,
        'payload': jsonEncode(payload),
        'deleted': 0,
        'modified_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _enqueue(
        txn,
        uid: uid,
        entidad: 'producto',
        idEntidad: producto.id,
        accion: 'upsert',
        payload: payload,
      );
    });
  }

  /// Tombstone: no reaparece al leer localmente, incluso sin Internet.
  Future<void> eliminarProducto(String uid, String id) async {
    _validarUid(uid);
    _validarId(id);
    await _db.transaction((txn) async {
      await txn.update(
        'productos_local',
        {'deleted': 1, 'modified_at': DateTime.now().millisecondsSinceEpoch},
        where: 'owner_uid = ? AND id = ?',
        whereArgs: [uid, id],
      );
      await _enqueue(
        txn,
        uid: uid,
        entidad: 'producto',
        idEntidad: id,
        accion: 'delete',
      );
    });
  }

  Future<List<ProductoModel>> obtenerProductos(String uid) async {
    _validarUid(uid);
    final rows = await _db.query(
      'productos_local',
      where: 'owner_uid = ? AND deleted = 0',
      whereArgs: [uid],
      orderBy: 'modified_at DESC',
    );
    return rows.map((r) {
      final datos = Map<String, dynamic>.from(
        jsonDecode(r['payload'] as String) as Map,
      );
      return ProductoModel.fromJson({...datos, 'id': r['id']});
    }).toList();
  }

  /// Idempotencia remota: el ID del pedido se asigna localmente y se reutiliza.
  Future<void> guardarPedido(String uid, PedidoModel pedido) async {
    _validarUid(uid);
    _validarId(pedido.id);
    final payload = pedido.toJson();
    await _db.transaction((txn) async {
      await txn.insert('pedidos_local', {
        'owner_uid': uid,
        'id': pedido.id,
        'payload': jsonEncode(payload),
        'modified_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _enqueue(
        txn,
        uid: uid,
        entidad: 'pedido',
        idEntidad: pedido.id,
        accion: 'upsert',
        payload: payload,
      );
    });
  }

  Future<List<PedidoModel>> obtenerPedidos(String uid) async {
    _validarUid(uid);
    final rows = await _db.query(
      'pedidos_local',
      where: 'owner_uid = ?',
      whereArgs: [uid],
      orderBy: 'modified_at DESC',
    );
    return rows.map((r) {
      final datos = Map<String, dynamic>.from(
        jsonDecode(r['payload'] as String) as Map,
      );
      return PedidoModel.fromJson({...datos, 'id': r['id']});
    }).toList();
  }

  Future<void> guardarItemCarrito(
    String uid,
    ProductoModel producto,
    int cantidad,
  ) async {
    _validarUid(uid);
    _validarId(producto.id);
    if (cantidad <= 0) throw ArgumentError.value(cantidad, 'cantidad');
    await _db.insert('carrito_local', {
      'owner_uid': uid,
      'producto_id': producto.id,
      'producto_payload': jsonEncode(producto.toJson()),
      'cantidad': cantidad,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> quitarItemCarrito(String uid, String productoId) async {
    _validarUid(uid);
    _validarId(productoId);
    await _db.delete(
      'carrito_local',
      where: 'owner_uid = ? AND producto_id = ?',
      whereArgs: [uid, productoId],
    );
  }

  Future<void> vaciarCarrito(String uid) async {
    _validarUid(uid);
    await _db.delete('carrito_local', where: 'owner_uid = ?', whereArgs: [uid]);
  }

  Future<List<CarritoLocalItem>> obtenerCarrito(String uid) async {
    _validarUid(uid);
    final rows = await _db.query(
      'carrito_local',
      where: 'owner_uid = ?',
      whereArgs: [uid],
    );
    return rows.map((r) {
      final datos = Map<String, dynamic>.from(
        jsonDecode(r['producto_payload'] as String) as Map,
      );
      final producto = ProductoModel.fromJson({
        ...datos,
        'id': r['producto_id'],
      });
      return CarritoLocalItem(
        producto: producto,
        cantidad: r['cantidad'] as int,
      );
    }).toList();
  }

  Future<List<OperacionPendiente>> operacionesPendientes(String uid) async {
    _validarUid(uid);
    final rows = await _db.query(
      'operaciones_pendientes',
      where: 'owner_uid = ?',
      whereArgs: [uid],
      orderBy: 'sequence ASC',
    );
    return rows.map(OperacionPendiente.fromRow).toList();
  }

  /// Se invoca SOLAMENTE despues de que Firebase confirme la escritura.
  /// El UID protege contra un ACK recibido durante un cambio de cuenta.
  Future<void> confirmarSincronizacion(String uid, String idOperacion) async {
    _validarUid(uid);
    await _db.delete(
      'operaciones_pendientes',
      where: 'owner_uid = ? AND operation_id = ?',
      whereArgs: [uid, idOperacion],
    );
  }

  /// Conserva la operacion para un reintento posterior.
  Future<void> registrarError(
    String uid,
    String idOperacion,
    String error,
  ) async {
    _validarUid(uid);
    await _db.rawUpdate(
      '''
      UPDATE operaciones_pendientes
      SET attempts = attempts + 1, last_error = ?
      WHERE owner_uid = ? AND operation_id = ?
    ''',
      [error, uid, idOperacion],
    );
  }
}
