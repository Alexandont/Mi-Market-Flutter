import 'package:flutter/material.dart';
import '../models/carrito_provider.dart';
import '../repositories/pedido_repository.dart';
import '../repositories/usuario_repository.dart';

/// Carrito de compras y confirmacion del pedido.
///
/// Permite cambiar cantidades, quitar lineas y confirmar la compra indicando
/// una direccion de entrega.
class CarritoScreen extends StatefulWidget {
  const CarritoScreen({super.key});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  final _carrito = CarritoProvider();
  final _pedidos = PedidoRepository();
  final _usuarios = UsuarioRepository();
  final _direccion = TextEditingController();

  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    _cargarDireccion();
  }

  @override
  void dispose() {
    _direccion.dispose();
    super.dispose();
  }

  /// Rellena la direccion con la que el usuario tenga guardada en su perfil.
  Future<void> _cargarDireccion() async {
    final respuesta = await _usuarios.obtenerPerfilActual();
    if (!mounted) return;
    final guardada = respuesta.data?.direccionEntrega ?? '';
    if (guardada.isNotEmpty && _direccion.text.isEmpty) {
      setState(() => _direccion.text = guardada);
    }
  }

  Future<void> _confirmar() async {
    if (_direccion.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique una direccion de entrega')),
      );
      return;
    }

    setState(() => _confirmando = true);

    final respuesta = await _pedidos.confirmarCarrito(
      direccionEntrega: _direccion.text,
    );

    if (!mounted) return;
    setState(() => _confirmando = false);

    if (!respuesta.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(respuesta.message ?? 'No se pudo registrar el pedido')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 48),
        title: const Text('Pedido registrado'),
        content: Text(
          'Su pedido por ${respuesta.data?.totalFormateado ?? ''} quedo '
          'registrado y lo puede seguir desde "Mis pedidos".',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(contexto),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = _carrito.obtenerItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrito'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Vaciar carrito',
              icon: const Icon(Icons.remove_shopping_cart_outlined),
              onPressed: () {
                _carrito.vaciar();
                setState(() {});
              },
            ),
        ],
      ),

      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 56),
                    SizedBox(height: 12),
                    Text('El carrito esta vacio'),
                    SizedBox(height: 4),
                    Text('Agregue productos desde el catalogo'),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (contexto, indice) {
                      final item = items[indice];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: item.producto.imagenUrl.isEmpty
                                ? Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: const Icon(Icons.shopping_bag_outlined),
                                  )
                                : Image.network(
                                    item.producto.imagenUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image_outlined),
                                  ),
                          ),
                        ),
                        title: Text(item.producto.nombre),
                        subtitle: Text(
                            '${item.producto.precioFormateado} c/u  ·  '
                            'S/ ${item.subtotal.toStringAsFixed(2)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                _carrito.cambiarCantidad(
                                    item.producto.id, item.cantidad - 1);
                                setState(() {});
                              },
                            ),
                            Text('${item.cantidad}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: item.cantidad >= item.producto.stock
                                  ? null
                                  : () {
                                      _carrito.cambiarCantidad(
                                          item.producto.id,
                                          item.cantidad + 1);
                                      setState(() {});
                                    },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                            color:
                                Theme.of(context).colorScheme.outlineVariant),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _direccion,
                          decoration: const InputDecoration(
                            labelText: 'Direccion de entrega',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total',
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            Text(
                              _carrito.totalFormateado,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _confirmando ? null : _confirmar,
                          icon: _confirmando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check),
                          label: Text(_confirmando
                              ? 'Registrando pedido'
                              : 'Confirmar pedido'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
