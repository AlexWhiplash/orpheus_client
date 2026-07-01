import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/qr_scan_screen.dart';

void main() {
  group('QrScanScreen widget tests', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    testWidgets('Smoke: показывает заголовок и подсказку', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: QrScanScreen(
            scannerBuilder: (context, onQrValue) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('СКАНИРОВАТЬ QR-КОД'), findsOneWidget);
      expect(find.text('Наведите камеру на QR-код'), findsOneWidget);
    });

    testWidgets('Скан: onQrValue закрывает экран и возвращает строку', (tester) async {
      String? result;
      late Future<void> Function(String value) onQrValue;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => QrScanScreen(
                            scannerBuilder: (context, cb) {
                              onQrValue = cb;
                              return const ColoredBox(color: Colors.black);
                            },
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      // Экран содержит бесконечные анимации, поэтому pumpAndSettle() будет таймаутиться.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('СКАНИРОВАТЬ QR-КОД'), findsOneWidget);

      // В реальности значение прилетает из камеры. В тесте вызываем callback напрямую.
      onQrValue('PUBLIC_KEY_ABC');
      // Внутри есть delay(500ms) перед pop
      await tester.pump(const Duration(milliseconds: 600));
      // На экране много бесконечных анимаций, поэтому pumpAndSettle() может таймаутиться.
      await tester.pump(const Duration(milliseconds: 200));

      expect(result, equals('PUBLIC_KEY_ABC'));
    });
  });
}


