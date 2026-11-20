import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mimarket_flutter/local/imagenes_producto_locales.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporal;
  late ImagenesProductoLocales imagenes;

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('mimarket_fotos_');
    imagenes = ImagenesProductoLocales(raiz: temporal);
  });

  tearDown(() async {
    imagenes.cerrarCliente();
    await temporal.delete(recursive: true);
  });

  Future<XFile> imagenTemporal(String nombre, List<int> datos) async {
    final carpeta = Directory(path.join(temporal.path, 'picker'));
    await carpeta.create(recursive: true);
    final archivo = File(path.join(carpeta.path, nombre));
    await archivo.writeAsBytes(datos);
    return XFile(archivo.path);
  }

  final foto = [137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3];

  test('foto seleccionada sobrevive a reconstruir el servicio', () async {
    final seleccion = await imagenTemporal('camara.png', foto);
    final guardada = await imagenes.guardarSeleccionada('u1', 'p1', seleccion);
    expect(await guardada.exists(), isTrue);
    final otraInstancia = ImagenesProductoLocales(raiz: temporal);
    final recuperada = await otraInstancia.buscarSeleccionada('u1', 'p1');
    expect(recuperada?.path, guardada.path);
    expect(await recuperada!.readAsBytes(), foto);
    otraInstancia.cerrarCliente();
  });

  test('separa fotos por usuario y producto', () async {
    final seleccion = await imagenTemporal('foto.png', foto);
    await imagenes.guardarSeleccionada('u1', 'p1', seleccion);
    expect(await imagenes.buscarSeleccionada('u1', 'p2'), isNull);
    expect(await imagenes.buscarSeleccionada('u2', 'p1'), isNull);
  });

  test('una foto nueva tiene prioridad sobre la seleccion anterior', () async {
    await imagenes.guardarSeleccionada(
      'u1',
      'p1',
      await imagenTemporal('a.png', foto),
    );
    final nueva = [1, 2, 3, 4, 5];
    await imagenes.guardarSeleccionada(
      'u1',
      'p1',
      await imagenTemporal('b.png', nueva),
    );
    expect(
      await (await imagenes.buscarSeleccionada('u1', 'p1'))!.readAsBytes(),
      nueva,
    );
  });

  test(
    'la copia descargada sigue disponible sin internet tras reinicio',
    () async {
      var intentos = 0;
      final cliente = MockClient((request) async {
        intentos++;
        return http.Response.bytes(
          Uint8List.fromList(foto),
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final online = ImagenesProductoLocales(raiz: temporal, cliente: cliente);
      const url = 'https://storage.example.com/imagen1.png';
      await online.descargarRemota('u1', 'p1', url);
      online.cerrarCliente();
      final sinInternet = ImagenesProductoLocales(
        raiz: temporal,
        cliente: MockClient(
          (_) async => throw const SocketException('sin red'),
        ),
      );
      final archivo = await sinInternet.buscarRemota('u1', 'p1', url);
      expect(await archivo!.readAsBytes(), foto);
      expect(
        (await sinInternet.descargarRemota('u1', 'p1', url)).path,
        archivo.path,
      );
      expect(intentos, 1);
      sinInternet.cerrarCliente();
    },
  );

  test('una URL descargada no realiza otra peticion innecesaria', () async {
    var consultas = 0;
    final client = MockClient((_) async {
      consultas++;
      return http.Response.bytes(
        Uint8List.fromList(foto),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    final servicio = ImagenesProductoLocales(raiz: temporal, cliente: client);
    const url = 'https://storage.example.com/a.png';
    await servicio.descargarRemota('u1', 'p1', url);
    await servicio.descargarRemota('u1', 'p1', url);
    expect(consultas, 1);
    servicio.cerrarCliente();
  });

  test('cambiar la URL no reutiliza una fotografia remota obsoleta', () async {
    final servicio = ImagenesProductoLocales(
      raiz: temporal,
      cliente: MockClient(
        (_) async => http.Response.bytes(
          Uint8List.fromList(foto),
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );
    const vieja = 'https://storage.example.com/imagen.png?v=1';
    const nueva = 'https://storage.example.com/imagen.png?v=2';
    await servicio.descargarRemota('u1', 'p1', vieja);
    expect(await servicio.buscarRemota('u1', 'p1', nueva), isNull);
    await servicio.descargarRemota('u1', 'p1', nueva);
    expect(await servicio.buscarRemota('u1', 'p1', nueva), isNotNull);
    servicio.cerrarCliente();
  });

  test('HTTP fallido no crea un archivo de imagen falso', () async {
    final servicio = ImagenesProductoLocales(
      raiz: temporal,
      cliente: MockClient((_) async => http.Response('error', 503)),
    );
    const url = 'https://storage.example.com/imagen.png';
    await expectLater(
      servicio.descargarRemota('u1', 'p1', url),
      throwsA(isA<HttpException>()),
    );
    expect(await servicio.buscarRemota('u1', 'p1', url), isNull);
    servicio.cerrarCliente();
  });

  test('rechaza archivos vacios y descargas demasiado grandes', () async {
    final vacia = await imagenTemporal('vacia.jpg', []);
    await expectLater(
      imagenes.guardarSeleccionada('u1', 'p1', vacia),
      throwsStateError,
    );
    final servicio = ImagenesProductoLocales(
      raiz: temporal,
      cliente: MockClient(
        (_) async => http.Response.bytes(
          Uint8List(ImagenesProductoLocales.limiteBytes + 1),
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );
    const url = 'https://storage.example.com/grande.png';
    await expectLater(
      servicio.descargarRemota('u1', 'p1', url),
      throwsStateError,
    );
    expect(await servicio.buscarRemota('u1', 'p1', url), isNull);
    servicio.cerrarCliente();
  });

  test('valida UID, producto y URL antes de guardar', () async {
    final seleccion = await imagenTemporal('seleccion.jpg', foto);
    await expectLater(
      imagenes.guardarSeleccionada('', 'p1', seleccion),
      throwsArgumentError,
    );
    await expectLater(
      imagenes.guardarSeleccionada('u1', '', seleccion),
      throwsArgumentError,
    );
    await expectLater(
      imagenes.descargarRemota('u1', 'p1', 'file:///etc/a'),
      throwsArgumentError,
    );
  });
}
