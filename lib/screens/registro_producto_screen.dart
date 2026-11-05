import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/producto_model.dart';
import '../repositories/producto_repository.dart';

/// Formulario de registro de un producto nuevo.
///
/// La vista previa de la foto usa [Image.memory] con los bytes del archivo en
/// lugar de [Image.file], porque `Image.file` no funciona cuando la aplicacion
/// corre en el navegador.
class RegistroProductoScreen extends StatefulWidget {
  const RegistroProductoScreen({super.key});

  @override
  State<RegistroProductoScreen> createState() =>
      _RegistroProductoScreenState();
}

class _RegistroProductoScreenState extends State<RegistroProductoScreen> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _precio = TextEditingController();
  final _stock = TextEditingController(text: '1');

  final _repositorio = ProductoRepository();
  final _selector = ImagePicker();

  String _categoria = ProductoModel.categorias.first;
  XFile? _imagen;
  Uint8List? _vistaPrevia;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _precio.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _elegirImagen(ImageSource origen) async {
    try {
      final archivo = await _selector.pickImage(
        source: origen,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (archivo == null) return;

      final bytes = await archivo.readAsBytes();
      if (!mounted) return;

      setState(() {
        _imagen = archivo;
        _vistaPrevia = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la imagen: $e')),
      );
    }
  }

  void _mostrarOpcionesImagen() {
    showModalBottomSheet<void>(
      context: context,
      builder: (contexto) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galeria'),
              onTap: () {
                Navigator.pop(contexto);
                _elegirImagen(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar una foto'),
              onTap: () {
                Navigator.pop(contexto);
                _elegirImagen(ImageSource.camera);
              },
            ),
            if (_imagen != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Quitar la foto'),
                onTap: () {
                  Navigator.pop(contexto);
                  setState(() {
                    _imagen = null;
                    _vistaPrevia = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formulario.currentState!.validate()) return;

    setState(() => _guardando = true);

    final producto = ProductoModel(
      nombre: _nombre.text.trim(),
      descripcion: _descripcion.text.trim(),
      categoria: _categoria,
      precio: double.parse(_precio.text.replaceAll(',', '.')),
      stock: int.parse(_stock.text),
    );

    final respuesta = await _repositorio.crearProducto(producto, _imagen);
    if (!mounted) return;

    if (respuesta.isSuccess) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto registrado')),
      );
      return;
    }

    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(respuesta.message ?? 'No se pudo guardar')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo producto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formulario,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: _guardando ? null : _mostrarOpcionesImagen,
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: colores.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colores.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _vistaPrevia == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined,
                                    size: 40, color: colores.outline),
                                const SizedBox(height: 8),
                                const Text('Toque para agregar una foto'),
                              ],
                            )
                          : Image.memory(_vistaPrevia!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del producto',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().length < 2) {
                        return 'Escriba el nombre';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _descripcion,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _categoria,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: ProductoModel.categorias
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (valor) {
                      if (valor != null) setState(() => _categoria = valor);
                    },
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _precio,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Precio',
                            prefixText: 'S/ ',
                          ),
                          validator: (valor) {
                            final numero = double.tryParse(
                                (valor ?? '').replaceAll(',', '.'));
                            if (numero == null) return 'Precio invalido';
                            if (numero <= 0) return 'Debe ser mayor que cero';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _stock,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Stock',
                          ),
                          validator: (valor) {
                            final numero = int.tryParse(valor ?? '');
                            if (numero == null) return 'Cantidad invalida';
                            if (numero < 0) return 'No puede ser negativo';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  FilledButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: _guardando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_guardando
                        ? 'Guardando en Firebase'
                        : 'Guardar producto'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
