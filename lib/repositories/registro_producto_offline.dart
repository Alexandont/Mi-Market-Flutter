import 'package:image_picker/image_picker.dart';

import '../models/producto_model.dart';
import 'registro_producto_offline_stub.dart'
    if (dart.library.io) 'registro_producto_offline_io.dart'
    as plataforma;

/// Entrada multiplataforma. Solo se invoca para Android/iOS.
/// En web y escritorio se conserva el flujo remoto anterior del repositorio.
Future<ProductoModel> registrarProductoLocal(
  String uid,
  ProductoModel producto,
  XFile? fotografia,
) => plataforma.registrarProductoLocal(uid, producto, fotografia);
