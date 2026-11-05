import 'package:firebase_auth/firebase_auth.dart';
import '../models/usuario_model.dart';
import '../network/api_contract.dart';
import '../network/api_response.dart';

/// Gestiona la autenticacion con Firebase Authentication.
///
/// Se encarga de iniciar sesion, registrar usuarios, cerrar sesion y consultar
/// quien es el usuario actual. Todas las operaciones devuelven un
/// [ApiResponse] para que las pantallas manejen el resultado de una sola forma.
class FirebaseAuthManager {
  final FirebaseAuth _auth;

  /// Permite inyectar una instancia distinta de [FirebaseAuth], util en
  /// pruebas unitarias.
  FirebaseAuthManager({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  /// Tiempo maximo de espera de cada operacion contra Firebase.
  static const Duration _limite = Duration(seconds: 10);

  /// Inicia sesion con correo y contrasena.
  Future<ApiResponse<UsuarioModel>> iniciarSesion(
      String email, String clave) async {
    try {
      final credencial = await _auth
          .signInWithEmailAndPassword(
              email: email.trim(), password: clave)
          .timeout(_limite);

      final user = credencial.user;
      if (user == null) {
        return ApiResponse.error(
          'No se pudo obtener el usuario despues de iniciar sesion',
          statusCode: ApiContract.httpUnauthorized,
        );
      }

      return ApiResponse.exito(
        _desdeFirebase(user),
        message: 'Sesion iniciada correctamente',
      );
    } on FirebaseAuthException catch (e) {
      return ApiResponse.error(
        _traducirError(e.code),
        statusCode: ApiContract.httpUnauthorized,
      );
    } catch (e) {
      return ApiResponse.error(
        'No se pudo conectar con Firebase: $e',
        statusCode: ApiContract.httpServiceUnavailable,
      );
    }
  }

  /// Registra un usuario nuevo con correo y contrasena.
  ///
  /// Si se indica [nombre], tambien actualiza el nombre visible del perfil.
  Future<ApiResponse<UsuarioModel>> registrarUsuario(
      String email, String clave,
      [String nombre = '']) async {
    try {
      final credencial = await _auth
          .createUserWithEmailAndPassword(
              email: email.trim(), password: clave)
          .timeout(_limite);

      final user = credencial.user;
      if (user == null) {
        return ApiResponse.error(
          'No se pudo crear la cuenta',
          statusCode: ApiContract.httpBadRequest,
        );
      }

      if (nombre.trim().isNotEmpty) {
        try {
          await user.updateDisplayName(nombre.trim());
          await user.reload();
        } catch (_) {
          // Si falla solo el nombre visible, la cuenta igual quedo creada.
        }
      }

      return ApiResponse.exito(
        _desdeFirebase(_auth.currentUser ?? user, nombreAlterno: nombre),
        message: 'Cuenta creada correctamente',
        statusCode: ApiContract.httpCreated,
      );
    } on FirebaseAuthException catch (e) {
      return ApiResponse.error(
        _traducirError(e.code),
        statusCode: ApiContract.httpBadRequest,
      );
    } catch (e) {
      return ApiResponse.error(
        'No se pudo conectar con Firebase: $e',
        statusCode: ApiContract.httpServiceUnavailable,
      );
    }
  }

  /// Cierra la sesion activa.
  Future<ApiResponse<bool>> cerrarSesion() async {
    try {
      await _auth.signOut();
      return ApiResponse.exito(true, message: 'Sesion cerrada');
    } catch (e) {
      return ApiResponse.error('No se pudo cerrar la sesion: $e');
    }
  }

  /// Indica si hay un usuario con sesion abierta.
  bool estaAutenticado() => _auth.currentUser != null;

  /// UID del usuario actual, o cadena vacia si no hay sesion.
  String get uidActual => _auth.currentUser?.uid ?? '';

  /// Datos del usuario con sesion abierta, o `null` si no hay ninguna.
  UsuarioModel? obtenerUsuarioActual() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _desdeFirebase(user);
  }

  /// Envia un correo para restablecer la contrasena.
  Future<ApiResponse<bool>> recuperarClave(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim()).timeout(_limite);
      return ApiResponse.exito(true,
          message: 'Se envio un correo para restablecer la contrasena');
    } on FirebaseAuthException catch (e) {
      return ApiResponse.error(_traducirError(e.code),
          statusCode: ApiContract.httpBadRequest);
    } catch (e) {
      return ApiResponse.error('No se pudo enviar el correo: $e');
    }
  }

  /// Convierte un [User] de Firebase en el modelo propio de la aplicacion.
  UsuarioModel _desdeFirebase(User user, {String nombreAlterno = ''}) {
    final correo = user.email ?? '';
    final nombre = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (nombreAlterno.trim().isNotEmpty
            ? nombreAlterno.trim()
            : correo.split('@').first);

    return UsuarioModel(
      uid: user.uid,
      nombre: nombre,
      email: correo,
      creadoEn: user.metadata.creationTime?.millisecondsSinceEpoch ?? 0,
    );
  }

  /// Traduce los codigos de error de Firebase a mensajes para el usuario.
  String _traducirError(String codigo) {
    switch (codigo) {
      case 'invalid-email':
        return 'El correo no tiene un formato valido';
      case 'user-disabled':
        return 'Esta cuenta esta deshabilitada';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contrasena incorrectos';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo';
      case 'weak-password':
        return 'La contrasena debe tener al menos 6 caracteres';
      case 'too-many-requests':
        return 'Demasiados intentos. Espere unos minutos';
      case 'network-request-failed':
        return 'Sin conexion a internet';
      case 'operation-not-allowed':
        return 'El inicio de sesion con correo no esta habilitado en Firebase';
      default:
        return 'Error de autenticacion: $codigo';
    }
  }
}
