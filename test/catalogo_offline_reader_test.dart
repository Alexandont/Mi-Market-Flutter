import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimarket_flutter/local/catalogo_cache_local.dart';
import 'package:mimarket_flutter/local/local_database.dart';
import 'package:mimarket_flutter/local/offline_store.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:mimarket_flutter/repositories/catalogo_offline_reader.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FuenteFalsa implements CatalogoFuente {
  FuenteFalsa(this.eventos);
  final Stream<CatalogoEvento> eventos;

  @override
  Stream<CatalogoEvento> observar() => eventos;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const uid = 'usuario-A';
  final arroz = ProductoModel(
    id: 'arroz',
    nombre: 'Arroz',
    precio: 4.5,
    stock: 10,
  );
  final leche = ProductoModel(
    id: 'leche',
    nombre: 'Leche',
    precio: 5.0,
    stock: 7,
  );
  final arrozEditado = arroz.copyWith(nombre: 'Arroz offline');

  late Directory temp;
  late String ruta;
  late LocalDatabase db;
  late CatalogoCacheLocal cache;
  late OfflineStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mimarket_reader_');
    ruta = path.join(temp.path, 'catalogo.db');
    db = await LocalDatabase.openWithFactory(databaseFactoryFfi, ruta);
    cache = CatalogoCacheLocal(db);
    store = OfflineStore(db);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  CatalogoOfflineReader reader(Stream<CatalogoEvento> eventos) =>
      CatalogoOfflineReader(
        cache: cache,
        store: store,
        fuente: FuenteFalsa(eventos),
      );

  test('emite SQLite antes de recibir el servidor', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    final resultados = await reader(const Stream<CatalogoEvento>.empty())
        .observar(uid)
        .toList();
    expect(resultados.length, 1);
    expect(resultados.first.single.id, 'arroz');
  });

  test('snapshot completo actualiza SQLite sin crear outbox', () async {
    final evento = CatalogoEvento(
      productos: [arroz, leche],
      confirmadoPorServidor: true,
    );
    final resultados = await reader(Stream.value(evento))
        .observar(uid)
        .toList();
    expect(resultados.first, isEmpty);
    expect(resultados.last.map((p) => p.id).toSet(), {'arroz', 'leche'});
    expect((await cache.leer(uid)).length, 2);
    expect(await store.operacionesPendientes(uid), isEmpty);
  });

  test('snapshot de caché incompleto no elimina SQLite', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz, leche]);
    final evento = CatalogoEvento(
      productos: [leche],
      confirmadoPorServidor: false,
    );
    final resultados = await reader(Stream.value(evento))
        .observar(uid)
        .toList();
    expect(resultados.last.map((p) => p.id).toSet(), {'arroz', 'leche'});
    expect((await cache.leer(uid)).length, 2);
  });

  test(
    'edición local pendiente prevalece contra snapshot confirmado',
    () async {
      await cache.guardarSnapshotRemoto(uid, [arroz]);
      await store.guardarProducto(uid, arrozEditado);
      final evento = CatalogoEvento(
        productos: [arroz],
        confirmadoPorServidor: true,
      );
      final resultados = await reader(Stream.value(evento))
          .observar(uid)
          .toList();
      expect(resultados.last.single.nombre, 'Arroz offline');
      expect((await store.operacionesPendientes(uid)).length, 1);
    },
  );

  test('borrado pendiente permanece oculto ante caché antigua', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    await store.eliminarProducto(uid, 'arroz');
    final evento = CatalogoEvento(
      productos: [arroz],
      confirmadoPorServidor: false,
    );
    final resultados = await reader(Stream.value(evento))
        .observar(uid)
        .toList();
    expect(resultados.last, isEmpty);
    expect((await store.operacionesPendientes(uid)).last.accion, 'delete');
  });

  test('al fallar red devuelve copia SQLite sin perder registros', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    final fuente = Stream<CatalogoEvento>.error(Exception('red caída'));
    final resultados = await reader(fuente).observar(uid).toList();
    expect(resultados.last.single.id, 'arroz');
  });

  test('la lectura inicial funciona después de reabrir SQLite', () async {
    await cache.guardarSnapshotRemoto(uid, [leche]);
    await db.close();
    db = await LocalDatabase.openWithFactory(databaseFactoryFfi, ruta);
    cache = CatalogoCacheLocal(db);
    store = OfflineStore(db);
    final resultados = await reader(const Stream<CatalogoEvento>.empty())
        .observar(uid)
        .toList();
    expect(resultados.single.single.id, 'leche');
  });

  test('la sesión B no muestra productos guardados para A', () async {
    await cache.guardarSnapshotRemoto(uid, [arroz]);
    final resultados = await reader(const Stream<CatalogoEvento>.empty())
        .observar('usuario-B')
        .toList();
    expect(resultados.single, isEmpty);
  });
}
