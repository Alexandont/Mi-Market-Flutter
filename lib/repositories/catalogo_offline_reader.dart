import 'package:cloud_firestore/cloud_firestore.dart';

import '../local/catalogo_cache_local.dart';
import '../local/offline_store.dart';
import '../models/producto_model.dart';
import '../network/api_contract.dart';

/// Un evento puede venir de la caché Firestore (parcial) o del servidor.
class CatalogoEvento {
  const CatalogoEvento({
    required this.productos,
    required this.confirmadoPorServidor,
  });

  final List<ProductoModel> productos;
  final bool confirmadoPorServidor;
}

/// Interfaz inyectable, sin Firebase en las pruebas unitarias.
abstract class CatalogoFuente {
  Stream<CatalogoEvento> observar();
}

class FirebaseCatalogoFuente implements CatalogoFuente {
  FirebaseCatalogoFuente({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<CatalogoEvento> observar() => _firestore
      .collection(ApiContract.coleccionProductos)
      .orderBy('nombre')
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => CatalogoEvento(
          productos: snapshot.docs
              .map(
                (doc) => ProductoModel.fromJson({...doc.data(), 'id': doc.id}),
              )
              .toList(),
          confirmadoPorServidor:
              !snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites,
        ),
      );
}

/// Combina SQLite y Firestore sin borrar cambios offline pendientes.
/// Solo los snapshots completos y confirmados pueden podar registros locales.
class CatalogoOfflineReader {
  CatalogoOfflineReader({
    required this.cache,
    required this.store,
    required this.fuente,
  });

  final CatalogoCacheLocal cache;
  final OfflineStore store;
  final CatalogoFuente fuente;

  Stream<List<ProductoModel>> observar(String uid) async* {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Se requiere sesion autenticada');
    }

    // Mostrar SQLite inmediatamente, antes de intentar contactar Firebase.
    yield _ordenar(await cache.leer(uid));

    try {
      await for (final evento in fuente.observar()) {
        if (evento.confirmadoPorServidor) {
          // Catalogo remoto completo: respeta IDs con operaciones pendientes.
          await cache.guardarSnapshotRemoto(uid, evento.productos);
          yield _ordenar(await cache.leer(uid));
        } else {
          // Caché de Firestore potencialmente incompleta: jamás podar SQLite.
          yield _ordenar(await _combinarCacheIncompleta(uid, evento.productos));
        }
      }
    } catch (_) {
      // Si el servidor falla, la copia local sigue disponible.
      // MVVM añadirá más adelante un estado de error/conectividad visible.
      yield _ordenar(await cache.leer(uid));
    }
  }

  Future<List<ProductoModel>> _combinarCacheIncompleta(
    String uid,
    List<ProductoModel> delFirestore,
  ) async {
    final locales = await cache.leer(uid);
    final pendientes = await store.operacionesPendientes(uid);
    final accionPorId = <String, String>{};
    for (final operacion in pendientes) {
      if (operacion.entidad == 'producto') {
        accionPorId[operacion.idEntidad] = operacion.accion;
      }
    }

    final visibles = <String, ProductoModel>{
      for (final producto in locales) producto.id: producto,
    };
    for (final producto in delFirestore) {
      if (producto.id.isNotEmpty && !accionPorId.containsKey(producto.id)) {
        visibles[producto.id] = producto;
      }
    }
    for (final entry in accionPorId.entries) {
      if (entry.value == 'delete') visibles.remove(entry.key);
    }
    return visibles.values.toList();
  }

  List<ProductoModel> _ordenar(List<ProductoModel> lista) =>
      [...lista]..sort((a, b) => a.nombre.compareTo(b.nombre));
}
