import 'package:flutter/material.dart';

/// Alternativa para Flutter Web: conserva Image.network sin usar dart:io.
class ImagenProductoOffline extends StatelessWidget {
  const ImagenProductoOffline({
    super.key,
    required this.uid,
    required this.productoId,
    required this.imagenUrl,
    this.fit = BoxFit.cover,
  });

  final String uid;
  final String productoId;
  final String imagenUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fondo = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_not_supported_outlined),
    );
    if (imagenUrl.isEmpty) return fondo;
    return Image.network(
      imagenUrl,
      fit: fit,
      errorBuilder: (_, _, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.image_not_supported_outlined),
      ),
    );
  }
}
