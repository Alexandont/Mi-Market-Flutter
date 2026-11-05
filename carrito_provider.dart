import 'producto_model.dart';
import 'pedido_model.dart';

/// Una linea del carrito: un producto y cuantas unidades se llevan.
class ItemCarrito {
  final ProductoModel producto;
  final int cantidad;

  ItemCarrito({required this.producto, required this.cantidad});

  double get subtotal => producto.precio * cantidad;

  ItemCarrito copyWith({ProductoModel? producto, int? cantidad}) {
    return ItemCarrito(
      producto: producto ?? this.producto,
      cantidad: cantidad ?? this.cantidad,
    );
  }

  /// Convierte la linea del carrito en una linea de pedido, copiando el precio
  /// del momento de la compra.
  ItemPedidoModel aItemPedido() {
    return ItemPedidoModel(
      productoId: producto.id,
      nombre: producto.nombre,
      precioUnitario: producto.precio,
      cantidad: cantidad,
    );
  }
}

/// Carrito de compras y cache local de productos.
///
/// Es un Singleton: existe una sola instancia en toda la aplicacion, de modo
/// que el carrito sobrevive al cambiar de pantalla. Tambien guarda la ultima
/// lista de productos descargada, para poder mostrar algo cuando no hay
/// conexion.
class CarritoProvider {
  static final CarritoProvider _instancia = CarritoProvider._interno();
  factory CarritoProvider() => _instancia;
  CarritoProvider._interno();

  final List<ItemCarrito> _items = [];
  final List<ProductoModel> _productos = [];

  // ----------------------------------------------------------------
  // CARRITO
  // ----------------------------------------------------------------

  /// Lista no modificable de las lineas del carrito.
  List<ItemCarrito> obtenerItems() => List.unmodifiable(_items);

  /// Agrega un producto. Si ya estaba, suma la cantidad en lugar de duplicar
  /// la linea.
  void agregar(ProductoModel producto, {int cantidad = 1}) {
    if (cantidad <= 0) return;
    final indice = _items.indexWhere((i) => i.producto.id == producto.id);
    if (indice == -1) {
      _items.add(ItemCarrito(producto: producto, cantidad: cantidad));
    } else {
      final actual = _items[indice];
      _items[indice] = actual.copyWith(cantidad: actual.cantidad + cantidad);
    }
  }

  /// Fija la cantidad de un producto. Con cantidad cero o menos, lo quita.
  void cambiarCantidad(String productoId, int cantidad) {
    final indice = _items.indexWhere((i) => i.producto.id == productoId);
    if (indice == -1) return;
    if (cantidad <= 0) {
      _items.removeAt(indice);
    } else {
      _items[indice] = _items[indice].copyWith(cantidad: cantidad);
    }
  }

  /// Quita un producto del carrito.
  void quitar(String productoId) {
    _items.removeWhere((i) => i.producto.id == productoId);
  }

  /// Vacia el carrito. Se llama despues de confirmar un pedido.
  void vaciar() => _items.clear();

  /// Importe total del carrito.
  double get total => _items.fold(0.0, (suma, item) => suma + item.subtotal);

  /// Unidades totales, para el contador del icono del carrito.
  int get cantidadProductos =>
      _items.fold(0, (suma, item) => suma + item.cantidad);

  /// Indica si el carrito no tiene nada.
  bool get estaVacio => _items.isEmpty;

  /// Total formateado en soles.
  String get totalFormateado => 'S/ ${total.toStringAsFixed(2)}';

  /// Convierte el carrito en las lineas de un pedido.
  List<ItemPedidoModel> aItemsPedido() =>
      _items.map((item) => item.aItemPedido()).toList();

  // ----------------------------------------------------------------
  // CACHE DE PRODUCTOS
  // ----------------------------------------------------------------

  /// Reemplaza la cache con la lista recien descargada.
  void actualizarProductos(List<ProductoModel> nuevos) {
    _productos
      ..clear()
      ..addAll(nuevos);
  }

  /// Agrega un producto a la cache si no estaba.
  void agregarProducto(ProductoModel producto) {
    if (!_productos.any((p) => p.id == producto.id)) {
      _productos.add(producto);
    }
  }

  /// Lista no modificable de los productos en cache.
  List<ProductoModel> obtenerProductos() => List.unmodifiable(_productos);

  /// Filtra la cache por nombre, descripcion o categoria.
  List<ProductoModel> buscarProductos(String consulta) {
    final texto = consulta.toLowerCase().trim();
    if (texto.isEmpty) return obtenerProductos();
    return _productos.where((p) {
      return p.nombre.toLowerCase().contains(texto) ||
          p.descripcion.toLowerCase().contains(texto) ||
          p.categoria.toLowerCase().contains(texto);
    }).toList();
  }
}
