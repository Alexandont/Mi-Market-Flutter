import 'package:image_picker/image_picker.dart';

import '../local/imagenes_producto_locales.dart';
import '../local/local_database_provider.dart';
import '../local/offline_store.dart';
import '../models/producto_model.dart';
import 'registro_producto_local_service.dart';

/// No hace llamadas de red. Guarda imagen persistente y producto+outbox local.
Future<ProductoModel> registrarProductoLocal(
  String uid,
  ProductoModel producto,
  XFile? fotografia,
) async {
  final base = await LocalDatabaseProvider.database;
  final imagenes = await ImagenesProductoLocales.compartida();
  return RegistroProductoLocalService(
    store: OfflineStore(base),
    imagenes: imagenes,
  ).registrar(uid, producto, fotografia: fotografia);
}
