import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimarket_flutter/local/local_database.dart';
import 'package:mimarket_flutter/local/offline_store.dart';
import 'package:mimarket_flutter/models/pedido_model.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory carpeta;
  late String ubicacion;
  late LocalDatabase base;
  late OfflineStore local;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('mimarket_test_');
    ubicacion = path.join(carpeta.path, 'datos.db');
    base = await LocalDatabase.openWithFactory(databaseFactoryFfi, ubicacion);
    local = OfflineStore(base);
  });

  tearDown(() async {
    await base.close();
    await carpeta.delete(recursive: true);
  });

  final producto = ProductoModel(
    id: 'producto-001',
    nombre: 'Arroz',
    categoria: 'Abarrotes',
    precio: 4.50,
    stock: 5,
  );

  test('producto y outbox sobreviven a cerrar y reabrir SQLite', () async {
    await local.guardarProducto('usuario-A', producto);
    expect((await local.obtenerProductos('usuario-A')).single.nombre, 'Arroz');
    expect((await local.operacionesPendientes('usuario-A')).length, 1);

    await base.close();
    base = await LocalDatabase.openWithFactory(databaseFactoryFfi, ubicacion);
    local = OfflineStore(base);
    expect(
      (await local.obtenerProductos('usuario-A')).single.id,
      'producto-001',
    );
    expect((await local.operacionesPendientes('usuario-A')).length, 1);
  });

  test('separacion de datos por UID', () async {
    await local.guardarProducto('usuario-A', producto);
    expect(await local.obtenerProductos('usuario-B'), isEmpty);
    expect(await local.operacionesPendientes('usuario-B'), isEmpty);
  });

  test('eliminar crea tombstone y conserva el cambio pendiente', () async {
    await local.guardarProducto('usuario-A', producto);
    await local.eliminarProducto('usuario-A', 'producto-001');
    expect(await local.obtenerProductos('usuario-A'), isEmpty);
    final cola = await local.operacionesPendientes('usuario-A');
    expect(cola.map((o) => o.accion).toList(), ['upsert', 'delete']);
  });

  test('confirmar solo elimina la operacion confirmada', () async {
    await local.guardarProducto('usuario-A', producto);
    final operacion = (await local.operacionesPendientes('usuario-A')).single;
    await local.registrarError('usuario-A', operacion.idOperacion, 'Sin red');
    expect((await local.operacionesPendientes('usuario-A')).single.intentos, 1);
    await local.confirmarSincronizacion('usuario-B', operacion.idOperacion);
    expect((await local.operacionesPendientes('usuario-A')).length, 1);
    await local.confirmarSincronizacion('usuario-A', operacion.idOperacion);
    expect(await local.operacionesPendientes('usuario-A'), isEmpty);
  });

  test('pedido persiste y conserva su ID estable', () async {
    const uid = 'usuario-A';
    final pedido = PedidoModel(
      id: 'pedido-001',
      fecha: 1000,
      total: 9,
      direccionEntrega: 'Calle de prueba 123',
      items: [
        ItemPedidoModel(
          productoId: producto.id,
          nombre: 'Arroz',
          cantidad: 2,
          precioUnitario: 4.5,
        ),
      ],
    );
    await local.guardarPedido(uid, pedido);
    expect((await local.obtenerPedidos(uid)).single.id, 'pedido-001');
    expect((await local.operacionesPendientes(uid)).single.entidad, 'pedido');
  });

  test('carrito persiste despues de reabrir', () async {
    await local.guardarItemCarrito('usuario-A', producto, 3);
    await base.close();
    base = await LocalDatabase.openWithFactory(databaseFactoryFfi, ubicacion);
    local = OfflineStore(base);
    final items = await local.obtenerCarrito('usuario-A');
    expect(items.single.cantidad, 3);
    expect(items.single.producto.id, producto.id);
  });
}
