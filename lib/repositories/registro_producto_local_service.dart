import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../local/imagenes_producto_locales.dart';
import '../local/offline_store.dart';
import '../models/producto_model.dart';

/// Primera mitad del registro offline-first: SOLO almacenamiento local.
///
/// Genera un ID estable antes de guardar la fotografia y el producto.
/// La escritura de producto + outbox es atomica dentro de OfflineStore.
/// No intenta usar Firestore ni Firebase Storage; una etapa posterior
/// procesara la outbox y confirmara el envio remoto.
class RegistroProductoLocalService {
  RegistroProductoLocalService({
    required this.store,
    required this.imagenes,
    String Function()? nuevoId,
  }) : _nuevoId = nuevoId ?? const Uuid().v4;

  final OfflineStore store;
  final ImagenesProductoLocales imagenes;
  final String Function() _nuevoId;

  /// Guarda una nueva entidad, con fotografia persistente opcional.
  ///
  /// Retorna solo cuando SQLite confirma los datos y su operacion pendiente.
  /// Si SQLite falla, la foto persistente se conserva para diagnostico;
  /// no se borra un archivo que podria ser recuperable.
  Future<ProductoModel> registrar(
    String uid,
    ProductoModel producto, {
    XFile? fotografia,
  }) async {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Se requiere sesion iniciada');
    }
    if (producto.id.trim().isNotEmpty) {
      throw ArgumentError.value(
        producto.id,
        'producto.id',
        'Este servicio solo crea productos nuevos',
      );
    }
    if (producto.nombre.trim().length < 2 ||
        !producto.precio.isFinite ||
        producto.precio <= 0 ||
        producto.stock < 0) {
      throw ArgumentError('Datos del producto no validos');
    }

    final id = _nuevoId();
    if (id.trim().isEmpty) {
      throw StateError('El generador devolvio un identificador vacio');
    }
    final ahora = DateTime.now().millisecondsSinceEpoch;
    final definitivo = producto.copyWith(
      id: id,
      creadorUid: uid,
      creadoEn: ahora,
      actualizadoEn: ahora,
      // La URL definitiva solo se asigna cuando Firebase Storage responde.
      imagenUrl: '',
      imagenRuta: '',
    );

    // La foto queda fuera de la cache temporal del selector ANTES de anotar
    // la operacion pendiente en SQLite. Se identifica por (uid, productoId).
    if (fotografia != null) {
      await imagenes.guardarSeleccionada(uid, id, fotografia);
    }

    // SQLite y outbox se guardan en una sola transaccion (OfflineStore).
    await store.guardarProducto(uid, definitivo);
    return definitivo;
  }
}
