import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';

void main() {
  group('UpdateService Tests', () {
    tearDown(() {
      UpdateService.debugResetForTesting();
    });

    test('resolveDownloadUrl: абсолютный URL не меняется', () {
      const url = 'https://update.orpheus.click/orpheus.apk';
      expect(UpdateService.resolveDownloadUrl(url), equals(url));
    });

    test('resolveDownloadUrl: относительный путь резолвится через AppConfig', () {
      const path = '/download';
      expect(UpdateService.resolveDownloadUrl(path), equals(AppConfig.httpUrl(path)));
    });

    test('getWithFallback: возвращает ответ основного хоста', () async {
      final called = <Uri>[];
      UpdateService.debugHttpGet = (uri) async {
        called.add(uri);
        return http.Response('ok', 200);
      };

      final resp = await UpdateService.debugGetWithFallbackForTesting('/api/check-update');
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(200));
      expect(resp.body, equals('ok'));

      // Список хостов сейчас единственный (legacy-домен убран ради приватности),
      // поэтому запрос уходит только на primary host.
      expect(called.map((u) => u.host).toList(), equals([AppConfig.primaryApiHost]));
    });

    test('getWithFallback: возвращает null, когда все хосты недоступны', () async {
      final called = <Uri>[];
      UpdateService.debugHttpGet = (uri) async {
        called.add(uri);
        throw http.ClientException('boom');
      };

      final resp = await UpdateService.debugGetWithFallbackForTesting('/api/check-update');
      expect(resp, isNull);
      // Перебирает все известные хосты (сейчас — один) и сдаётся.
      expect(called.map((u) => u.host).toList(), equals([AppConfig.primaryApiHost]));
    });

    testWidgets('checkForUpdate: показывает диалог, когда serverBuild > currentBuild, и закрывается по "ПОЗЖЕ"', (tester) async {
      UpdateService.debugResetForTesting();
      UpdateService.debugCurrentBuildNumberOverride = 1;
      UpdateService.debugHttpGet = (uri) async {
        return http.Response(
          '{"version_code":2,"download_url":"/download","version_name":"1.1.0","required":false}',
          200,
        );
      };

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );

      await UpdateService.checkForUpdate(ctx);
      await tester.pumpAndSettle();

      expect(find.text('Доступно обновление'), findsOneWidget);
      expect(find.text('Позже'), findsOneWidget);
      expect(find.text('Скачать'), findsOneWidget);

      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();

      expect(find.text('Доступно обновление'), findsNothing);
    });

    testWidgets('checkForUpdate: required=true скрывает кнопку "ПОЗЖЕ"', (tester) async {
      UpdateService.debugResetForTesting();
      UpdateService.debugCurrentBuildNumberOverride = 1;
      UpdateService.debugHttpGet = (uri) async {
        return http.Response(
          '{"version_code":2,"download_url":"/download","version_name":"1.1.0","required":true}',
          200,
        );
      };

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );

      await UpdateService.checkForUpdate(ctx);
      await tester.pumpAndSettle();

      expect(find.text('Доступно обновление'), findsOneWidget);
      expect(find.text('Позже'), findsNothing);
      expect(find.text('Скачать'), findsOneWidget);
    });

    testWidgets('checkForUpdate: не показывает диалог, когда serverBuild <= currentBuild', (tester) async {
      UpdateService.debugResetForTesting();
      UpdateService.debugCurrentBuildNumberOverride = 2;
      UpdateService.debugHttpGet = (uri) async {
        return http.Response(
          '{"version_code":2,"download_url":"/download","version_name":"1.1.0","required":false}',
          200,
        );
      };

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );

      await UpdateService.checkForUpdate(ctx);
      await tester.pumpAndSettle();

      expect(find.text('Доступно обновление'), findsNothing);
    });
  });
}

