import '../local/offline_store.dart';
import 'firebase_sync_gateway.dart';

/// Resultado de UN intento de sincronizacion. La sincronizacion automatica
/// al reconectar se conectara a este servicio en la siguiente subetapa.
class SyncReport {
  const SyncReport({
    required this.confirmed,
    required this.remaining,
    this.error,
  });

  final int confirmed;
  final int remaining;
  final String? error;
  bool get complete => remaining == 0 && error == null;
}

/// Consume la outbox SQLite en orden FIFO, sin descartar cambios fallidos.
/// No debe ejecutarse en paralelo ni para una cuenta diferente al usuario
/// Firebase autenticado. El responsable de invocarlo verificara ese UID.
class SyncService {
  SyncService({
    required this.store,
    required this.remote,
    this.operationTimeout = const Duration(seconds: 15),
  });

  final OfflineStore store;
  final RemoteSyncGateway remote;
  final Duration operationTimeout;
  bool _running = false;

  Future<SyncReport> syncNow(String uid) async {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Se requiere usuario autenticado');
    }
    if (_running) {
      throw StateError('Ya hay una sincronizacion en curso');
    }
    _running = true;
    try {
      final pending = await store.operacionesPendientes(uid);
      var confirmed = 0;
      for (final operation in pending) {
        try {
          await remote.apply(operation).timeout(operationTimeout);
          // ACK solamente tras finalizar la escritura remota correctamente.
          await store.confirmarSincronizacion(uid, operation.idOperacion);
          confirmed++;
        } catch (error) {
          // Mantener el orden: no procesar una operacion posterior si
          // una anterior fallo. Guardar diagnostico sin exponer datos de pago.
          final reason = error.runtimeType.toString();
          await store.registrarError(uid, operation.idOperacion, reason);
          final remaining = (await store.operacionesPendientes(uid)).length;
          return SyncReport(
            confirmed: confirmed,
            remaining: remaining,
            error: reason,
          );
        }
      }
      return SyncReport(confirmed: confirmed, remaining: 0);
    } finally {
      _running = false;
    }
  }
}
