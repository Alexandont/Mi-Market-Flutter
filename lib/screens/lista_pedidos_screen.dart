import 'package:flutter/material.dart';
import '../models/pedido_model.dart';
import '../repositories/pedido_repository.dart';

/// Historial de pedidos del usuario.
///
/// Escucha la subcoleccion `usuarios/{uid}/pedidos` en tiempo real, de modo
/// que un pedido recien confirmado aparece sin recargar.
class ListaPedidosScreen extends StatefulWidget {
  const ListaPedidosScreen({super.key});

  @override
  State<ListaPedidosScreen> createState() => _ListaPedidosScreenState();
}

class _ListaPedidosScreenState extends State<ListaPedidosScreen> {
  final _pedidos = PedidoRepository();

  /// Convierte los milisegundos guardados en Firestore a una fecha legible.
  String _formatearFecha(int milisegundos) {
    if (milisegundos == 0) return 'Sin fecha';
    final fecha = DateTime.fromMillisecondsSinceEpoch(milisegundos);
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year} a las $hora:$minuto';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pedidos')),
      body: StreamBuilder<List<PedidoModel>>(
        stream: _pedidos.escucharPedidos(),
        builder: (contexto, instantanea) {
          if (instantanea.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (instantanea.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 56),
                    const SizedBox(height: 12),
                    const Text('No se pudieron cargar los pedidos'),
                    const SizedBox(height: 4),
                    Text(
                      '${instantanea.error}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }

          final lista = instantanea.data ?? const <PedidoModel>[];

          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 56),
                    SizedBox(height: 12),
                    Text('Todavia no tiene pedidos'),
                    SizedBox(height: 4),
                    Text('Sus compras apareceran aqui'),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lista.length,
            itemBuilder: (contexto, indice) {
              final pedido = lista[indice];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text('${pedido.cantidadProductos}'),
                  ),
                  title: Text(pedido.totalFormateado),
                  subtitle: Text(_formatearFecha(pedido.fecha)),
                  trailing: Chip(
                    label: Text(pedido.estado),
                    visualDensity: VisualDensity.compact,
                  ),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (pedido.direccionEntrega.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(pedido.direccionEntrega)),
                        ],
                      ),
                      const Divider(height: 24),
                    ],
                    ...pedido.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${item.cantidad} x ${item.nombre}'),
                            ),
                            Text('S/ ${item.subtotal.toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
