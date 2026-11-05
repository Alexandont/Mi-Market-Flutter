import 'package:flutter/material.dart';
import '../models/carrito_provider.dart';
import '../models/producto_model.dart';
import '../repositories/producto_repository.dart';

/// Catalogo de productos.
///
/// Usa un [StreamBuilder] sobre Firestore, asi que la lista se actualiza sola
/// cuando alguien agrega o cambia un producto, sin recargar la pantalla.
/// El filtro por texto y por categoria se aplica en memoria sobre esa lista.
class ListaProductosScreen extends StatefulWidget {
  const ListaProductosScreen({super.key});

  @override
  State<ListaProductosScreen> createState() => _ListaProductosScreenState();
}

class _ListaProductosScreenState extends State<ListaProductosScreen> {
  final _productos = ProductoRepository();
  final _carrito = CarritoProvider();
  final _busqueda = TextEditingController();

  String _texto = '';
  String _categoria = 'Todas';

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  List<ProductoModel> _filtrar(List<ProductoModel> lista) {
    final texto = _texto.toLowerCase().trim();
    return lista.where((p) {
      final coincideCategoria =
          _categoria == 'Todas' || p.categoria == _categoria;
      final coincideTexto = texto.isEmpty ||
          p.nombre.toLowerCase().contains(texto) ||
          p.descripcion.toLowerCase().contains(texto);
      return coincideCategoria && coincideTexto;
    }).toList();
  }

  void _agregarAlCarrito(ProductoModel producto) {
    _carrito.agregar(producto);
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${producto.nombre} agregado al carrito'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Ver carrito',
            onPressed: () => Navigator.pushNamed(context, '/carrito'),
          ),
        ),
      );
  }

  Future<void> _eliminar(ProductoModel producto) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('Se eliminara "${producto.nombre}" y su foto.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    final respuesta = await _productos.eliminarProducto(producto);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(respuesta.message ?? 'Operacion completada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categorias = ['Todas', ...ProductoModel.categorias];
    final enCarrito = _carrito.cantidadProductos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalogo'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () async {
                  await Navigator.pushNamed(context, '/carrito');
                  if (mounted) setState(() {});
                },
              ),
              if (enCarrito > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$enCarrito',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/registro_producto'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _busqueda,
                  decoration: InputDecoration(
                    hintText: 'Buscar producto',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _texto.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _busqueda.clear();
                              setState(() => _texto = '');
                            },
                          ),
                  ),
                  onChanged: (valor) => setState(() => _texto = valor),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categorias.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (contexto, indice) {
                      final categoria = categorias[indice];
                      return ChoiceChip(
                        label: Text(categoria),
                        selected: _categoria == categoria,
                        onSelected: (_) =>
                            setState(() => _categoria = categoria),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<List<ProductoModel>>(
              stream: _productos.escucharProductos(),
              builder: (contexto, instantanea) {
                if (instantanea.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (instantanea.hasError) {
                  return _Aviso(
                    icono: Icons.cloud_off,
                    titulo: 'No se pudo cargar el catalogo',
                    detalle: '${instantanea.error}',
                  );
                }

                final lista = _filtrar(instantanea.data ?? const []);

                if (lista.isEmpty) {
                  return _Aviso(
                    icono: Icons.inventory_2_outlined,
                    titulo: _texto.isEmpty && _categoria == 'Todas'
                        ? 'Todavia no hay productos'
                        : 'Sin resultados',
                    detalle: _texto.isEmpty && _categoria == 'Todas'
                        ? 'Pulse el boton Nuevo para registrar el primero'
                        : 'Pruebe con otro texto o categoria',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: lista.length,
                  itemBuilder: (contexto, indice) {
                    final producto = lista[indice];
                    return _TarjetaProducto(
                      producto: producto,
                      puedeEditar: _productos.puedeEditar(producto),
                      onAgregar: producto.hayStock
                          ? () => _agregarAlCarrito(producto)
                          : null,
                      onEliminar: () => _eliminar(producto),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de un producto dentro del catalogo.
class _TarjetaProducto extends StatelessWidget {
  final ProductoModel producto;
  final bool puedeEditar;
  final VoidCallback? onAgregar;
  final VoidCallback onEliminar;

  const _TarjetaProducto({
    required this.producto,
    required this.puedeEditar,
    required this.onAgregar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 72,
                child: producto.imagenUrl.isEmpty
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported_outlined),
                      )
                    : Image.network(
                        producto.imagenUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(producto.nombre,
                      style: Theme.of(context).textTheme.titleMedium),
                  if (producto.descripcion.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      producto.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        producto.precioFormateado,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.primary),
                      ),
                      if (producto.categoria.isNotEmpty)
                        Chip(
                          label: Text(producto.categoria),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      Text(
                        producto.hayStock
                            ? 'Stock: ${producto.stock}'
                            : 'Agotado',
                        style: TextStyle(
                          fontSize: 12,
                          color: producto.hayStock
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Column(
              children: [
                IconButton(
                  tooltip: producto.hayStock
                      ? 'Agregar al carrito'
                      : 'Sin stock',
                  icon: const Icon(Icons.add_shopping_cart),
                  onPressed: onAgregar,
                ),
                if (puedeEditar)
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onEliminar,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mensaje centrado para estados vacios o de error.
class _Aviso extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
