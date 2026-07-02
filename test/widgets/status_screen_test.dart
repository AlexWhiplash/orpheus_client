import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/status_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('StatusScreen: smoke (без таймеров) и отображает заголовок',
      (tester) async {
    // Регион теперь берётся из локали устройства (никаких сетевых запросов),
    // поэтому http-мок больше не нужен.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: StatusScreen(
          disableTimersForTesting: true,
          debugPublicKeyBase64: 'ABCDEFGH1234',
          // databaseService/websocket/messageUpdates оставляем дефолтными: тест smoke.
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Система'), findsOneWidget);
  });
}
