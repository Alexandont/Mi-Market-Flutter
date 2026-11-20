// La version web no importa dart:io ni path_provider.
export 'imagen_producto_offline_web.dart'
    if (dart.library.io) 'imagen_producto_offline_io.dart';
