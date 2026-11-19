import 'package:cloud_firestore/cloud_firestore.dart';

import '../local/operacion_pendiente.dart';
import '../network/api_contract.dart';

/// Contrato inyectable: permite probar la sincronizacion sin conectarse a Firebase.
abstract class RemoteSyncGateway {
  Future<void> apply(OperacionPendiente operation);
}

/// Escribe en las colecciones Firestore que Mi-Market ya utiliza.
/// Los ID se generan ANTES de la sincronizacion y nunca se reemplazan aqui.
class FirebaseSyncGateway implements RemoteSyncGateway {
  FirebaseSyncGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> apply(OperacionPendiente operation) async {
    if (operation.uid.trim().isEmpty || operation.idEntidad.trim().isEmpty) {
      throw StateError('La operacion no contiene UID e ID validos');
    }

    if (operation.entidad == 'producto') {
      final document = _firestore
          .collection(ApiContract.coleccionProductos)
          .doc(operation.idEntidad);
      switch (operation.accion) {
        case 'upsert':
          final data = operation.payload;
          if (data == null) throw StateError('Producto sin payload');
          // No agrega el ID como campo: el modelo actual lo guarda en doc.id.
          await document.set(data, SetOptions(merge: true));
          return;
        case 'delete':
          await document.delete();
          return;
        default:
          throw UnsupportedError('Accion de producto desconocida');
      }
    }

    if (operation.entidad == 'pedido' && operation.accion == 'upsert') {
      final data = operation.payload;
      if (data == null) throw StateError('Pedido sin payload');
      await _firestore
          .collection(ApiContract.coleccionUsuarios)
          .doc(operation.uid)
          .collection(ApiContract.coleccionPedidos)
          .doc(operation.idEntidad)
          .set(data, SetOptions(merge: true));
      return;
    }

    throw UnsupportedError('Entidad o accion de sincronizacion no soportada');
  }
}
