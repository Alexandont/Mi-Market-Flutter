import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pedido_model.dart';
import '../models/producto_model.dart';
import '../models/usuario_model.dart';
import '../network/api_contract.dart';
import '../network/api_response.dart';

/// Acceso a Cloud Firestore para Mi Market.
///
/// Trabaja sobre las mismas colecciones que la aplicacion nativa en Kotlin:
/// `productos`, `usuarios` y la subcoleccion `usuarios/{uid}/pedidos`.
class FirestoreRepository {
  final FirebaseFirestore _db;

  FirestoreRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _productos =>
      _db.collection(ApiContract.coleccionProductos);

  CollectionReference<Map<String, dynamic>> get _usuarios =>
      _db.collection(ApiContract.coleccionUsuarios);

  CollectionReference<Map<String, dynamic>> _pedidosDe(String uid) =>
      _usuarios.doc(uid).collection(ApiContract.coleccionPedidos);

  // ================================================================
  // PRODUCTOS
  // ================================================================

  /// Trae todos los productos ordenados por nombre.
  Future<ApiResponse<List<ProductoModel>>> obtenerProductos() async {
    try {
      final snapshot = await _productos.orderBy('nombre').get();
      final lista = snapshot.docs
          .map((doc) => ProductoModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList();

      return ApiResponse.exito(lista,
          message: 'Productos cargados desde Cloud Firestore');
    } on FirebaseException catch (e) {
      return ApiResponse.error(
        'Error de Firestore al cargar productos: ${e.message ?? e.code}',
        statusCode: ApiContract.httpServiceUnavailable,
      );
    } catch (e) {
      return ApiResponse.error('Error al cargar productos: $e');
    }
  }

  /// Escucha los productos en tiempo real.
  ///
  /// A diferencia de [obtenerProductos], esto devuelve un flujo: cada vez que
  /// alguien agrega o cambia un producto, la pantalla se actualiza sola.
  Stream<List<ProductoModel>> escucharProductos() {
    return _productos.orderBy('nombre').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => ProductoModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    });
  }

  /// Trae un producto por su identificador.
  Future<ApiResponse<ProductoModel>> obtenerProducto(String id) async {
    try {
      final doc = await _productos.doc(id).get();
      if (!doc.exists || doc.data() == null) {
        return ApiResponse.error('El producto no existe',
            statusCode: ApiContract.httpNotFound);
      }
      return ApiResponse.exito(
        ProductoModel.fromJson({...doc.data()!, 'id': doc.id}),
      );
    } catch (e) {
      return ApiResponse.error('Error al cargar el producto: $e');
    }
  }

  /// Crea un producto nuevo.
  ///
  /// Si el producto no trae identificador, deja que Firestore genere uno y lo
  /// guarda tambien dentro del documento, para que ambos valores coincidan.
  Future<ApiResponse<ProductoModel>> crearProducto(
      ProductoModel producto) async {
    try {
      final referencia = producto.id.isNotEmpty
          ? _productos.doc(producto.id)
          : _productos.doc();

      final ahora = DateTime.now().millisecondsSinceEpoch;
      final definitivo = producto.copyWith(
        id: referencia.id,
        creadoEn: producto.creadoEn == 0 ? ahora : producto.creadoEn,
        actualizadoEn: ahora,
      );

      await referencia.set(definitivo.toJson());

      return ApiResponse.exito(definitivo,
          message: 'Producto guardado en Cloud Firestore',
          statusCode: ApiContract.httpCreated);
    } on FirebaseException catch (e) {
      return ApiResponse.error(
        'Error de Firestore al guardar: ${e.message ?? e.code}',
        statusCode: ApiContract.httpServiceUnavailable,
      );
    } catch (e) {
      return ApiResponse.error('Error al guardar el producto: $e');
    }
  }

  /// Actualiza un producto existente.
  ///
  /// Usa `merge` para no borrar campos que esta version no conozca.
  Future<ApiResponse<ProductoModel>> actualizarProducto(
      String id, ProductoModel producto) async {
    try {
      final actualizado = producto.copyWith(
        id: id,
        actualizadoEn: DateTime.now().millisecondsSinceEpoch,
      );

      await _productos.doc(id).set(actualizado.toJson(), SetOptions(merge: true));

      return ApiResponse.exito(actualizado,
          message: 'Producto actualizado en Cloud Firestore');
    } catch (e) {
      return ApiResponse.error('Error al actualizar el producto: $e');
    }
  }

  /// Elimina un producto.
  Future<ApiResponse<bool>> eliminarProducto(String id) async {
    try {
      await _productos.doc(id).delete();
      return ApiResponse.exito(true, message: 'Producto eliminado');
    } catch (e) {
      return ApiResponse.error('Error al eliminar el producto: $e');
    }
  }

  /// Busca productos por nombre.
  ///
  /// Firestore no permite buscar texto dentro de un campo, asi que se usa un
  /// rango de prefijo: el caracter `` es el ultimo del rango Unicode y
  /// sirve de tope superior. Esto encuentra los nombres que EMPIEZAN con la
  /// consulta, no los que la contienen en medio.
  Future<ApiResponse<List<ProductoModel>>> buscarProductos(
      String consulta) async {
    final texto = consulta.trim();
    if (texto.isEmpty) return obtenerProductos();

    try {
      final snapshot = await _productos
          .orderBy('nombre')
          .startAt([texto])
          .endAt(['$texto'])
          .get();

      final lista = snapshot.docs
          .map((doc) => ProductoModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList();

      return ApiResponse.exito(lista, message: 'Busqueda completada');
    } catch (e) {
      return ApiResponse.error('Error en la busqueda: $e');
    }
  }

  /// Trae los productos de una categoria.
  Future<ApiResponse<List<ProductoModel>>> productosPorCategoria(
      String categoria) async {
    try {
      final snapshot = await _productos
          .where('categoria', isEqualTo: categoria)
          .get();

      final lista = snapshot.docs
          .map((doc) => ProductoModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));

      return ApiResponse.exito(lista);
    } catch (e) {
      return ApiResponse.error('Error al filtrar por categoria: $e');
    }
  }

  // ================================================================
  // USUARIOS
  // ================================================================

  /// Crea o actualiza el documento del usuario.
  Future<ApiResponse<UsuarioModel>> guardarUsuario(UsuarioModel usuario) async {
    try {
      if (usuario.uid.isEmpty) {
        return ApiResponse.error('El usuario no tiene UID',
            statusCode: ApiContract.httpBadRequest);
      }

      final ahora = DateTime.now().millisecondsSinceEpoch;
      final definitivo = usuario.copyWith(
        creadoEn: usuario.creadoEn == 0 ? ahora : usuario.creadoEn,
      );

      await _usuarios
          .doc(usuario.uid)
          .set(definitivo.toJson(), SetOptions(merge: true));

      return ApiResponse.exito(definitivo, message: 'Usuario guardado');
    } catch (e) {
      return ApiResponse.error('Error al guardar el usuario: $e');
    }
  }

  /// Trae el documento de un usuario por su UID.
  Future<ApiResponse<UsuarioModel>> obtenerUsuario(String uid) async {
    try {
      final doc = await _usuarios.doc(uid).get();
      if (!doc.exists || doc.data() == null) {
        return ApiResponse.error('El usuario no esta registrado en Firestore',
            statusCode: ApiContract.httpNotFound);
      }
      return ApiResponse.exito(
        UsuarioModel.fromJson({...doc.data()!, 'uid': doc.id}),
      );
    } catch (e) {
      return ApiResponse.error('Error al cargar el usuario: $e');
    }
  }

  // ================================================================
  // PEDIDOS
  // ================================================================

  /// Guarda un pedido en `usuarios/{uid}/pedidos`.
  Future<ApiResponse<PedidoModel>> crearPedido(
      String uid, PedidoModel pedido) async {
    try {
      if (uid.isEmpty) {
        return ApiResponse.error('No hay sesion iniciada',
            statusCode: ApiContract.httpUnauthorized);
      }
      if (pedido.items.isEmpty) {
        return ApiResponse.error('El pedido no tiene productos',
            statusCode: ApiContract.httpBadRequest);
      }

      final referencia = pedido.id.isNotEmpty
          ? _pedidosDe(uid).doc(pedido.id)
          : _pedidosDe(uid).doc();

      final definitivo = pedido.copyWith(
        id: referencia.id,
        fecha: pedido.fecha == 0
            ? DateTime.now().millisecondsSinceEpoch
            : pedido.fecha,
      );

      await referencia.set(definitivo.toJson());

      return ApiResponse.exito(definitivo,
          message: 'Pedido registrado',
          statusCode: ApiContract.httpCreated);
    } catch (e) {
      return ApiResponse.error('Error al registrar el pedido: $e');
    }
  }

  /// Trae los pedidos de un usuario, del mas reciente al mas antiguo.
  Future<ApiResponse<List<PedidoModel>>> obtenerPedidos(String uid) async {
    try {
      if (uid.isEmpty) {
        return ApiResponse.error('No hay sesion iniciada',
            statusCode: ApiContract.httpUnauthorized);
      }

      final snapshot =
          await _pedidosDe(uid).orderBy('fecha', descending: true).get();

      final lista = snapshot.docs
          .map((doc) => PedidoModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList();

      return ApiResponse.exito(lista, message: 'Pedidos cargados');
    } catch (e) {
      return ApiResponse.error('Error al cargar los pedidos: $e');
    }
  }

  /// Escucha los pedidos de un usuario en tiempo real.
  Stream<List<PedidoModel>> escucharPedidos(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return _pedidosDe(uid)
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PedidoModel.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }
}
