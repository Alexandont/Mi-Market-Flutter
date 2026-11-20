import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/pedido_model.dart';
import '../models/producto_model.dart';
import '../models/usuario_model.dart';
import 'api_contract.dart';

/// Cliente HTTP del servidor REST local de Mi Market.
///
/// Implementa las operaciones CRUD contra `http://localhost:3000/api/v1/`.
/// Todos los metodos devuelven `null` o una lista vacia si el servidor no
/// responde, porque la aplicacion esta disenada para seguir funcionando solo
/// con Firebase cuando el servidor local no esta levantado.
class ApiService {
  final http.Client _cliente;
  final Future<String?> Function() _proveedorToken;

  /// [proveedorToken] permite probar el cliente sin credenciales reales.
  /// En la app normal se obtiene el ID token del usuario Firebase activo.
  ApiService({http.Client? cliente, Future<String?> Function()? proveedorToken})
    : _cliente = cliente ?? http.Client(),
      _proveedorToken = proveedorToken ?? _tokenFirebaseActual;

  static Future<String?> _tokenFirebaseActual() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      // Sin Firebase disponible o sin sesion: la consulta REST es opcional.
      return null;
    }
  }

  static const Duration _limite = Duration(seconds: 5);

  Map<String, String> get _cabeceras => {
    'Content-Type': 'application/json; charset=UTF-8',
    'Accept': 'application/json',
  };

  /// No envia solicitudes de lectura REST si no hay sesion autentificada.
  Future<Map<String, String>?> _cabecerasLecturaAutenticada() async {
    String? token;
    try {
      token = (await _proveedorToken().timeout(_limite))?.trim();
    } catch (_) {
      return null;
    }
    if (token == null || token.isEmpty) return null;
    return <String, String>{..._cabeceras, 'Authorization': 'Bearer $token'};
  }

  bool _esExito(int codigo) => codigo >= 200 && codigo <= 299;

  Uri _url(String endpoint) => Uri.parse('${ApiContract.baseUrl}$endpoint');

  // ================================================================
  // USUARIOS
  // ================================================================

  /// `POST usuarios/login`
  Future<UsuarioModel?> login(String email, String clave) async {
    try {
      final respuesta = await _cliente
          .post(
            _url(ApiContract.endpointLogin),
            headers: _cabeceras,
            body: jsonEncode({'email': email, 'clave': clave}),
          )
          .timeout(_limite);

      if (_esExito(respuesta.statusCode)) {
        final cuerpo = jsonDecode(respuesta.body);
        return UsuarioModel.fromJson(Map<String, dynamic>.from(cuerpo));
      }
    } catch (_) {
      // El servidor local no esta disponible: Firebase se encarga.
    }
    return null;
  }

  // ================================================================
  // PRODUCTOS
  // ================================================================

  /// `GET productos`
  Future<List<ProductoModel>> obtenerProductos() async {
    try {
      final cabeceras = await _cabecerasLecturaAutenticada();
      if (cabeceras == null) return [];
      final respuesta = await _cliente
          .get(_url(ApiContract.endpointProductos), headers: cabeceras)
          .timeout(_limite);

      if (_esExito(respuesta.statusCode)) {
        final cuerpo = jsonDecode(respuesta.body);
        if (cuerpo is List) {
          return cuerpo
              .whereType<Map>()
              .map((e) => ProductoModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// `POST productos`
  Future<ProductoModel?> crearProducto(ProductoModel producto) async {
    try {
      final respuesta = await _cliente
          .post(
            _url(ApiContract.endpointProductos),
            headers: _cabeceras,
            body: jsonEncode(producto.toJson()),
          )
          .timeout(_limite);

      if (_esExito(respuesta.statusCode)) {
        final cuerpo = jsonDecode(respuesta.body);
        return ProductoModel.fromJson(Map<String, dynamic>.from(cuerpo));
      }
    } catch (_) {}
    return null;
  }

  /// `PUT productos/{id}`
  Future<ProductoModel?> actualizarProducto(
    String id,
    ProductoModel producto,
  ) async {
    try {
      final respuesta = await _cliente
          .put(
            _url('${ApiContract.endpointProductos}/$id'),
            headers: _cabeceras,
            body: jsonEncode(producto.toJson()),
          )
          .timeout(_limite);

      if (_esExito(respuesta.statusCode)) {
        final cuerpo = jsonDecode(respuesta.body);
        return ProductoModel.fromJson(Map<String, dynamic>.from(cuerpo));
      }
    } catch (_) {}
    return null;
  }

  /// `DELETE productos/{id}`
  Future<bool> eliminarProducto(String id) async {
    try {
      final respuesta = await _cliente
          .delete(
            _url('${ApiContract.endpointProductos}/$id'),
            headers: _cabeceras,
          )
          .timeout(_limite);
      return _esExito(respuesta.statusCode);
    } catch (_) {}
    return false;
  }

  /// `GET productos/buscar?q=...`
  Future<List<ProductoModel>> buscarProductos(String consulta) async {
    try {
      final url = Uri.parse(
        '${ApiContract.baseUrl}${ApiContract.endpointProductosBuscar}'
        '?q=${Uri.encodeQueryComponent(consulta)}',
      );

      final cabeceras = await _cabecerasLecturaAutenticada();
      if (cabeceras == null) return [];
      final respuesta = await _cliente
          .get(url, headers: cabeceras)
          .timeout(_limite);

      if (_esExito(respuesta.statusCode)) {
        final cuerpo = jsonDecode(respuesta.body);
        if (cuerpo is List) {
          return cuerpo
              .whereType<Map>()
              .map((e) => ProductoModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  // ================================================================
  // PEDIDOS
  // ================================================================

  /// `POST pedidos`
  Future<PedidoModel?> crearPedido(PedidoModel pedido) async {
    try {
      final respuesta = await _cliente
          .post(
            _url(ApiContract.endpointPedidos),
            headers: _cabeceras,
            body: jsonEncode(pedido.toJson()),
          )
          .timeout(_limite);

      if (_esExito(respuesta.statusCode)) {
        final cuerpo = jsonDecode(respuesta.body);
        return PedidoModel.fromJson(Map<String, dynamic>.from(cuerpo));
      }
    } catch (_) {}
    return null;
  }

  /// `GET pedidos`
  Future<List<PedidoModel>> obtenerPedidos() async {
    try {
      final respuesta = await _cliente
          .get(_url(ApiContract.endpointPedidos), headers: _cabeceras)
          .timeout(_limite);

      if (_esExito(respuesta.statusCode)) {
        final cuerpo = jsonDecode(respuesta.body);
        if (cuerpo is List) {
          return cuerpo
              .whereType<Map>()
              .map((e) => PedidoModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Cierra el cliente HTTP.
  void cerrar() => _cliente.close();
}
