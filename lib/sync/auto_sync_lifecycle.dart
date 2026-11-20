import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../local/imagenes_producto_locales.dart';
import '../local/local_database_provider.dart';
import '../local/offline_store.dart';
import '../local/operacion_pendiente.dart';
import 'firebase_sync_gateway.dart';
import 'producto_foto_sync_gateway.dart';
import 'sync_service.dart';

/// En Android/iOS reintenta la outbox cuando la app se inicia, vuelve al
/// primer plano y a intervalos mientras permanece abierta.
/// No ejecuta sincronizacion en web/escritorio ni tareas en segundo plano.
class AutoSyncLifecycle extends StatefulWidget {
  const AutoSyncLifecycle({
    super.key,
    required this.child,
    this.intervalo = const Duration(seconds: 45),
    this.intentarSincronizacion = sincronizarPendientes,
    this.habilitado,
  });

  final Widget child;
  final Duration intervalo;
  final Future<void> Function() intentarSincronizacion;

  /// Usado en pruebas para activar la logica en otra plataforma.
  final bool? habilitado;

  @override
  State<AutoSyncLifecycle> createState() => _AutoSyncLifecycleState();
}

class _AutoSyncLifecycleState extends State<AutoSyncLifecycle>
    with WidgetsBindingObserver {
  Timer? _reintento;
  bool _ocupado = false;

  bool get _habilitado =>
      widget.habilitado ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  @override
  void initState() {
    super.initState();
    if (!_habilitado) return;
    WidgetsBinding.instance.addObserver(this);
    _reintento = Timer.periodic(widget.intervalo, (_) => _intentar());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _intentar();
    });
  }

  Future<void> _intentar() async {
    if (!mounted || _ocupado) return;
    _ocupado = true;
    try {
      await widget.intentarSincronizacion();
    } catch (e) {
      // Los errores remotos nunca deben cerrar la app ni borrar SQLite.
      debugPrint('MiMarket: sincronizacion pospuesta (${e.runtimeType})');
    } finally {
      _ocupado = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _habilitado) {
      _intentar();
    }
  }

  @override
  void dispose() {
    _reintento?.cancel();
    if (_habilitado) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// La cuenta de Firebase se comprueba antes y despues de cada operacion.
/// Si cambia, se mantiene la entrada en la outbox para un nuevo intento.
class _GatewayDeCuenta implements RemoteSyncGateway {
  _GatewayDeCuenta(this.uid, this.siguiente);

  final String uid;
  final RemoteSyncGateway siguiente;

  void _verificar(OperacionPendiente op) {
    if (op.uid != uid || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('La sesion cambio durante la sincronizacion');
    }
  }

  @override
  Future<void> apply(OperacionPendiente operation) async {
    _verificar(operation);
    await siguiente.apply(operation);
    _verificar(operation);
  }
}

/// Sincronizacion real: Storage -> Firestore -> actualizacion SQLite -> ACK.
/// Si una etapa falla, SyncService conserva la outbox y el archivo local.
Future<void> sincronizarPendientes() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.trim().isEmpty) return;

  final base = await LocalDatabaseProvider.database;
  final store = OfflineStore(base);
  if ((await store.operacionesPendientes(uid)).isEmpty) return;

  final gateway = ProductoFotoSyncGateway(
    firestore: FirebaseSyncGateway(),
    subidor: FirebaseSubidorFotoProducto(),
    imagenes: await ImagenesProductoLocales.compartida(),
    baseLocal: base,
  );
  final servicio = SyncService(
    store: store,
    remote: _GatewayDeCuenta(uid, gateway),
    // Dos operaciones remotas (imagen y documento) pueden requerir mas
    // tiempo que el timeout habitual de una sola escritura.
    operationTimeout: const Duration(seconds: 90),
  );
  final resultado = await servicio.syncNow(uid);
  if (resultado.error != null) {
    debugPrint(
      'MiMarket: pendientes=${resultado.remaining}; '
      'fallo=${resultado.error}',
    );
  } else if (resultado.confirmed > 0) {
    debugPrint(
      'MiMarket: sincronizadas=${resultado.confirmed}; '
      'pendientes=${resultado.remaining}',
    );
  }
}
