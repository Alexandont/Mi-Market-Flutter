import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:mimarket_flutter/network/api_service.dart';

void main() {
  test('GET productos interpreta el contrato JSON con HTTP simulado', () async {
    final api = ApiService(
      cliente: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/productos');
        return http.Response(
          jsonEncode([
            {'id': 'p1', 'nombre': 'Leche', 'precio': 11.5, 'stock': 10},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final items = await api.obtenerProductos();
    expect(items.single.id, 'p1');
    expect(items.single.precio, 11.5);
    api.cerrar();
  });

  test('POST productos envia JSON y acepta una respuesta valida', () async {
    final api = ApiService(
      cliente: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/productos');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['nombre'], 'Pan');
        return http.Response(jsonEncode({...body, 'id': 'id-servidor'}), 201);
      }),
    );
    final creado = await api.crearProducto(
      ProductoModel(nombre: 'Pan', precio: 8, stock: 3),
    );
    expect(creado?.id, 'id-servidor');
    api.cerrar();
  });

  test(
    'cuando el servidor falla conserva su comportamiento opcional',
    () async {
      final api = ApiService(
        cliente: MockClient((request) async => http.Response('error', 503)),
      );
      expect(await api.obtenerProductos(), isEmpty);
      expect(await api.crearProducto(ProductoModel(nombre: 'Pan')), isNull);
      api.cerrar();
    },
  );
}
