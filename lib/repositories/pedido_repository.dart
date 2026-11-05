import '../firebase/firebase_auth_manager.dart';
import '../firebase/firestore_repository.dart';
import '../models/carrito_provider.dart';
import '../models/pedido_model.dart';
import '../network/api_response.dart';
import '../network/api_service.dart';

/// Repositorio de pedidos.
///
/// Convierte el carrito en un pedido y lo guarda en
/// `usuarios/{uid}/pedidos`, la misma ruta que usa la aplicacion Kotlin.
class PedidoRepository {
  final ApiService _api;
  final FirestoreRepository _firestore;
  final FirebaseAuthManager _auth;
  final CarritoProvider _carrito;

  PedidoRepository({
    ApiService? api,
    FirestoreRepository? firestore,
    FirebaseAuthManager? auth,
    CarritoProvider? carrito,
  })  : _api = api ?? ApiService(),
        _firestore = firestore ?? FirestoreRepository(),
        _auth = auth ?? FirebaseAuthManager(),
        _carrito = carrito ?? CarritoProvider();

  /// Confirma el carrito actual como un pedido nuevo.
  ///
  /// Vacia el carrito solo si el pedido se guardo bien: si falla, el usuario
  /// conserva lo que habia elegido y puede reintentar.
  Future<ApiResponse<PedidoModel>> confirmarCarrito({
    required String direccionEntrega,
    double? latEntrega,
    double? lngEntrega,
  }) async {
    final uid = _auth.uidActual;
    if (uid.isEmpty) {
      return ApiResponse.error('Debe iniciar sesion para hacer un pedido',
          statusCode: 401);
    }
    if (_carrito.estaVacio) {
      return ApiResponse.error('El carrito esta vacio', statusCode: 400);
    }
    if (direccionEntrega.trim().isEmpty) {
      return ApiResponse.error('Indique una direccion de entrega',
          statusCode: 400);
    }

    final pedido = PedidoModel(
      items: _carrito.aItemsPedido(),
      total: _carrito.total,
      direccionEntrega: direccionEntrega.trim(),
      latEntrega: latEntrega,
      lngEntrega: lngEntrega,
      estado: PedidoModel.estadoRegistrado,
      fecha: DateTime.now().millisecondsSinceEpoch,
    );

    final guardado = await _firestore.crearPedido(uid, pedido);
    if (!guardado.isSuccess || guardado.data == null) return guardado;

    await _api.crearPedido(guardado.data!);
    _carrito.vaciar();

    return ApiResponse.exito(guardado.data!,
        message: 'Pedido registrado correctamente', statusCode: 201);
  }

  /// Historial de pedidos del usuario actual.
  Future<ApiResponse<List<PedidoModel>>> obtenerPedidos() async {
    final uid = _auth.uidActual;
    if (uid.isEmpty) {
      return ApiResponse.error('No hay sesion iniciada', statusCode: 401);
    }
    return _firestore.obtenerPedidos(uid);
  }

  /// Escucha el historial de pedidos en tiempo real.
  Stream<List<PedidoModel>> escucharPedidos() {
    final uid = _auth.uidActual;
    if (uid.isEmpty) return Stream.value(const []);
    return _firestore.escucharPedidos(uid);
  }
}
