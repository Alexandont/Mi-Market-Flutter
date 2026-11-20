import 'package:flutter_test/flutter_test.dart';
import 'package:mimarket_flutter/preferences/preferencias_locales.dart';

class Memoria implements AlmacenPreferencias {
  final valores = <String, String>{};
  @override
  Future<String?> leer(String clave) async => valores[clave];
  @override
  Future<void> escribir(String clave, String valor) async {
    valores[clave] = valor;
  }

  @override
  Future<void> borrar(String clave) async {
    valores.remove(clave);
  }
}

void main() {
  test('las preferencias quedan separadas por UID', () async {
    final repo = PreferenciasCatalogo(almacen: Memoria());
    expect(await repo.leerCategoria('usuario-a'), 'Todas');
    await repo.guardarCategoria('usuario-a', 'Bebidas');
    expect(await repo.leerCategoria('usuario-a'), 'Bebidas');
    expect(await repo.leerCategoria('usuario-b'), 'Todas');
  });

  test('rechaza categorias invalidas y permite restablecer', () async {
    final repo = PreferenciasCatalogo(almacen: Memoria());
    await expectLater(
      repo.guardarCategoria('usuario-a', 'Inexistente'),
      throwsArgumentError,
    );
    await repo.guardarCategoria('usuario-a', 'Lácteos');
    await repo.restablecerCategoria('usuario-a');
    expect(await repo.leerCategoria('usuario-a'), 'Todas');
  });
}
