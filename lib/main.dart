import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'repositories/usuario_repository.dart';
import 'screens/carrito_screen.dart';
import 'screens/inicio_sesion_screen.dart';
import 'screens/lista_pedidos_screen.dart';
import 'screens/lista_productos_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/registro_producto_screen.dart';

/// Punto de entrada de Mi Market.
///
/// Inicializa Firebase antes de levantar la interfaz y decide si abrir el
/// menu o la pantalla de inicio de sesion segun exista o no una sesion
/// activa.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Error al inicializar Firebase: $e');
  }

  runApp(const MiMarketApp());
}

/// Widget raiz de la aplicacion.
class MiMarketApp extends StatelessWidget {
  const MiMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    final usuarioRepository = UsuarioRepository();
    final autenticado = usuarioRepository.estaAutenticado();

    return MaterialApp(
      title: 'Mi Market',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7F3B)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
      ),
      initialRoute: autenticado ? '/menu' : '/login',
      routes: {
        '/login': (context) => const InicioSesionScreen(),
        '/menu': (context) => const MenuScreen(),
        '/productos': (context) => const ListaProductosScreen(),
        '/registro_producto': (context) => const RegistroProductoScreen(),
        '/carrito': (context) => const CarritoScreen(),
        '/pedidos': (context) => const ListaPedidosScreen(),
      },
    );
  }
}
