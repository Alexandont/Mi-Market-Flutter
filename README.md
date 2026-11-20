# Mi-Market — Aplicación Flutter

Aplicación de gestión de productos de un minimarket, desarrollada con Flutter y Dart. Integra autenticación con Firebase, persistencia local mediante SQLite, sincronización de registros y fotografías con Firebase y consultas de lectura a una API REST local.

> **Estado del proyecto (20/11/2026):** desarrollo y validación en emulador Android. Este README documenta funciones verificadas y limitaciones actuales; no representa una certificación de producción.

## Funcionalidades

- Inicio de sesión con Firebase Authentication.
- Catálogo con búsqueda, filtros por categoría, precios y stock.
- Registro de productos con fotografía desde cámara o galería.
- Consulta de productos sin conexión, utilizando una copia local del catálogo.
- Registro de nuevos productos offline en Android/iOS, con ID estable y fotografía persistente.
- Cola SQLite de operaciones pendientes (*transactional outbox*).
- Reintento de sincronización al iniciar la aplicación, al volver al primer plano y periódicamente mientras la aplicación permanece abierta.
- Sincronización de fotografías a Firebase Storage y de documentos a Cloud Firestore.
- Carrito y pantallas de pedidos (su cobertura funcional completa requiere validación independiente).
- Consultas REST de productos autenticadas mediante Firebase ID Token (Bearer).

## Tecnologías

| Capa | Tecnología |
| --- | --- |
| Aplicación | Flutter, Dart y Material 3 |
| Autenticación | Firebase Authentication |
| Datos remotos | Cloud Firestore |
| Fotografías remotas | Firebase Storage |
| Datos locales | SQLite (`sqflite`) |
| Preferencias locales | `shared_preferences` |
| Red | `http` |
| API REST de desarrollo | Node.js y Express (proyecto separado) |
| Pruebas | `flutter_test` y pruebas SQLite con `sqflite_common_ffi` |

## Estructura relevante

```text
lib/
├── firebase/         # Autenticación, Firestore y Storage
├── local/            # SQLite, caché, outbox y fotografías locales
├── models/           # Modelos de datos
├── network/          # Contrato y cliente REST
├── preferences/      # Preferencias locales
├── repositories/     # Acceso a datos y registro offline
├── screens/          # Pantallas Flutter
├── sync/             # Gateways y ciclo de sincronización
├── viewmodels/       # Estado y lógica de presentación del catálogo
├── widgets/          # Componentes reutilizables
├── firebase_options.dart
└── main.dart

test/                  # Pruebas automatizadas
```

El catálogo utiliza un flujo de lectura que muestra primero datos SQLite y luego concilia eventos de Firestore. Los registros locales pendientes quedan protegidos frente a instantáneas remotas incompletas. La pantalla del catálogo incorpora un ViewModel; no se afirma que todas las pantallas estén migradas a MVVM.

## Persistencia y sincronización offline

La base de datos Android se llama `mimarket_offline_v1.db` y contiene las tablas:

- `productos_local`
- `pedidos_local`
- `carrito_local`
- `operaciones_pendientes`

Cada registro se vincula al UID autenticado. Al crear un producto offline, la aplicación asigna un identificador estable, conserva la fotografía fuera de la caché temporal y guarda el producto junto con su operación pendiente en una transacción SQLite.

La sincronización utiliza este recorrido:

```text
Crear producto sin conexión
      ↓
Foto persistente + SQLite + operación pendiente
      ↓
Reconexión / inicio / primer plano / reintento periódico
      ↓
Subir fotografía a Firebase Storage (si existe)
      ↓
Guardar documento en Cloud Firestore con el mismo ID
      ↓
Actualizar copia SQLite y confirmar la operación
```

Los fallos conservan la operación pendiente para reintentar. Las fotografías de productos nuevos se suben a rutas deterministas por usuario y producto. La sincronización periódica funciona **mientras la aplicación está abierta**; no se declara un servicio de sincronización en segundo plano con la app cerrada.

## API REST de lectura

El archivo `lib/network/api_contract.dart` define las direcciones de desarrollo:

- Emulador Android: `http://10.0.2.2:3000/api/v1/`
- Equipo anfitrión y web local: `http://localhost:3000/api/v1/`

El cliente `ApiService` obtiene un Firebase ID Token de la sesión actual y envía `Authorization: Bearer <token>` para las consultas `GET /productos` y `GET /productos/buscar?q=...`.

**Importante:** el servidor REST utilizado en las pruebas expone rutas de lectura; no se ha completado una API de escrituras REST. El cliente Flutter conserva métodos para otras operaciones, pero no deben considerarse endpoints de producción validados. Las escrituras de los productos offline en Android usan el flujo SQLite → Firebase indicado arriba.

El servidor Node.js se mantiene en su proyecto separado y se ejecuta allí con `npm start`. Para acceder al servicio desde un emulador Android, debe estar disponible en el puerto 3000 de la máquina anfitriona.

## Requisitos de ejecución

1. Flutter SDK y Android Studio instalados.
2. Emulador Android configurado o dispositivo Android conectado.
3. Configuración Firebase del proyecto disponible (incluido `lib/firebase_options.dart` y los archivos de plataforma que correspondan).
4. Cuenta de prueba autorizada en Firebase Authentication y reglas de Firestore/Storage adecuadas.

Desde la raíz del repositorio:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -t lib/main.dart
```

Para el diagnóstico REST, el servidor Node.js debe estar iniciado previamente. Los archivos `lib/diagnostico_api_rest.dart` y `lib/diagnostico_api_service.dart` se utilizaron para pruebas locales y **no forman parte de la ejecución normal ni deben subirse sin revisión**.

## Evidencias de validación — 20/11/2026

Las pruebas realizadas en el emulador Pixel 8 (Android API 37.1) documentaron:

| Prueba | Resultado observado |
| --- | --- |
| `flutter analyze` | Sin problemas |
| `flutter test` | 65 pruebas aprobadas |
| Consulta REST con token Firebase | HTTP 200 |
| Interpretación del cliente `ApiService` | 3 productos recibidos |
| Registro offline de «Naranja huando» | Visible con su fotografía |
| Persistencia después de cerrar y reabrir offline | Confirmada |
| Documento remoto | Observado en Cloud Firestore |
| Fotografía remota | Observada en Firebase Storage |
| `operaciones_pendientes` en Database Inspector | Tabla vacía en la inspección |

La evidencia disponible **no sustituye** una prueba exhaustiva de duplicados, reintentos por fallos parciales, reglas de seguridad y todos los casos de uso de pedidos o carrito.

## Seguridad y notas para producción

- El permiso `android:usesCleartextTraffic="true"` se añadió a `android/app/src/debug/AndroidManifest.xml` para las pruebas HTTP locales. **No debe habilitarse de forma indiscriminada en producción.**
- Para un despliegue público, utilizar una API con **HTTPS** y verificar las reglas de autorización de Firebase.
- No subir claves de cuentas de servicio, tokens, archivos `.env` con secretos ni credenciales privadas a GitHub.
- El almacenamiento de claves privadas del backend debe permanecer fuera del repositorio.
- Revisar las advertencias de dependencias npm y compatibilidad de plugins Kotlin/Gradle antes de publicar una versión de producción.
- La sincronización fuera de Android/iOS y con la aplicación cerrada no está acreditada por las pruebas descritas.

## Estado del repositorio

Rama de desarrollo validada: `feature/mvvm-persistencia-offline`.

El README está preparado para documentar el estado actual; su incorporación en un commit debe realizarse por separado y después de revisar los archivos locales pendientes.
