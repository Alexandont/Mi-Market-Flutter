/// Usuario de Mi Market.
///
/// Los campos coinciden con la clase `Usuario` de la aplicacion Kotlin, que
/// guarda estos documentos en la coleccion `usuarios` usando el UID de Firebase
/// Authentication como identificador del documento.
class UsuarioModel {
  static const String rolCliente = 'cliente';
  static const String rolAdmin = 'admin';

  /// UID de Firebase Authentication.
  final String uid;

  final String nombre;
  final String email;

  /// `cliente` o `admin`. Se cambia a mano desde la consola de Firestore.
  final String rol;

  final String direccionEntrega;
  final double? latEntrega;
  final double? lngEntrega;
  final bool aceptoPrivacidad;
  final bool consentimientoUbicacion;

  /// Fecha de creacion en milisegundos desde la epoca.
  final int creadoEn;

  UsuarioModel({
    this.uid = '',
    this.nombre = '',
    this.email = '',
    this.rol = rolCliente,
    this.direccionEntrega = '',
    this.latEntrega,
    this.lngEntrega,
    this.aceptoPrivacidad = false,
    this.consentimientoUbicacion = false,
    this.creadoEn = 0,
  });

  /// Indica si el usuario puede editar o eliminar productos de otros.
  bool get esAdmin => rol == rolAdmin;

  /// Indica si el usuario tiene un punto de entrega definido.
  bool get tieneEntrega => latEntrega != null && lngEntrega != null;

  factory UsuarioModel.fromJson(Map<String, dynamic> json) {
    return UsuarioModel(
      uid: (json['uid'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      rol: (json['rol'] ?? rolCliente).toString(),
      direccionEntrega: (json['direccionEntrega'] ?? '').toString(),
      latEntrega: _aDoubleNulable(json['latEntrega']),
      lngEntrega: _aDoubleNulable(json['lngEntrega']),
      aceptoPrivacidad: json['aceptoPrivacidad'] == true,
      consentimientoUbicacion: json['consentimientoUbicacion'] == true,
      creadoEn: _aInt(json['creadoEn']),
    );
  }

  /// Serializa el perfil para Firestore.
  ///
  /// No incluye `uid`: las reglas usan `hasOnly` y el uid es el nombre del
  /// documento.
  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'email': email,
      'rol': rol,
      'direccionEntrega': direccionEntrega,
      'latEntrega': latEntrega,
      'lngEntrega': lngEntrega,
      'aceptoPrivacidad': aceptoPrivacidad,
      'consentimientoUbicacion': consentimientoUbicacion,
      'creadoEn': creadoEn,
    };
  }

  UsuarioModel copyWith({
    String? uid,
    String? nombre,
    String? email,
    String? rol,
    String? direccionEntrega,
    double? latEntrega,
    double? lngEntrega,
    bool? aceptoPrivacidad,
    bool? consentimientoUbicacion,
    int? creadoEn,
  }) {
    return UsuarioModel(
      uid: uid ?? this.uid,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      rol: rol ?? this.rol,
      direccionEntrega: direccionEntrega ?? this.direccionEntrega,
      latEntrega: latEntrega ?? this.latEntrega,
      lngEntrega: lngEntrega ?? this.lngEntrega,
      aceptoPrivacidad: aceptoPrivacidad ?? this.aceptoPrivacidad,
      consentimientoUbicacion:
          consentimientoUbicacion ?? this.consentimientoUbicacion,
      creadoEn: creadoEn ?? this.creadoEn,
    );
  }

  static double? _aDoubleNulable(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor.toString());
  }

  static int _aInt(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
