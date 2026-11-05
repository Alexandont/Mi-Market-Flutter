import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../network/api_contract.dart';
import '../network/api_response.dart';

/// Resultado de subir una foto: la URL publica y la ruta interna del archivo.
///
/// La ruta se guarda junto al producto porque es lo unico que permite borrar
/// despues el archivo de Storage.
class FotoSubida {
  final String url;
  final String ruta;

  FotoSubida({required this.url, required this.ruta});
}

/// Gestiona las fotos de productos en Firebase Storage.
///
/// Guarda los archivos en `productos/{uid}/...`, la misma carpeta que usa la
/// aplicacion nativa en Kotlin.
class FirebaseStorageManager {
  final FirebaseStorage _storage;

  FirebaseStorageManager({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Sube la foto de un producto y devuelve su URL y su ruta.
  ///
  /// Usa `putData` con los bytes del archivo en lugar de `putFile`, porque
  /// `putFile` no funciona cuando la aplicacion corre en el navegador.
  Future<ApiResponse<FotoSubida>> subirFotoProducto(
      XFile archivo, String uidUsuario) async {
    try {
      final marca = DateTime.now().millisecondsSinceEpoch;
      final ruta = '${ApiContract.carpetaFotosProductos}/$uidUsuario/$marca.jpg';

      final bytes = await archivo.readAsBytes();
      final referencia = _storage.ref().child(ruta);
      final metadatos = SettableMetadata(contentType: 'image/jpeg');

      await referencia.putData(bytes, metadatos);
      final url = await referencia.getDownloadURL();

      return ApiResponse.exito(
        FotoSubida(url: url, ruta: ruta),
        message: 'Foto subida a Firebase Storage',
        statusCode: ApiContract.httpCreated,
      );
    } on FirebaseException catch (e) {
      return ApiResponse.error(
        'No se pudo subir la foto: ${e.message ?? e.code}',
        statusCode: ApiContract.httpServiceUnavailable,
      );
    } catch (e) {
      return ApiResponse.error('No se pudo subir la foto: $e');
    }
  }

  /// Borra un archivo de Storage por su ruta.
  ///
  /// Si el archivo ya no existe, lo considera un exito: el objetivo es que no
  /// quede, y no queda.
  Future<ApiResponse<bool>> eliminarArchivo(String ruta) async {
    if (ruta.trim().isEmpty) {
      return ApiResponse.exito(true, message: 'No habia archivo que borrar');
    }
    try {
      await _storage.ref().child(ruta).delete();
      return ApiResponse.exito(true, message: 'Archivo eliminado');
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        return ApiResponse.exito(true, message: 'El archivo ya no existia');
      }
      return ApiResponse.error(
        'No se pudo eliminar el archivo: ${e.message ?? e.code}',
      );
    } catch (e) {
      return ApiResponse.error('No se pudo eliminar el archivo: $e');
    }
  }
}
