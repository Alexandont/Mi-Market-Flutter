import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimarket_flutter/models/producto_model.dart';
import 'package:mimarket_flutter/network/api_response.dart';
import 'package:mimarket_flutter/viewmodels/catalogo_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('filtra por texto y categoria sin acceder a Firebase', () async {
    final eventos = StreamController<List<ProductoModel>>();
    final vm = CatalogoViewModel(
      observarProductos: () => eventos.stream,
      eliminarProducto: (_) async => ApiResponse.exito(true),
      puedeEditar: (_) => true,
    );
    vm.iniciar();
    eventos.add([
      ProductoModel(id: 'p1', nombre: 'Leche Gloria', categoria: 'Lácteos'),
      ProductoModel(id: 'p2', nombre: 'Pan Bimbo', categoria: 'Panadería'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(vm.cargando, isFalse);
    expect(vm.visibles.length, 2);
    vm.cambiarTexto('gloria');
    expect(vm.visibles.single.id, 'p1');
    vm.cambiarTexto('');
    vm.cambiarCategoria('Panadería');
    expect(vm.visibles.single.id, 'p2');
    vm.dispose();
    await eventos.close();
  });

  test('expone errores de la fuente de datos', () async {
    final vm = CatalogoViewModel(
      observarProductos: () =>
          Stream<List<ProductoModel>>.error(StateError('sin conexion')),
      eliminarProducto: (_) async => ApiResponse.exito(true),
      puedeEditar: (_) => false,
    );
    vm.iniciar();
    await Future<void>.delayed(Duration.zero);
    expect(vm.cargando, isFalse);
    expect(vm.error, contains('sin conexion'));
    vm.dispose();
  });

  test('restaura la categoria y la guarda al cambiar', () async {
    String? guardada;
    final vm = CatalogoViewModel(
      observarProductos: () => Stream.value(const <ProductoModel>[]),
      eliminarProducto: (_) async => ApiResponse.exito(true),
      puedeEditar: (_) => false,
      cargarCategoria: () async => 'Bebidas',
      guardarCategoria: (v) async {
        guardada = v;
      },
    );
    vm.iniciar();
    await Future<void>.delayed(Duration.zero);
    expect(vm.categoria, 'Bebidas');
    vm.cambiarCategoria('Otros');
    await Future<void>.delayed(Duration.zero);
    expect(guardada, 'Otros');
    vm.dispose();
  });
}
