import 'api_contract.dart';

/// Envoltorio generico de respuestas para peticiones a servicios REST o Firebase.
///
/// Unifica el manejo de datos, errores, mensajes y codigos HTTP en toda la
/// aplicacion, de modo que las pantallas no necesitan saber de donde vino el
/// dato.
///
/// [T] es el tipo contenido en la respuesta, por ejemplo `List<ProductoModel>`.
class ApiResponse<T> {
  /// Datos devueltos por la operacion cuando resulto exitosa.
  final T? data;

  /// Codigo de respuesta HTTP asociado.
  final int statusCode;

  /// Mensaje descriptivo del resultado.
  final String? message;

  /// Indica si la peticion se proceso con exito (codigos 200 a 299).
  final bool isSuccess;

  ApiResponse({
    this.data,
    this.statusCode = ApiContract.httpOk,
    this.message,
    bool? isSuccess,
  }) : isSuccess = isSuccess ?? (statusCode >= 200 && statusCode <= 299);

  /// Crea una respuesta de exito.
  factory ApiResponse.exito(T? data, {String? message, int statusCode = 200}) {
    return ApiResponse<T>(
      data: data,
      statusCode: statusCode,
      message: message,
      isSuccess: true,
    );
  }

  /// Crea una respuesta de error.
  factory ApiResponse.error(String message, {int statusCode = 503}) {
    return ApiResponse<T>(
      data: null,
      statusCode: statusCode,
      message: message,
      isSuccess: false,
    );
  }
}
