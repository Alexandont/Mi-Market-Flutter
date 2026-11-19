import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimarket_flutter/local/local_database.dart';
import 'package:mimarket_flutter/local/offline_store.dart';
import 'package:mimarket_flutter/local/operacion_pendiente.dart';
import 'package:mimarket_flutter/models/pedido_model.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:mimarket_flutter/sync/firebase_sync_gateway.dart';
import 'package:mimarket_flutter/sync/sync_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeRemote implements RemoteSyncGateway {
  bool available = true;
  final List<String> applied = [];
  final Map<String, Map<String, dynamic>?> products = {};
  final Map<String, Map<String, dynamic>?> orders = {};

  @override
  Future<void> apply(OperacionPendiente op) async {
    if (!available) throw StateError('sin red');
    applied.add(op.idOperacion);
    final key = '${op.uid}/${op.idEntidad}';
    if (op.entidad == 'producto') {
      if (op.accion == 'delete') {
        products.remove(key);
      } else {
        products[key] = op.payload;
      }
    } else if (op.entidad == 'pedido') {
      orders[key] = op.payload;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory temp;
  late LocalDatabase database;
  late OfflineStore store;
  late FakeRemote fake;
  late SyncService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mimarket_sync_test_');
    database = await LocalDatabase.openWithFactory(
      databaseFactoryFfi,
      path.join(temp.path, 'sync.db'),
    );
    store = OfflineStore(database);
    fake = FakeRemote();
    service = SyncService(store: store, remote: fake);
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  final product = ProductoModel(
    id: 'producto-id-estable',
    nombre: 'Leche',
    precio: 5.5,
    stock: 8,
  );

  test('sin conexion conserva la operacion con intentos', () async {
    await store.guardarProducto('u1', product);
    fake.available = false;
    final result = await service.syncNow('u1');
    expect(result.confirmed, 0);
    expect(result.remaining, 1);
    final pending = (await store.operacionesPendientes('u1')).single;
    expect(pending.intentos, 1);
    expect(fake.products, isEmpty);
  });

  test('tras recuperar conexion usa el mismo ID y elimina outbox', () async {
    await store.guardarProducto('u1', product);
    fake.available = false;
    await service.syncNow('u1');
    fake.available = true;
    final result = await service.syncNow('u1');
    expect(result.complete, isTrue);
    expect(result.confirmed, 1);
    expect(await store.operacionesPendientes('u1'), isEmpty);
    expect(fake.products.keys.single, 'u1/producto-id-estable');
  });

  test('upsert y delete se ejecutan en orden y no reviven el dato', () async {
    await store.guardarProducto('u1', product);
    await store.eliminarProducto('u1', product.id);
    final result = await service.syncNow('u1');
    expect(result.confirmed, 2);
    expect(fake.applied.length, 2);
    expect(fake.products, isEmpty);
    expect(await store.operacionesPendientes('u1'), isEmpty);
  });

  test('el usuario A no sincroniza los cambios de usuario B', () async {
    await store.guardarProducto('u1', product);
    await store.guardarProducto('u2', product);
    final result = await service.syncNow('u1');
    expect(result.confirmed, 1);
    expect((await store.operacionesPendientes('u2')).length, 1);
    expect(fake.products.containsKey('u1/producto-id-estable'), isTrue);
    expect(fake.products.containsKey('u2/producto-id-estable'), isFalse);
  });

  test('un pedido utiliza su ID local al sincronizar', () async {
    final order = PedidoModel(
      id: 'pedido-id-estable',
      total: 11,
      fecha: 1234,
      direccionEntrega: 'Prueba',
      items: [
        ItemPedidoModel(
          productoId: product.id,
          nombre: product.nombre,
          cantidad: 2,
          precioUnitario: 5.5,
        ),
      ],
    );
    await store.guardarPedido('u1', order);
    final report = await service.syncNow('u1');
    expect(report.complete, isTrue);
    expect(fake.orders.containsKey('u1/pedido-id-estable'), isTrue);
  });

  test('sin elementos pendientes no escribe nada', () async {
    final report = await service.syncNow('u1');
    expect(report.confirmed, 0);
    expect(report.complete, isTrue);
    expect(fake.applied, isEmpty);
  });
}
