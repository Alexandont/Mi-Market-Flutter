/// Linea de un pedido: un producto con su cantidad y su precio al momento de
/// la compra.
///
/// El precio se copia dentro del pedido a proposito: si el producto cambia de
/// precio despues, el pedido historico conserva el que se cobro.
class ItemPedidoModel {
  final String productoId;
  final String nombre;
  final double precioUnitario;
  final int cantidad;

  ItemPedidoModel({
    this.productoId = '',
    this.nombre = '',
    this.precioUnitario = 0.0,
    this.cantidad = 0,
  });

  /// Importe de esta linea.
  double get subtotal => precioUnitario * cantidad;

  factory ItemPedidoModel.fromJson(Map<String, dynamic> json) {
    return ItemPedidoModel(
      productoId: (json['productoId'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      precioUnitario: _aDouble(json['precioUnitario']),
      cantidad: _aInt(json['cantidad']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productoId': productoId,
      'nombre': nombre,
      'precioUnitario': precioUnitario,
      'cantidad': cantidad,
    };
  }

  ItemPedidoModel copyWith({
    String? productoId,
    String? nombre,
    double? precioUnitario,
    int? cantidad,
  }) {
    return ItemPedidoModel(
      productoId: productoId ?? this.productoId,
      nombre: nombre ?? this.nombre,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      cantidad: cantidad ?? this.cantidad,
    );
  }

  static double _aDouble(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0.0;
  }

  static int _aInt(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}

/// Pedido realizado por un usuario.
///
/// Se guarda en la subcoleccion `usuarios/{uid}/pedidos`, igual que en la
/// aplicacion Kotlin.
class PedidoModel {
  /// Estado inicial de todo pedido nuevo.
  static const String estadoRegistrado = 'Registrado';

  final String id;
  final List<ItemPedidoModel> items;
  final double total;
  final String direccionEntrega;
  final double? latEntrega;
  final double? lngEntrega;
  final String estado;

  /// Fecha del pedido en milisegundos desde la epoca.
  final int fecha;

  PedidoModel({
    this.id = '',
    this.items = const [],
    this.total = 0.0,
    this.direccionEntrega = '',
    this.latEntrega,
    this.lngEntrega,
    this.estado = estadoRegistrado,
    this.fecha = 0,
  });

  /// Suma de unidades de todas las lineas.
  int get cantidadProductos =>
      items.fold(0, (suma, item) => suma + item.cantidad);

  /// Indica si el pedido tiene un punto de entrega en el mapa.
  bool get tieneEntrega => latEntrega != null && lngEntrega != null;

  /// Total formateado en soles.
  String get totalFormateado => 'S/ ${total.toStringAsFixed(2)}';

  factory PedidoModel.fromJson(Map<String, dynamic> json) {
    final listaCruda = json['items'];
    final items = <ItemPedidoModel>[];
    if (listaCruda is List) {
      for (final item in listaCruda) {
        if (item is Map) {
          items.add(ItemPedidoModel.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return PedidoModel(
      id: (json['id'] ?? '').toString(),
      items: items,
      total: _aDouble(json['total']),
      direccionEntrega: (json['direccionEntrega'] ?? '').toString(),
      latEntrega: _aDoubleNulable(json['latEntrega']),
      lngEntrega: _aDoubleNulable(json['lngEntrega']),
      estado: (json['estado'] ?? estadoRegistrado).toString(),
      fecha: _aInt(json['fecha']),
    );
  }

  /// Serializa el pedido para Firestore.
  ///
  /// No incluye `id`: las reglas usan `hasOnly` y rechazan campos de mas.
  Map<String, dynamic> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(),
      'total': total,
      'direccionEntrega': direccionEntrega,
      'latEntrega': latEntrega,
      'lngEntrega': lngEntrega,
      'estado': estado,
      'fecha': fecha,
    };
  }

  PedidoModel copyWith({
    String? id,
    List<ItemPedidoModel>? items,
    double? total,
    String? direccionEntrega,
    double? latEntrega,
    double? lngEntrega,
    String? estado,
    int? fecha,
  }) {
    return PedidoModel(
      id: id ?? this.id,
      items: items ?? this.items,
      total: total ?? this.total,
      direccionEntrega: direccionEntrega ?? this.direccionEntrega,
      latEntrega: latEntrega ?? this.latEntrega,
      lngEntrega: lngEntrega ?? this.lngEntrega,
      estado: estado ?? this.estado,
      fecha: fecha ?? this.fecha,
    );
  }

  static double _aDouble(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0.0;
  }

  static double? _aDoubleNulable(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor.toString());
  }

  static int _aInt(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
