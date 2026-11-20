import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimarket_flutter/sync/auto_sync_lifecycle.dart';

void main() {
  testWidgets('intenta al iniciar y periodicamente sin contacto con Firebase', (
    tester,
  ) async {
    var intentos = 0;
    await tester.pumpWidget(
      AutoSyncLifecycle(
        habilitado: true,
        intervalo: const Duration(seconds: 10),
        intentarSincronizacion: () async {
          intentos++;
        },
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    expect(intentos, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(intentos, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no ejecuta intentos simultaneos y libera el bloqueo', (
    tester,
  ) async {
    final primera = Completer<void>();
    var intentos = 0;
    await tester.pumpWidget(
      AutoSyncLifecycle(
        habilitado: true,
        intervalo: const Duration(seconds: 10),
        intentarSincronizacion: () {
          intentos++;
          return intentos == 1 ? primera.future : Future<void>.value();
        },
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    expect(intentos, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(intentos, 1);
    primera.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(intentos, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deshabilitado no crea intentos', (tester) async {
    var intentos = 0;
    await tester.pumpWidget(
      AutoSyncLifecycle(
        habilitado: false,
        intervalo: const Duration(seconds: 10),
        intentarSincronizacion: () async {
          intentos++;
        },
        child: const SizedBox(),
      ),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(intentos, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
