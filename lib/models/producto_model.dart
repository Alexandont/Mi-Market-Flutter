/// Modelo de un producto del minimarket.
///
/// Los nombres de los campos coinciden exactamente con la clase `Producto` de
/// la aplicacion nativa en Kotlin, de modo que ambas aplicaciones leen y
/// escriben los mismos documentos de la coleccion `productos` sin romperse.
class ProductoModel {
  /// Identificador del documento en Cloud Firestore.
  final String id;

  /// Nombre del producto.
  final String nombre;

  /// Descripcion del producto.
  final String descripcion;

  /// Categoria a la que pertenece. Ver [categorias].
  final String categoria;

  /// Precio unitario en soles.
  final double precio;

  /// Unidades disponibles.
  final int stock;

  /// URL publica de la foto almacenada en Firebase Storage.
  final String imagenUrl;

  /// Ruta interna del archivo en Storage, necesaria para poder borrarlo.
  final String imagenRuta;

  /// UID del usuario que creo el producto.
  final String creadorUid;

  /// Fecha de creacion en milisegundos desde la epoca.
  final int creadoEn;

  /// Fecha de la ultima actualizacion en milisegundos desde la epoca.
  final int actualizadoEn;

  ProductoModel({
    this.id = '',
    this.nombre = '',
    this.descripcion = '',
    this.categoria = '',
    this.precio = 0.0,
    this.stock = 0,
    this.imagenUrl = '',
    this.imagenRuta = '',
    this.creadorUid = '',
    this.creadoEn = 0,
    this.actualizadoEn = 0,
  });

  /// Categorias disponibles. Son las mismas que usa la aplicacion Kotlin.
  static const List<String> categorias = [
    'Abarrotes',
    'Bebidas',
    'Lácteos',
    'Frutas y verduras',
    'Carnes',
    'Panadería',
    'Limpieza',
    'Snacks',
    'Otros',
  ];

  /// Construye un [ProductoModel] desde un mapa de Firestore o de la API REST.
  ///
  /// Convierte los numeros con tolerancia porque Firestore puede devolver un
  /// entero donde se espera un decimal, y la API REST puede devolver texto.
  factory ProductoModel.fromJson(Map<String, dynamic> json) {
    return ProductoModel(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      categoria: (json['categoria'] ?? '').toString(),
      precio: _aDouble(json['precio']),
      stock: _aInt(json['stock']),
      imagenUrl: (json['imagenUrl'] ?? '').toString(),
      imagenRuta: (json['imagenRuta'] ?? '').toString(),
      creadorUid: (json['creadorUid'] ?? '').toString(),
      creadoEn: _aInt(json['creadoEn']),
      actualizadoEn: _aInt(json['actualizadoEn']),
    );
  }

  /// Serializa el producto al formato que se guarda en Firestore.
  ///
  /// No incluye `id` a proposito: las reglas de seguridad usan `hasOnly` y
  /// rechazan cualquier campo de mas. El identificador vive en el nombre del
  /// documento, no dentro de el.
  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'descripcion': descripcion,
      'categoria': categoria,
      'precio': precio,
      'stock': stock,
      'imagenUrl': imagenUrl,
      'imagenRuta': imagenRuta,
      'creadorUid': creadorUid,
      'creadoEn': creadoEn,
      'actualizadoEn': actualizadoEn,
    };
  }

  /// Crea una copia cambiando solo los campos indicados.
  ProductoModel copyWith({
    String? id,
    String? nombre,
    String? descripcion,
    String? categoria,
    double? precio,
    int? stock,
    String? imagenUrl,
    String? imagenRuta,
    String? creadorUid,
    int? creadoEn,
    int? actualizadoEn,
  }) {
    return ProductoModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      categoria: categoria ?? this.categoria,
      precio: precio ?? this.precio,
      stock: stock ?? this.stock,
      imagenUrl: imagenUrl ?? this.imagenUrl,
      imagenRuta: imagenRuta ?? this.imagenRuta,
      creadorUid: creadorUid ?? this.creadorUid,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  /// Indica si queda stock disponible.
  bool get hayStock => stock > 0;

  /// Precio formateado en soles, por ejemplo `S/ 12.50`.
  String get precioFormateado => 'S/ ${precio.toStringAsFixed(2)}';

  static double _aDouble(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0.0;
  }

  static int _aInt(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
