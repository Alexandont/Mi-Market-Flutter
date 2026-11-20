import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../local/imagenes_producto_locales.dart';
import '../local/local_database.dart';
import '../local/operacion_pendiente.dart';
import '../network/api_contract.dart';
import 'firebase_sync_gateway.dart';

/// Resultado remoto estable, independientemente de cuantos reintentos ocurran.
class FotoProductoSincronizada {
  const FotoProductoSincronizada({required this.url, required this.ruta});

  final String url;
  final String ruta;
}

/// Interfaz inyectable para probar reintentos sin Firebase real.
abstract class SubidorFotoProducto {
  Future<FotoProductoSincronizada> subir({
    required String uid,
    required String productoId,
    required File archivo,
  });
}

/// Subida remota con ruta *determinista* por usuario y producto.
///
/// Si un reintento ocurre despues de subir la foto pero antes del ACK de
/// Firestore, se sobrescribe el mismo objeto, no se crea otro.
class FirebaseSubidorFotoProducto implements SubidorFotoProducto {
  FirebaseSubidorFotoProducto({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<FotoProductoSincronizada> subir({
    required String uid,
    required String productoId,
    required File archivo,
  }) async {
    if (uid.trim().isEmpty || productoId.trim().isEmpty) {
      throw ArgumentError('UID e ID del producto son obligatorios');
    }
    final bytes = await archivo.readAsBytes();
    if (bytes.isEmpty || bytes.length > ImagenesProductoLocales.limiteBytes) {
      throw StateError('Fotografia vacia o mayor a 12 MB');
    }

    // El selector normalmente entrega JPEG, pero se reconocen tambien PNG/WebP.
    final String extension;
    final String mime;
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      extension = 'jpg';
      mime = 'image/jpeg';
    } else if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      extension = 'png';
      mime = 'image/png';
    } else if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      extension = 'webp';
      mime = 'image/webp';
    } else {
      throw const FormatException('Formato de fotografia no compatible');
    }

    final ruta =
        '${ApiContract.carpetaFotosProductos}/$uid/$productoId.$extension';
    final referencia = _storage.ref().child(ruta);
    await referencia.putData(bytes, SettableMetadata(contentType: mime));
    final url = await referencia.getDownloadURL();
    return FotoProductoSincronizada(url: url, ruta: ruta);
  }
}

/// Procesa imagen+producto como una sola operacion pendiente de outbox.
///
/// 1. Busca fotografia persistente, si existe.
/// 2. Sube imagen (si la hay) con ruta estable.
/// 3. Escribe el documento con la URL en Firestore (mismo productId).
/// 4. Actualiza la copia SQLite SIN generar otra operacion pendiente.
///
/// NO elimina la outbox: eso es responsabilidad de SyncService y sucede
/// solamente despues de que `apply` retorna satisfactoriamente.
///
/// Este gateway se integra con SyncService en la siguiente subetapa; el
/// paquete actual NO inicia sincronizaciones reales.
class ProductoFotoSyncGateway implements RemoteSyncGateway {
  ProductoFotoSyncGateway({
    required this.firestore,
    required this.subidor,
    required this.imagenes,
    required this.baseLocal,
  });

  final RemoteSyncGateway firestore;
  final SubidorFotoProducto subidor;
  final ImagenesProductoLocales imagenes;
  final LocalDatabase baseLocal;

  /// Marcador para nuevos registros: protege contra foto perdida antes del ACK.
  static const String fotoLocalPendiente = 'local:pending';

  @override
  Future<void> apply(OperacionPendiente operacion) async {
    if (operacion.uid.trim().isEmpty || operacion.idEntidad.trim().isEmpty) {
      throw StateError('Operacion sin UID o identificador');
    }
    if (operacion.entidad != 'producto' || operacion.accion != 'upsert') {
      await firestore.apply(operacion);
      return;
    }

    final original = operacion.payload;
    if (original == null) {
      throw StateError('Producto sin datos en la outbox');
    }
    if (original['creadorUid']?.toString() != operacion.uid) {
      throw StateError('La operacion no pertenece al UID autenticado');
    }

    final foto = await imagenes.buscarSeleccionada(
      operacion.uid,
      operacion.idEntidad,
    );

    if (foto == null) {
      // El marcador se incorporara en RegistroProductoLocalService antes de
      // habilitar ejecucion automatica. Impide confirmar sin una foto obligada.
      if (original['imagenRuta'] == fotoLocalPendiente) {
        throw StateError('Fotografia pendiente ausente: no confirmar outbox');
      }
      await firestore.apply(operacion);
      return;
    }

    final subida = await subidor.subir(
      uid: operacion.uid,
      productoId: operacion.idEntidad,
      archivo: foto,
    );
    if (subida.url.trim().isEmpty || subida.ruta.trim().isEmpty) {
      throw StateError('Firebase Storage no confirmo URL y ruta');
    }

    final actualizado = <String, dynamic>{
      ...original,
      'imagenUrl': subida.url,
      'imagenRuta': subida.ruta,
    };

    final conImagen = OperacionPendiente(
      secuencia: operacion.secuencia,
      idOperacion: operacion.idOperacion,
      uid: operacion.uid,
      entidad: operacion.entidad,
      idEntidad: operacion.idEntidad,
      accion: operacion.accion,
      payload: actualizado,
      fechaCreacion: operacion.fechaCreacion,
      intentos: operacion.intentos,
      ultimoError: operacion.ultimoError,
    );

    // Firestore utiliza document.set con el ID original; asi se evitan docs
    // duplicados si este bloque se repite por fallo de red o un ACK perdido.
    await firestore.apply(conImagen);

    // CAS: una escritura posterior o eliminacion local no se sobrescribe.
    // Si SQLite falla, apply falla y la outbox se conserva para reintento.
    await baseLocal.database.rawUpdate(
      '''
      UPDATE productos_local
      SET payload = ?, modified_at = ?
      WHERE owner_uid = ? AND id = ? AND deleted = 0 AND payload = ?
    ''',
      [
        jsonEncode(actualizado),
        DateTime.now().millisecondsSinceEpoch,
        operacion.uid,
        operacion.idEntidad,
        jsonEncode(original),
      ],
    );
  }
}
