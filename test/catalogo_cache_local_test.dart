import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimarket_flutter/local/catalogo_cache_local.dart';
import 'package:mimarket_flutter/local/local_database.dart';
import 'package:mimarket_flutter/local/offline_store.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const uid = 'usuario-A';
  final arroz = ProductoModel(
    id: 'arroz-1',
    nombre: 'Arroz',
    precio: 4.5,
    stock: 5,
  );
  final leche = ProductoModel(
    id: 'leche-1',
    nombre: 'Leche',
    precio: 5.0,
    stock: 7,
  );

  late Directory carpeta;
  late String ubicacion;
  late LocalDatabase base;
  late CatalogoCacheLocal cache;
  late OfflineStore store;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('mimarket_cache_test_');
    ubicacion = path.join(carpeta.path, 'datos.db');
    base = await LocalDatabase.openWithFactory(databaseFactoryFfi, ubicacion);
    cache = CatalogoCacheLocal(base);
    store = OfflineStore(base);
  });

  tearDown(() async {
    await base.close();
    await carpeta.delete(recursive: true);
  });

  test('snapshot remoto se conserva tras reinicio de SQLite', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz, leche]);
    expect((await cache.leer(uid)).length, 2);
    expect(await store.operacionesPendientes(uid), isEmpty);

    await base.close();
    base = await LocalDatabase.openWithFactory(databaseFactoryFfi, ubicacion);
    cache = CatalogoCacheLocal(base);
    store = OfflineStore(base);
    expect((await cache.leer(uid)).map((p) => p.id).toSet(), {
      'arroz-1',
      'leche-1',
    });
    expect(await store.operacionesPendientes(uid), isEmpty);
  });

  test(
    'edicion offline pendiente no se sobreescribe con snapshot antiguo',
    () async {
      await cache.guardarSnapshotRemoto(uid, [arroz]);
      await store.guardarProducto(uid, arroz.copyWith(nombre: 'Arroz local'));
      await cache.guardarSnapshotRemoto(uid, [arroz]);
      expect((await cache.leer(uid)).single.nombre, 'Arroz local');
      expect((await store.operacionesPendientes(uid)).length, 1);
    },
  );

  test('borrado offline no reaparece al actualizar el catalogo', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    await store.eliminarProducto(uid, arroz.id);
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    expect(await cache.leer(uid), isEmpty);
    expect((await store.operacionesPendientes(uid)).single.accion, 'delete');
  });

  test('snapshot completo quita registros remotos obsoletos', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz, leche]);
    await cache.guardarSnapshotRemoto(uid, [leche]);
    expect((await cache.leer(uid)).single.id, leche.id);
    expect(await store.operacionesPendientes(uid), isEmpty);
  });

  test('snapshot remoto no mezcla los datos entre usuarios', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    await cache.guardarSnapshotRemoto('usuario-B', [leche]);
    expect((await cache.leer(uid)).single.id, arroz.id);
    expect((await cache.leer('usuario-B')).single.id, leche.id);
    expect(await store.operacionesPendientes(uid), isEmpty);
  });

  test('snapshot con IDs duplicados se rechaza sin cambiar SQLite', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    await expectLater(
      cache.guardarSnapshotRemoto(uid, [leche, leche]),
      throwsArgumentError,
    );
    expect((await cache.leer(uid)).single.id, arroz.id);
  });
}
