import 'package:image_picker/image_picker.dart';

import '../models/producto_model.dart';

Future<ProductoModel> registrarProductoLocal(
  String uid,
  ProductoModel producto,
  XFile? fotografia,
) => Future.error(
  UnsupportedError(
    'El registro local de este paquete solo esta habilitado en Android/iOS',
  ),
);
