import '../firebase/firebase_auth_manager.dart';
import '../firebase/firestore_repository.dart';
import '../models/usuario_model.dart';
import '../network/api_response.dart';

/// Repositorio de usuarios.
///
/// Coordina Firebase Authentication, que maneja las credenciales, con Cloud
/// Firestore, que guarda el perfil: nombre, rol y direccion de entrega.
/// Authentication por si solo no puede guardar esos campos.
class UsuarioRepository {
  final FirebaseAuthManager _auth;
  final FirestoreRepository _firestore;

  UsuarioRepository({
    FirebaseAuthManager? auth,
    FirestoreRepository? firestore,
  })  : _auth = auth ?? FirebaseAuthManager(),
        _firestore = firestore ?? FirestoreRepository();

  /// Inicia sesion y trae el perfil completo desde Firestore.
  ///
  /// Si el documento de Firestore no existe todavia, devuelve los datos
  /// basicos de Authentication en lugar de fallar.
  Future<ApiResponse<UsuarioModel>> iniciarSesion(
      String email, String clave) async {
    final respuesta = await _auth.iniciarSesion(email, clave);
    if (!respuesta.isSuccess || respuesta.data == null) return respuesta;

    final basico = respuesta.data!;
    final perfil = await _firestore.obtenerUsuario(basico.uid);

    if (perfil.isSuccess && perfil.data != null) {
      // El perfil manda, pero el correo de Authentication es el verdadero.
      return ApiResponse.exito(
        perfil.data!.copyWith(email: basico.email),
        message: respuesta.message,
      );
    }

    return ApiResponse.exito(basico, message: respuesta.message);
  }

  /// Registra un usuario y crea su documento en Firestore.
  Future<ApiResponse<UsuarioModel>> registrar(
      String email, String clave, String nombre) async {
    final respuesta = await _auth.registrarUsuario(email, clave, nombre);
    if (!respuesta.isSuccess || respuesta.data == null) return respuesta;

    final usuario = respuesta.data!;
    final guardado = await _firestore.guardarUsuario(usuario);

    // Si Firestore falla, la cuenta ya existe en Authentication y el usuario
    // puede entrar; el perfil se completara despues.
    if (guardado.isSuccess && guardado.data != null) {
      return ApiResponse.exito(guardado.data!,
          message: 'Cuenta creada correctamente', statusCode: 201);
    }

    return ApiResponse.exito(usuario,
        message: 'Cuenta creada, el perfil se guardara mas tarde',
        statusCode: 201);
  }

  /// Cierra la sesion activa.
  Future<ApiResponse<bool>> cerrarSesion() => _auth.cerrarSesion();

  /// Indica si hay sesion abierta. Lo usa `main.dart` para elegir la pantalla
  /// inicial.
  bool estaAutenticado() => _auth.estaAutenticado();

  /// UID del usuario actual, o cadena vacia.
  String get uidActual => _auth.uidActual;

  /// Datos basicos del usuario con sesion abierta.
  UsuarioModel? obtenerUsuarioActual() => _auth.obtenerUsuarioActual();

  /// Perfil completo del usuario actual, leido de Firestore.
  Future<ApiResponse<UsuarioModel>> obtenerPerfilActual() async {
    final uid = _auth.uidActual;
    if (uid.isEmpty) {
      return ApiResponse.error('No hay sesion iniciada', statusCode: 401);
    }

    final perfil = await _firestore.obtenerUsuario(uid);
    if (perfil.isSuccess) return perfil;

    final basico = _auth.obtenerUsuarioActual();
    if (basico != null) return ApiResponse.exito(basico);

    return perfil;
  }

  /// Guarda cambios del perfil, como el nombre o la direccion de entrega.
  Future<ApiResponse<UsuarioModel>> actualizarPerfil(UsuarioModel usuario) {
    return _firestore.guardarUsuario(usuario);
  }

  /// Envia el correo para restablecer la contrasena.
  Future<ApiResponse<bool>> recuperarClave(String email) =>
      _auth.recuperarClave(email);
}
