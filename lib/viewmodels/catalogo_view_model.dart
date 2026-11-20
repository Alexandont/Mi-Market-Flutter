import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/producto_model.dart';
import '../network/api_response.dart';

/// Estado del catalogo separado de los widgets (MVVM).
/// Las dependencias se reciben mediante funciones para facilitar pruebas.
class CatalogoViewModel extends ChangeNotifier {
  // Parametros publicos para la inyeccion de dependencias desde las pantallas.
  factory CatalogoViewModel({
    required Stream<List<ProductoModel>> Function() observarProductos,
    required Future<ApiResponse<bool>> Function(ProductoModel) eliminarProducto,
    required bool Function(ProductoModel) puedeEditar,
    Future<String> Function()? cargarCategoria,
    Future<void> Function(String)? guardarCategoria,
  }) {
    return CatalogoViewModel._(
      observarProductos,
      eliminarProducto,
      puedeEditar,
      cargarCategoria,
      guardarCategoria,
    );
  }

  // Constructor privado con inicializadores formales; evita los cinco lints.
  CatalogoViewModel._(
    this._observarProductos,
    this._eliminarProducto,
    this._puedeEditar,
    this._cargarCategoria,
    this._guardarCategoria,
  );

  final Stream<List<ProductoModel>> Function() _observarProductos;
  final Future<ApiResponse<bool>> Function(ProductoModel) _eliminarProducto;
  final bool Function(ProductoModel) _puedeEditar;
  final Future<String> Function()? _cargarCategoria;
  final Future<void> Function(String)? _guardarCategoria;

  StreamSubscription<List<ProductoModel>>? _suscripcion;
  List<ProductoModel> _productos = const [];
  bool _cargando = true;
  String? _error;
  String _texto = '';
  String _categoria = 'Todas';
  bool _descartado = false;
  bool _categoriaCambiada = false;
  int _generacion = 0;

  bool get cargando => _cargando;
  String? get error => _error;
  String get texto => _texto;
  String get categoria => _categoria;
  List<ProductoModel> get productos => List.unmodifiable(_productos);

  List<ProductoModel> get visibles {
    final buscar = _texto.trim().toLowerCase();
    return _productos
        .where((p) {
          final mismaCategoria =
              _categoria == 'Todas' || p.categoria == _categoria;
          final coincide =
              buscar.isEmpty ||
              p.nombre.toLowerCase().contains(buscar) ||
              p.descripcion.toLowerCase().contains(buscar);
          return mismaCategoria && coincide;
        })
        .toList(growable: false);
  }

  bool puedeEditar(ProductoModel producto) => _puedeEditar(producto);

  Future<ApiResponse<bool>> eliminar(ProductoModel producto) =>
      _eliminarProducto(producto);

  void cambiarTexto(String valor) {
    if (_texto == valor) return;
    _texto = valor;
    _avisar();
  }

  void cambiarCategoria(String valor) {
    if (_categoria == valor) return;
    _categoriaCambiada = true;
    _categoria = valor;
    _avisar();
    final guardar = _guardarCategoria;
    if (guardar != null) {
      unawaited(_guardarPreferencia(guardar, valor));
    }
  }

  Future<void> _guardarPreferencia(
    Future<void> Function(String) guardar,
    String valor,
  ) async {
    try {
      await guardar(valor);
    } catch (_) {
      // Un fallo de preferencias no altera los datos del catalogo.
    }
  }

  void iniciar() {
    _restaurarCategoria();
    recargar();
  }

  Future<void> _restaurarCategoria() async {
    final cargar = _cargarCategoria;
    if (cargar == null) return;
    try {
      final guardada = await cargar();
      if (_descartado || _categoriaCambiada) return;
      if (guardada == 'Todas' || ProductoModel.categorias.contains(guardada)) {
        _categoria = guardada;
        _avisar();
      }
    } catch (_) {
      // La app puede operar con el filtro predeterminado.
    }
  }

  void recargar() {
    final generacion = ++_generacion;
    final anterior = _suscripcion;
    _suscripcion = null;
    if (anterior != null) unawaited(anterior.cancel());
    _cargando = true;
    _error = null;
    _avisar();
    if (_descartado) return;
    try {
      _suscripcion = _observarProductos().listen(
        (lista) {
          if (_descartado || generacion != _generacion) return;
          _productos = List.unmodifiable(lista);
          _cargando = false;
          _error = null;
          _avisar();
        },
        onError: (Object error, StackTrace stack) {
          if (_descartado || generacion != _generacion) return;
          _cargando = false;
          _error = error.toString();
          _avisar();
        },
        onDone: () {
          if (_descartado || generacion != _generacion) return;
          _cargando = false;
          _avisar();
        },
      );
    } catch (e) {
      _cargando = false;
      _error = e.toString();
      _avisar();
    }
  }

  void _avisar() {
    if (!_descartado) notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _generacion++;
    final anterior = _suscripcion;
    if (anterior != null) unawaited(anterior.cancel());
    super.dispose();
  }
}
