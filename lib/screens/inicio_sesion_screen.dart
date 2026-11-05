import 'package:flutter/material.dart';
import '../repositories/usuario_repository.dart';

/// Pantalla de inicio de sesion y registro.
///
/// Usa un solo formulario con dos modos para no duplicar campos: el boton
/// inferior alterna entre "entrar" y "crear cuenta", y en modo registro
/// aparece ademas el campo de nombre.
class InicioSesionScreen extends StatefulWidget {
  const InicioSesionScreen({super.key});

  @override
  State<InicioSesionScreen> createState() => _InicioSesionScreenState();
}

class _InicioSesionScreenState extends State<InicioSesionScreen> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _repositorio = UsuarioRepository();

  bool _modoRegistro = false;
  bool _cargando = false;
  bool _ocultarClave = true;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formulario.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    final respuesta = _modoRegistro
        ? await _repositorio.registrar(
            _email.text, _clave.text, _nombre.text)
        : await _repositorio.iniciarSesion(_email.text, _clave.text);

    if (!mounted) return;

    if (respuesta.isSuccess) {
      Navigator.pushReplacementNamed(context, '/menu');
      return;
    }

    setState(() {
      _cargando = false;
      _error = respuesta.message ?? 'No se pudo completar la operacion';
    });
  }

  Future<void> _recuperarClave() async {
    final correo = _email.text.trim();
    if (correo.isEmpty) {
      setState(() => _error = 'Escriba su correo para recuperar la contrasena');
      return;
    }

    final respuesta = await _repositorio.recuperarClave(correo);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(respuesta.message ?? 'Operacion completada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formulario,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.storefront,
                          size: 56, color: colores.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Mi Market',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _modoRegistro
                            ? 'Cree su cuenta para empezar a comprar'
                            : 'Ingrese con su correo y contrasena',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),

                      if (_modoRegistro) ...[
                        TextFormField(
                          controller: _nombre,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (valor) {
                            if (valor == null || valor.trim().length < 3) {
                              return 'Escriba su nombre';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo electronico',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (valor) {
                          final texto = valor?.trim() ?? '';
                          if (texto.isEmpty) return 'Escriba su correo';
                          if (!texto.contains('@') || !texto.contains('.')) {
                            return 'El correo no es valido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _clave,
                        obscureText: _ocultarClave,
                        decoration: InputDecoration(
                          labelText: 'Contrasena',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_ocultarClave
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(
                                () => _ocultarClave = !_ocultarClave),
                          ),
                        ),
                        validator: (valor) {
                          if (valor == null || valor.length < 6) {
                            return 'Debe tener al menos 6 caracteres';
                          }
                          return null;
                        },
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colores.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: colores.onErrorContainer, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                      color: colores.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _cargando ? null : _enviar,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _cargando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_modoRegistro
                                ? 'Crear cuenta'
                                : 'Iniciar sesion'),
                      ),

                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _cargando
                            ? null
                            : () => setState(() {
                                  _modoRegistro = !_modoRegistro;
                                  _error = null;
                                }),
                        child: Text(_modoRegistro
                            ? 'Ya tengo cuenta, iniciar sesion'
                            : 'No tengo cuenta, registrarme'),
                      ),

                      if (!_modoRegistro)
                        TextButton(
                          onPressed: _cargando ? null : _recuperarClave,
                          child: const Text('Olvide mi contrasena'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
