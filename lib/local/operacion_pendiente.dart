import 'dart:convert';

/// Registro durable de una escritura que todavia no se confirmo en Firebase.
/// La sincronizacion futura debe procesar 'sequence' en orden ascendente.
class OperacionPendiente {
  const OperacionPendiente({
    required this.secuencia,
    required this.idOperacion,
    required this.uid,
    required this.entidad,
    required this.idEntidad,
    required this.accion,
    required this.payload,
    required this.fechaCreacion,
    required this.intentos,
    this.ultimoError,
  });

  final int secuencia;
  final String idOperacion;
  final String uid;
  final String entidad;
  final String idEntidad;
  final String accion;
  final Map<String, dynamic>? payload;
  final int fechaCreacion;
  final int intentos;
  final String? ultimoError;

  factory OperacionPendiente.fromRow(Map<String, Object?> row) {
    final json = row['payload'] as String?;
    return OperacionPendiente(
      secuencia: row['sequence'] as int,
      idOperacion: row['operation_id'] as String,
      uid: row['owner_uid'] as String,
      entidad: row['entity_type'] as String,
      idEntidad: row['entity_id'] as String,
      accion: row['action'] as String,
      payload: json == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(json) as Map),
      fechaCreacion: row['created_at'] as int,
      intentos: row['attempts'] as int,
      ultimoError: row['last_error'] as String?,
    );
  }
}
