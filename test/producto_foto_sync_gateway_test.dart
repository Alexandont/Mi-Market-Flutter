import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mimarket_flutter/local/imagenes_producto_locales.dart';
import 'package:mimarket_flutter/local/local_database.dart';
import 'package:mimarket_flutter/local/offline_store.dart';
import 'package:mimarket_flutter/local/operacion_pendiente.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:mimarket_flutter/repositories/registro_producto_local_service.dart';
import 'package:mimarket_flutter/sync/firebase_sync_gateway.dart';
import 'package:mimarket_flutter/sync/producto_foto_sync_gateway.dart';
import 'package:mimarket_flutter/sync/sync_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SubidorDePrueba implements SubidorFotoProducto {
  int llamadas = 0;
  bool falla = false;
  final List<String> rutas = [];

  @override
  Future<FotoProductoSincronizada> subir({
    required String uid,
    required String productoId,
    required File archivo,
  }) async {
    llamadas++;
    if (falla) throw StateError('No hay conexion con Storage');
    if (!await archivo.exists()) throw StateError('No existe foto local');
    final ruta = 'productos/$uid/$productoId.jpg';
    rutas.add(ruta);
    return FotoProductoSincronizada(
      url: 'https://ejemplo.invalid/$uid/$productoId.jpg',
      ruta: ruta,
    );
  }
}

class FirestoreDePrueba implements RemoteSyncGateway {
  bool falla = false;
  final Map<String, Map<String, dynamic>> documentos = {};
  int llamadas = 0;

  @override
  Future<void> apply(OperacionPendiente op) async {
    llamadas++;
    if (falla) throw StateError('No hay conexion con Firestore');
    if (op.entidad == 'producto' && op.accion == 'upsert') {
      documentos[op.idEntidad] = Map<String, dynamic>.from(op.payload!);
    } else if (op.entidad == 'producto' && op.accion == 'delete') {
      documentos.remove(op.idEntidad);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory temporal;
  late LocalDatabase base;
  late OfflineStore store;
  late ImagenesProductoLocales imagenes;
  late SubidorDePrueba subidor;
  late FirestoreDePrueba firestore;
  late SyncService sync;
  late RegistroProductoLocalService registro;

  Future<ProductoModel> crear({bool conFoto = true}) async {
    XFile? foto;
    if (conFoto) {
      final origen = File(path.join(temporal.path, 'foto.jpg'));
      await origen.writeAsBytes([0xff, 0xd8, 0xff, 0xd9], flush: true);
      foto = XFile(origen.path);
    }
    return registro.registrar(
      'usuario-1',
      ProductoModel(
        nombre: 'Torta de chocolate',
        categoria: 'Otros',
        descripcion: 'Prueba',
        precio: 170,
        stock: 10,
      ),
      fotografia: foto,
    );
  }

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('mimarket_foto_sync_');
    base = await LocalDatabase.openWithFactory(
      databaseFactoryFfi,
      path.join(temporal.path, 'db.sqlite'),
    );
    store = OfflineStore(base);
    imagenes = ImagenesProductoLocales(
      raiz: Directory(path.join(temporal.path, 'imagenes')),
    );
    subidor = SubidorDePrueba();
    firestore = FirestoreDePrueba();
    sync = SyncService(
      store: store,
      remote: ProductoFotoSyncGateway(
        firestore: firestore,
        subidor: subidor,
        imagenes: imagenes,
        baseLocal: base,
      ),
    );
    registro = RegistroProductoLocalService(
      store: store,
      imagenes: imagenes,
      nuevoId: () => 'id-constante',
    );
  });

  tearDown(() async {
    imagenes.cerrarCliente();
    await base.close();
    await temporal.delete(recursive: true);
  });

  test('sube la foto antes de escribir Firestore y guarda URL local', () async {
    final producto = await crear();
    final r = await sync.syncNow('usuario-1');
    expect(r.complete, isTrue);
    expect(subidor.llamadas, 1);
    expect(
      firestore.documentos[producto.id]?['imagenUrl'],
      contains('https://'),
    );
    expect(
      (await store.obtenerProductos('usuario-1')).single.imagenRuta,
      'productos/usuario-1/id-constante.jpg',
    );
    expect(await store.operacionesPendientes('usuario-1'), isEmpty);
  });

  test('sin foto sincroniza el producto directamente', () async {
    await crear(conFoto: false);
    final r = await sync.syncNow('usuario-1');
    expect(r.complete, isTrue);
    expect(subidor.llamadas, 0);
    expect(
      firestore.documentos['id-constante']?['nombre'],
      'Torta de chocolate',
    );
  });

  test(
    'fallo en Storage conserva la operacion, sin escribir documento',
    () async {
      await crear();
      subidor.falla = true;
      final r = await sync.syncNow('usuario-1');
      expect(r.confirmed, 0);
      expect(r.remaining, 1);
      expect(firestore.llamadas, 0);
      expect(await store.operacionesPendientes('usuario-1'), hasLength(1));
    },
  );

  test(
    'fallo en Firestore conserva el archivo y reintenta con mismo ID',
    () async {
      await crear();
      firestore.falla = true;
      final fallo = await sync.syncNow('usuario-1');
      expect(fallo.remaining, 1);
      expect((await store.obtenerProductos('usuario-1')).single.imagenUrl, '');
      firestore.falla = false;
      final bien = await sync.syncNow('usuario-1');
      expect(bien.complete, isTrue);
      expect(subidor.rutas, [
        'productos/usuario-1/id-constante.jpg',
        'productos/usuario-1/id-constante.jpg',
      ]);
      expect(firestore.documentos.length, 1);
    },
  );

  test('foto faltante marcada como pendiente no confirma operacion', () async {
    await store.guardarProducto(
      'usuario-1',
      ProductoModel(
        id: 'id-constante',
        nombre: 'Torta de chocolate',
        creadorUid: 'usuario-1',
        imagenRuta: ProductoFotoSyncGateway.fotoLocalPendiente,
        precio: 170,
        stock: 10,
      ),
    );
    final r = await sync.syncNow('usuario-1');
    expect(r.confirmed, 0);
    expect(r.remaining, 1);
    expect(firestore.llamadas, 0);
    expect(await store.operacionesPendientes('usuario-1'), hasLength(1));
  });

  test(
    'no ejecuta operacion de otro usuario dentro del mismo gateway',
    () async {
      await crear();
      // La consulta original del store solo extrae las pendientes de usuario-1.
      final pendientes = await store.operacionesPendientes('usuario-1');
      final op = pendientes.single;
      final incorrecta = OperacionPendiente(
        secuencia: op.secuencia,
        idOperacion: op.idOperacion,
        uid: 'usuario-2',
        entidad: op.entidad,
        idEntidad: op.idEntidad,
        accion: op.accion,
        payload: op.payload,
        fechaCreacion: op.fechaCreacion,
        intentos: op.intentos,
      );
      final gateway = ProductoFotoSyncGateway(
        firestore: firestore,
        subidor: subidor,
        imagenes: imagenes,
        baseLocal: base,
      );
      await expectLater(gateway.apply(incorrecta), throwsStateError);
      expect(subidor.llamadas, 0);
      expect(firestore.llamadas, 0);
    },
  );

  test('las operaciones delete se delegan sin buscar fotos', () async {
    await store.eliminarProducto('usuario-1', 'id-constante');
    final r = await sync.syncNow('usuario-1');
    expect(r.complete, isTrue);
    expect(subidor.llamadas, 0);
    expect(firestore.llamadas, 1);
  });
}
