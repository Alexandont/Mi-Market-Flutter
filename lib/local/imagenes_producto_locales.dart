import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Copias persistentes de fotografias por usuario y producto.
/// Las fotografias NUEVAS se conservan hasta que una etapa posterior confirme
/// que Firebase Storage y Firestore las recibieron correctamente.
class ImagenesProductoLocales {
  ImagenesProductoLocales({required Directory raiz, http.Client? cliente})
    : this._(raiz, cliente);

  ImagenesProductoLocales._(this._raiz, http.Client? cliente)
    : _cliente = cliente ?? http.Client();

  final Directory _raiz;
  final http.Client _cliente;
  final Map<String, Future<File>> _descargasActivas = {};
  static const int limiteBytes = 12 * 1024 * 1024;
  static const _uuid = Uuid();

  static Future<ImagenesProductoLocales>? _compartida;

  /// Carpeta de documentos internos; no usar getTemporaryDirectory().
  static Future<ImagenesProductoLocales> compartida() =>
      _compartida ??= abrir();

  static Future<ImagenesProductoLocales> abrir() async {
    final documentos = await getApplicationDocumentsDirectory();
    final raiz = Directory(path.join(documentos.path, 'mimarket', 'imagenes'));
    await raiz.create(recursive: true);
    return ImagenesProductoLocales(raiz: raiz);
  }

  static String _hash(String texto) =>
      sha256.convert(texto.codeUnits).toString();

  void _validar(String uid, String productoId) {
    if (uid.trim().isEmpty || productoId.trim().isEmpty) {
      throw ArgumentError('UID e identificador de producto son obligatorios');
    }
  }

  Directory _carpeta(String uid, String productoId) =>
      Directory(path.join(_raiz.path, _hash(uid), _hash(productoId)));

  File _archivoRemoto(String uid, String productoId, String url) => File(
    path.join(_carpeta(uid, productoId).path, 'remota_${_hash(url)}.img'),
  );

  /// Guarda una copia de la foto seleccionada FUERA de la cache del picker.
  /// Es deliberado conservar las versiones anteriores hasta que se integre
  /// el tratamiento transaccional de reemplazos y el ACK remoto.
  Future<File> guardarSeleccionada(
    String uid,
    String productoId,
    XFile imagen,
  ) async {
    _validar(uid, productoId);
    final bytes = await imagen.readAsBytes();
    if (bytes.isEmpty || bytes.length > limiteBytes) {
      throw StateError('Imagen vacia o mayor a 12 MB');
    }
    final carpeta = _carpeta(uid, productoId);
    await carpeta.create(recursive: true);
    final nombre =
        'seleccionada_${DateTime.now().microsecondsSinceEpoch}_${_uuid.v4()}.img';
    final archivo = File(path.join(carpeta.path, nombre));
    await _escribirSeguro(archivo, bytes);
    return archivo;
  }

  /// Busca la ultima foto escogida (si existe) sin contactar a Firebase.
  Future<File?> buscarSeleccionada(String uid, String productoId) async {
    _validar(uid, productoId);
    final carpeta = _carpeta(uid, productoId);
    if (!await carpeta.exists()) return null;
    final archivos = await carpeta
        .list(followLinks: false)
        .where(
          (e) =>
              e is File &&
              path.basename(e.path).startsWith('seleccionada_') &&
              path.extension(e.path) == '.img',
        )
        .cast<File>()
        .toList();
    if (archivos.isEmpty) return null;
    archivos.sort(
      (a, b) => path.basename(b.path).compareTo(path.basename(a.path)),
    );
    for (final archivo in archivos) {
      if (await archivo.length() > 0) return archivo;
    }
    return null;
  }

  /// Solo consulta el almacenamiento; no hace ninguna peticion de red.
  Future<File?> buscarRemota(String uid, String productoId, String url) async {
    _validar(uid, productoId);
    if (url.trim().isEmpty) return null;
    final f = _archivoRemoto(uid, productoId, url);
    return await f.exists() && await f.length() > 0 ? f : null;
  }

  /// Prefiere la seleccion local (una modificacion que aun puede estar pendiente).
  Future<File?> buscarLocal(String uid, String productoId, String url) async {
    return await buscarSeleccionada(uid, productoId) ??
        await buscarRemota(uid, productoId, url);
  }

  /// Descarga la foto desde Firebase Storage una sola vez por URL.
  /// Una falla nunca borra la copia persistente que ya estuviera guardada.
  Future<File> descargarRemota(
    String uid,
    String productoId,
    String url,
  ) async {
    _validar(uid, productoId);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(url, 'url', 'La URL debe ser HTTP(S)');
    }
    final previo = await buscarRemota(uid, productoId, url);
    if (previo != null) return previo;
    final destino = _archivoRemoto(uid, productoId, url);
    return _descargasActivas.putIfAbsent(destino.path, () async {
      try {
        final revalidado = await buscarRemota(uid, productoId, url);
        if (revalidado != null) return revalidado;
        final respuesta = await _cliente
            .send(http.Request('GET', uri))
            .timeout(const Duration(seconds: 15));
        if (respuesta.statusCode != 200) {
          throw HttpException(
            'Descarga de imagen: HTTP ${respuesta.statusCode}',
          );
        }
        final tipo = respuesta.headers['content-type']?.toLowerCase();
        if (tipo != null && !tipo.startsWith('image/')) {
          throw const FormatException('El servidor no devolvio una imagen');
        }
        final bytes = <int>[];
        await for (final bloque in respuesta.stream.timeout(
          const Duration(seconds: 15),
        )) {
          bytes.addAll(bloque);
          if (bytes.length > limiteBytes) {
            throw StateError('La imagen remota supera 12 MB');
          }
        }
        if (bytes.isEmpty) throw StateError('Imagen remota vacia');
        await _escribirSeguro(destino, bytes);
        return destino;
      } finally {
        _descargasActivas.remove(destino.path);
      }
    });
  }

  Future<void> _escribirSeguro(File destino, List<int> bytes) async {
    await destino.parent.create(recursive: true);
    final temporal = File('${destino.path}.${_uuid.v4()}.tmp');
    try {
      await temporal.writeAsBytes(bytes, flush: true);
      // Los nombres son inmutables por ID de seleccion o hash de URL.
      if (!await destino.exists()) {
        await temporal.rename(destino.path);
      }
    } finally {
      if (await temporal.exists()) await temporal.delete();
    }
  }

  /// Solo se llama en servicios de corta vida/tests; no cerrar la compartida.
  @visibleForTesting
  void cerrarCliente() => _cliente.close();
}
