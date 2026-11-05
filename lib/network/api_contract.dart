import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Contrato de la API REST local de Mi Market.
///
/// Define la URL base del servidor y los nombres de las colecciones de Cloud
/// Firestore que comparte con la aplicacion nativa en Kotlin.
class ApiContract {
  /// URL base segun la plataforma de ejecucion.
  ///
  /// Dentro del emulador de Android, `localhost` apunta al propio emulador, por
  /// eso se usa `10.0.2.2`, que es el alias de la maquina anfitriona.
  static String get baseUrl {
    if (kIsWeb) {
      return "http://localhost:3000/api/v1/";
    }
    try {
      if (Platform.isAndroid) {
        return "http://10.0.2.2:3000/api/v1/";
      }
    } catch (_) {}
    return "http://localhost:3000/api/v1/";
  }

  // Endpoints de la API REST
  static const String endpointLogin = "usuarios/login";
  static const String endpointUsuarios = "usuarios";
  static const String endpointProductos = "productos";
  static const String endpointProductosBuscar = "productos/buscar";
  static const String endpointPedidos = "pedidos";

  // Colecciones de Cloud Firestore.
  // Deben coincidir con las de la aplicacion Kotlin para que ambas lean los
  // mismos documentos.
  static const String coleccionProductos = "productos";
  static const String coleccionTiendas = "tiendas";
  static const String coleccionUsuarios = "usuarios";
  static const String coleccionPedidos = "pedidos";

  /// Carpeta de Firebase Storage donde se guardan las fotos de productos.
  static const String carpetaFotosProductos = "productos";

  // Codigos de respuesta HTTP evaluados por la aplicacion
  static const int httpOk = 200;
  static const int httpCreated = 201;
  static const int httpNoContent = 204;
  static const int httpBadRequest = 400;
  static const int httpUnauthorized = 401;
  static const int httpNotFound = 404;
  static const int httpInternalError = 500;
  static const int httpServiceUnavailable = 503;
}
