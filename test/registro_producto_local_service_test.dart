import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mimarket_flutter/local/imagenes_producto_locales.dart';
import 'package:mimarket_flutter/local/local_database.dart';
import 'package:mimarket_flutter/local/offline_store.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:mimarket_flutter/repositories/registro_producto_local_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directorio;
  late LocalDatabase base;
  late OfflineStore store;
  late ImagenesProductoLocales imagenes;
  late RegistroProductoLocalService registro;

  ProductoModel muestra() => ProductoModel(
    nombre: 'Producto de prueba',
    descripcion: 'Prueba offline',
    categoria: 'Abarrotes',
    precio: 7.50,
    stock: 15,
  );

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('mimarket_registro_');
    base = await LocalDatabase.openWithFactory(
      databaseFactoryFfi,
      path.join(directorio.path, 'productos.db'),
    );
    store = OfflineStore(base);
    imagenes = ImagenesProductoLocales(
      raiz: Directory(path.join(directorio.path, 'imagenes')),
    );
    registro = RegistroProductoLocalService(
      store: store,
      imagenes: imagenes,
      nuevoId: () => 'producto-offline-1',
    );
  });

  tearDown(() async {
    imagenes.cerrarCliente();
    await base.close();
    await directorio.delete(recursive: true);
  });

  test('guarda producto en SQLite y crea una operacion pendiente', () async {
    final producto = await registro.registrar('usuario-A', muestra());
    expect(producto.id, 'producto-offline-1');
    expect(producto.creadorUid, 'usuario-A');
    expect(producto.creadoEn, greaterThan(0));
    expect((await store.obtenerProductos('usuario-A')).single.id, producto.id);
    final pendientes = await store.operacionesPendientes('usuario-A');
    expect(pendientes, hasLength(1));
    expect(pendientes.single.entidad, 'producto');
    expect(pendientes.single.accion, 'upsert');
    expect(pendientes.single.idEntidad, producto.id);
  });

  test('conserva imagen y datos despues de reabrir SQLite', () async {
    final origen = File(path.join(directorio.path, 'foto.jpg'));
    await origen.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9], flush: true);
    final creado = await registro.registrar(
      'usuario-A',
      muestra(),
      fotografia: XFile(origen.path),
    );
    final archivo = await imagenes.buscarSeleccionada('usuario-A', creado.id);
    expect(archivo, isNotNull);
    expect(await archivo!.readAsBytes(), [0xFF, 0xD8, 0xFF, 0xD9]);

    await base.close();
    base = await LocalDatabase.openWithFactory(
      databaseFactoryFfi,
      path.join(directorio.path, 'productos.db'),
    );
    store = OfflineStore(base);
    final imagenesReabiertas = ImagenesProductoLocales(
      raiz: Directory(path.join(directorio.path, 'imagenes')),
    );
    expect((await store.obtenerProductos('usuario-A')).single.id, creado.id);
    expect(await store.operacionesPendientes('usuario-A'), hasLength(1));
    expect(
      await imagenesReabiertas.buscarSeleccionada('usuario-A', creado.id),
      isNotNull,
    );
    imagenesReabiertas.cerrarCliente();
  });

  test('mantiene separacion de usuarios en SQLite e imagenes', () async {
    final creado = await registro.registrar('usuario-A', muestra());
    expect(await store.obtenerProductos('usuario-B'), isEmpty);
    expect(await store.operacionesPendientes('usuario-B'), isEmpty);
    expect(await imagenes.buscarSeleccionada('usuario-B', creado.id), isNull);
  });

  test('rechaza ausencia de sesion sin generar operaciones', () async {
    await expectLater(registro.registrar('', muestra()), throwsArgumentError);
    expect(await store.operacionesPendientes('usuario-A'), isEmpty);
  });

  test('rechaza producto con identificador previo', () async {
    await expectLater(
      registro.registrar('usuario-A', muestra().copyWith(id: 'viejo')),
      throwsArgumentError,
    );
    expect(await store.obtenerProductos('usuario-A'), isEmpty);
  });

  test('rechaza datos invalidos antes de escribir en SQLite', () async {
    await expectLater(
      registro.registrar('usuario-A', muestra().copyWith(precio: -3)),
      throwsArgumentError,
    );
    expect(await store.operacionesPendientes('usuario-A'), isEmpty);
  });

  test('si falla la fotografia no crea registro parcial en SQLite', () async {
    final vacia = File(path.join(directorio.path, 'vacia.jpg'));
    await vacia.writeAsBytes([]);
    await expectLater(
      registro.registrar('usuario-A', muestra(), fotografia: XFile(vacia.path)),
      throwsStateError,
    );
    expect(await store.obtenerProductos('usuario-A'), isEmpty);
    expect(await store.operacionesPendientes('usuario-A'), isEmpty);
  });
}
