import 'package:flutter/material.dart';
import '../models/carrito_provider.dart';
import '../repositories/usuario_repository.dart';

/// Menu principal de Mi Market.
///
/// Es el punto de reparto hacia los tres modulos de la aplicacion: catalogo,
/// carrito e historial de pedidos.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _usuarios = UsuarioRepository();
  final _carrito = CarritoProvider();

  String _nombre = '';

  @override
  void initState() {
    super.initState();
    _cargarUsuario();
  }

  Future<void> _cargarUsuario() async {
    final respuesta = await _usuarios.obtenerPerfilActual();
    if (!mounted) return;
    if (respuesta.isSuccess && respuesta.data != null) {
      setState(() => _nombre = respuesta.data!.nombre);
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text('Se perdera el contenido del carrito.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Cerrar sesion'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    _carrito.vaciar();
    await _usuarios.cerrarSesion();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (ruta) => false);
  }

  Future<void> _abrir(String ruta) async {
    await Navigator.pushNamed(context, ruta);
    // Al volver, se refresca para actualizar el contador del carrito.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enCarrito = _carrito.cantidadProductos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Market'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            icon: const Icon(Icons.logout),
            onPressed: _cerrarSesion,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_nombre.isNotEmpty) ...[
                  Text(
                    'Hola, $_nombre',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Que desea hacer hoy',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],

                _Opcion(
                  icono: Icons.inventory_2_outlined,
                  titulo: 'Catalogo de productos',
                  detalle: 'Buscar, agregar al carrito y registrar productos',
                  onTap: () => _abrir('/productos'),
                ),
                const SizedBox(height: 12),

                _Opcion(
                  icono: Icons.shopping_cart_outlined,
                  titulo: 'Carrito',
                  detalle: enCarrito == 0
                      ? 'No hay productos todavia'
                      : '$enCarrito producto(s) por ${_carrito.totalFormateado}',
                  insignia: enCarrito,
                  onTap: () => _abrir('/carrito'),
                ),
                const SizedBox(height: 12),

                _Opcion(
                  icono: Icons.receipt_long_outlined,
                  titulo: 'Mis pedidos',
                  detalle: 'Historial de compras realizadas',
                  onTap: () => _abrir('/pedidos'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de una opcion del menu.
class _Opcion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;
  final int insignia;
  final VoidCallback onTap;

  const _Opcion({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
    this.insignia = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colores.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: colores.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(detalle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (insignia > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colores.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$insignia',
                    style: TextStyle(
                        color: colores.onPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
