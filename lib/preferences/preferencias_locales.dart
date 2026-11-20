import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/producto_model.dart';

/// Solo preferencias de interfaz. No usar para pedidos, outbox ni credenciales.
abstract class AlmacenPreferencias {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrar(String clave);
}

/// En Android SharedPreferencesAsync utiliza DataStore Preferences por defecto.
class AlmacenPreferenciasSistema implements AlmacenPreferencias {
  AlmacenPreferenciasSistema({SharedPreferencesAsync? preferencias})
    : _preferencias = preferencias ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferencias;

  @override
  Future<String?> leer(String clave) => _preferencias.getString(clave);

  @override
  Future<void> escribir(String clave, String valor) async {
    await _preferencias.setString(clave, valor);
  }

  @override
  Future<void> borrar(String clave) => _preferencias.remove(clave);
}

class PreferenciasCatalogo {
  PreferenciasCatalogo({AlmacenPreferencias? almacen})
    : _almacen = almacen ?? AlmacenPreferenciasSistema();

  final AlmacenPreferencias _almacen;

  String _clave(String uid) {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'La sesion debe estar activa');
    }
    final hash = sha256.convert(uid.codeUnits).toString();
    return 'mimarket.v1.catalogo.categoria.$hash';
  }

  Future<String> leerCategoria(String uid) async {
    final valor = await _almacen.leer(_clave(uid));
    if (valor == 'Todas' || ProductoModel.categorias.contains(valor)) {
      return valor!;
    }
    return 'Todas';
  }

  Future<void> guardarCategoria(String uid, String categoria) async {
    if (categoria != 'Todas' && !ProductoModel.categorias.contains(categoria)) {
      throw ArgumentError.value(categoria, 'categoria');
    }
    await _almacen.escribir(_clave(uid), categoria);
  }

  Future<void> restablecerCategoria(String uid) => _almacen.borrar(_clave(uid));
}
