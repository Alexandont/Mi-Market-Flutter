import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:image_picker/image_picker.dart';

import 'registro_producto_offline.dart' as registro_offline;

import '../firebase/firebase_auth_manager.dart';
import '../firebase/firebase_storage_manager.dart';
import '../firebase/firestore_repository.dart';
import '../local/catalogo_cache_local.dart';
import '../local/local_database_provider.dart';
import '../local/offline_store.dart';
import 'catalogo_offline_reader.dart';
import '../models/carrito_provider.dart';
import '../models/producto_model.dart';
import '../network/api_response.dart';
import '../network/api_service.dart';

/// Repositorio de productos.
///
/// Es la fachada que usan las pantallas. Combina tres origenes:
///
/// 1. El servidor REST local, cuando esta levantado.
/// 2. Cloud Firestore, que es la fuente principal.
/// 3. La cache en memoria de [CarritoProvider], como respaldo sin conexion.
///
/// Firestore manda: si devuelve datos, su version es la buena.
class ProductoRepository {
  final ApiService _api;
  final FirestoreRepository _firestore;
  final FirebaseStorageManager _storage;
  final FirebaseAuthManager _auth;
  final CarritoProvider _cache;

  ProductoRepository({
    ApiService? api,
    FirestoreRepository? firestore,
    FirebaseStorageManager? storage,
    FirebaseAuthManager? auth,
    CarritoProvider? cache,
  }) : _api = api ?? ApiService(),
       _firestore = firestore ?? FirestoreRepository(),
       _storage = storage ?? FirebaseStorageManager(),
       _auth = auth ?? FirebaseAuthManager(),
       _cache = cache ?? CarritoProvider();

  /// Trae la lista de productos combinando el servidor REST y Firestore.
  ///
  /// Los duplicados se descartan por identificador. Si ninguna de las dos
  /// fuentes responde, cae en la cache.
  Future<ApiResponse<List<ProductoModel>>> obtenerProductos() async {
    final deRest = await _api.obtenerProductos();
    final deFirestore = await _firestore.obtenerProductos();

    final combinados = <ProductoModel>[
      ...deRest,
      ...(deFirestore.data ?? const <ProductoModel>[]),
    ];

    if (combinados.isEmpty) {
      final cacheados = _cache.obtenerProductos();
      if (cacheados.isNotEmpty) {
        return ApiResponse.exito(
          cacheados,
          message: 'Mostrando los ultimos productos guardados sin conexion',
        );
      }
      // Nada en ningun lado: si Firestore fallo, ese es el error a reportar.
      if (!deFirestore.isSuccess) {
        return ApiResponse.error(
          deFirestore.message ?? 'No se pudieron cargar los productos',
          statusCode: deFirestore.statusCode,
        );
      }
      return ApiResponse.exito(
        const <ProductoModel>[],
        message: 'Todavia no hay productos registrados',
      );
    }

    final unicos = _sinDuplicados(combinados);
    _cache.actualizarProductos(unicos);

    return ApiResponse.exito(
      unicos,
      message: 'Productos cargados desde el servidor REST y Firebase',
    );
  }

  /// Lee SQLite primero; actualiza la copia local solo con eventos fiables.
  /// Las operaciones de escritura existentes no cambian en esta subetapa.
  Stream<List<ProductoModel>> escucharProductos() => _escucharConSQLite();

  Stream<List<ProductoModel>> _escucharConSQLite() async* {
    final uid = _auth.uidActual;
    if (uid.isEmpty) {
      yield* _firestore.escucharProductos().map((lista) {
        _cache.actualizarProductos(lista);
        return lista;
      });
      return;
    }

    // Si SQLite no abre, conservar la lectura Firebase que ya funcionaba.
    late final CatalogoOfflineReader lector;
    try {
      final db = await LocalDatabaseProvider.database;
      lector = CatalogoOfflineReader(
        cache: CatalogoCacheLocal(db),
        store: OfflineStore(db),
        fuente: FirebaseCatalogoFuente(),
      );
    } catch (_) {
      yield* _firestore.escucharProductos().map((lista) {
        _cache.actualizarProductos(lista);
        return lista;
      });
      return;
    }

    await for (final lista in lector.observar(uid)) {
      _cache.actualizarProductos(lista);
      yield lista;
    }
  }

  /// Registra un producto nuevo, subiendo primero la foto si la hay.
  ///
  /// El orden importa: la foto se sube antes de guardar el producto, porque
  /// su URL tiene que ir dentro del documento.
  Future<ApiResponse<ProductoModel>> crearProducto(
    ProductoModel producto, [
    XFile? imagen,
  ]) async {
    final uid = _auth.uidActual;
    if (uid.isEmpty) {
      return ApiResponse.error(
        'Debe iniciar sesion para registrar productos',
        statusCode: 401,
      );
    }

    // Android/iOS: escribir primero SQLite y conservar la fotografia.
    // NO enviar a Firebase hasta que exista sincronizacion de imagen+documento.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final local = await registro_offline.registrarProductoLocal(
          uid,
          producto,
          imagen,
        );
        _cache.agregarProducto(local);
        return ApiResponse.exito(
          local,
          message: 'Guardado en el dispositivo. Pendiente de sincronizacion',
          statusCode: 201,
        );
      } catch (e) {
        return ApiResponse.error('No se pudo guardar localmente: $e');
      }
    }

    var porGuardar = producto.copyWith(creadorUid: uid);

    if (imagen != null) {
      final subida = await _storage.subirFotoProducto(imagen, uid);
      if (!subida.isSuccess || subida.data == null) {
        return ApiResponse.error(
          subida.message ?? 'No se pudo subir la foto del producto',
          statusCode: subida.statusCode,
        );
      }
      porGuardar = porGuardar.copyWith(
        imagenUrl: subida.data!.url,
        imagenRuta: subida.data!.ruta,
      );
    }

    final guardado = await _firestore.crearProducto(porGuardar);
    if (!guardado.isSuccess || guardado.data == null) {
      // Si Firestore fallo, se borra la foto para no dejarla huerfana.
      if (porGuardar.imagenRuta.isNotEmpty) {
        await _storage.eliminarArchivo(porGuardar.imagenRuta);
      }
      return guardado;
    }

    // El servidor REST es un extra: si no esta, no pasa nada.
    await _api.crearProducto(guardado.data!);
    _cache.agregarProducto(guardado.data!);

    return ApiResponse.exito(
      guardado.data!,
      message: 'Producto registrado',
      statusCode: 201,
    );
  }

  /// Actualiza un producto. Si llega una foto nueva, borra la anterior.
  Future<ApiResponse<ProductoModel>> actualizarProducto(
    String id,
    ProductoModel producto, [
    XFile? imagen,
  ]) async {
    final uid = _auth.uidActual;
    if (uid.isEmpty) {
      return ApiResponse.error('Debe iniciar sesion', statusCode: 401);
    }

    var porGuardar = producto.copyWith(id: id);
    final rutaAnterior = producto.imagenRuta;

    if (imagen != null) {
      final subida = await _storage.subirFotoProducto(imagen, uid);
      if (!subida.isSuccess || subida.data == null) {
        return ApiResponse.error(
          subida.message ?? 'No se pudo subir la foto',
          statusCode: subida.statusCode,
        );
      }
      porGuardar = porGuardar.copyWith(
        imagenUrl: subida.data!.url,
        imagenRuta: subida.data!.ruta,
      );
    }

    final actualizado = await _firestore.actualizarProducto(id, porGuardar);
    if (!actualizado.isSuccess) return actualizado;

    // La foto vieja se borra solo despues de que la nueva quedo guardada.
    if (imagen != null &&
        rutaAnterior.isNotEmpty &&
        rutaAnterior != porGuardar.imagenRuta) {
      await _storage.eliminarArchivo(rutaAnterior);
    }

    await _api.actualizarProducto(id, porGuardar);
    _refrescarCache(porGuardar);

    return actualizado;
  }

  /// Elimina un producto y su foto.
  Future<ApiResponse<bool>> eliminarProducto(ProductoModel producto) async {
    final borrado = await _firestore.eliminarProducto(producto.id);
    if (!borrado.isSuccess) return borrado;

    if (producto.imagenRuta.isNotEmpty) {
      await _storage.eliminarArchivo(producto.imagenRuta);
    }
    await _api.eliminarProducto(producto.id);

    final restantes = _cache
        .obtenerProductos()
        .where((p) => p.id != producto.id)
        .toList();
    _cache.actualizarProductos(restantes);

    return ApiResponse.exito(true, message: 'Producto eliminado');
  }

  /// Busca productos por nombre en el servidor REST y en Firestore.
  Future<ApiResponse<List<ProductoModel>>> buscarProductos(
    String consulta,
  ) async {
    final texto = consulta.trim();
    if (texto.isEmpty) return obtenerProductos();

    final deRest = await _api.buscarProductos(texto);
    final deFirestore = await _firestore.buscarProductos(texto);

    final combinados = <ProductoModel>[
      ...deRest,
      ...(deFirestore.data ?? const <ProductoModel>[]),
    ];

    if (combinados.isEmpty) {
      // La busqueda de Firestore solo encuentra por prefijo; la cache busca
      // tambien dentro del texto, asi que a veces rescata resultados.
      return ApiResponse.exito(
        _cache.buscarProductos(texto),
        message: 'Busqueda local',
      );
    }

    return ApiResponse.exito(
      _sinDuplicados(combinados),
      message: 'Busqueda completada',
    );
  }

  /// Filtra por categoria.
  Future<ApiResponse<List<ProductoModel>>> porCategoria(String categoria) {
    return _firestore.productosPorCategoria(categoria);
  }

  /// Indica si el usuario actual puede editar o borrar este producto.
  ///
  /// Solo su creador. El rol de administrador se valida ademas en las reglas
  /// de seguridad de Firestore, que es donde realmente cuenta.
  bool puedeEditar(ProductoModel producto) {
    final uid = _auth.uidActual;
    return uid.isNotEmpty && producto.creadorUid == uid;
  }

  /// Descarta repetidos conservando el primero de cada identificador.
  List<ProductoModel> _sinDuplicados(List<ProductoModel> lista) {
    final vistos = <String>{};
    return lista.where((p) {
      final clave = p.id.isNotEmpty ? p.id : p.nombre;
      return vistos.add(clave);
    }).toList();
  }

  void _refrescarCache(ProductoModel producto) {
    final lista = _cache.obtenerProductos().toList();
    final indice = lista.indexWhere((p) => p.id == producto.id);
    if (indice != -1) {
      lista[indice] = producto;
      _cache.actualizarProductos(lista);
    }
  }
}
