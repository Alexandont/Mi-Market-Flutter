import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../local/imagenes_producto_locales.dart';

/// Mantiene las mismas dimensiones visuales del catalogo original.
/// Android: muestra archivo local si esta disponible, descarga una copia
/// persistente cuando hay red; web: conserva el comportamiento Image.network.
class ImagenProductoOffline extends StatefulWidget {
  const ImagenProductoOffline({
    super.key,
    required this.uid,
    required this.productoId,
    required this.imagenUrl,
    this.fit = BoxFit.cover,
    this.almacen,
  });

  final String uid;
  final String productoId;
  final String imagenUrl;
  final BoxFit fit;
  final ImagenesProductoLocales? almacen;

  @override
  State<ImagenProductoOffline> createState() => _ImagenProductoOfflineState();
}

class _ImagenProductoOfflineState extends State<ImagenProductoOffline> {
  late Future<File?> _imagen;

  @override
  void initState() {
    super.initState();
    _imagen = _resolver();
  }

  @override
  void didUpdateWidget(covariant ImagenProductoOffline anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.uid != widget.uid ||
        anterior.productoId != widget.productoId ||
        anterior.imagenUrl != widget.imagenUrl ||
        anterior.almacen != widget.almacen) {
      _imagen = _resolver();
    }
  }

  Future<File?> _resolver() async {
    if (kIsWeb || widget.uid.isEmpty || widget.productoId.isEmpty) {
      return null;
    }
    try {
      final almacen =
          widget.almacen ?? await ImagenesProductoLocales.compartida();
      final local = await almacen.buscarLocal(
        widget.uid,
        widget.productoId,
        widget.imagenUrl,
      );
      if (local != null) return local;
      if (widget.imagenUrl.isEmpty) return null;
      return await almacen.descargarRemota(
        widget.uid,
        widget.productoId,
        widget.imagenUrl,
      );
    } catch (_) {
      // Nunca impedir la visualizacion del catalogo por un fallo de imagen.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return widget.imagenUrl.isEmpty
          ? _marcador(context)
          : Image.network(
              widget.imagenUrl,
              fit: widget.fit,
              errorBuilder: (_, _, _) => _marcador(context),
            );
    }
    return FutureBuilder<File?>(
      future: _imagen,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(
            snapshot.data!,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _marcador(context),
          );
        }
        return _marcador(context);
      },
    );
  }

  Widget _marcador(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Icon(Icons.image_not_supported_outlined),
  );
}
