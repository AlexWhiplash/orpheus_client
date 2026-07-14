import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/status_screen.dart';
import 'package:orpheus_project/services/geo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  GeoService fakeGeo(String? country) => GeoService.forTesting(
        httpClient: MockClient((req) async => country == null
            ? http.Response('fail', 500)
            : http.Response(country, 200)),
        endpoints: [GeoEndpoint('https://geo.test/country', (b) => b)],
        isOnline: () async => true,
      );

  Widget buildScreen(GeoService geo) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: StatusScreen(
          disableTimersForTesting: true,
          debugPublicKeyBase64: 'ABCDEFGH1234',
          geoService: geo,
          // databaseService/websocket/messageUpdates оставляем дефолтными: smoke.
        ),
      );

  testWidgets('StatusScreen: smoke (без таймеров) и отображает заголовок',
      (tester) async {
    // IP-geo цепочка мокнута провалом: регион остаётся из локали устройства.
    await tester.pumpWidget(buildScreen(fakeGeo(null)));

    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Система'), findsOneWidget);
    expect(find.text('Из настроек устройства'), findsOneWidget);
  });

  testWidgets(
      'StatusScreen: IP=RU при иностранной локали включает «Усиленный» (union)',
      (tester) async {
    // Локаль тестового окружения en_US (не traffic-control), IP-сервис
    // возвращает RU — union обязан дать Enhanced.
    await tester.pumpWidget(buildScreen(fakeGeo('RU')));

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('RU'), findsOneWidget);
    expect(find.text('Усиленный'), findsOneWidget);
    expect(find.text('По IP • зашифровано'), findsOneWidget);
  });
}
