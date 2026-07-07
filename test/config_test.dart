import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/config.dart';

void main() {
  group('AppConfig Tests', () {
    test('Версия приложения определена', () {
      expect(AppConfig.appVersion, isNotEmpty);
      // Должна быть похожа на SemVer, допускаем префикс 'v' (например: v1.0.0)
      expect(AppConfig.appVersion, matches(RegExp(r'^v?\d+\.\d+\.\d+.*$')));
    });

    test('Генерация WebSocket URL', () {
      const publicKey = 'test_public_key_123';
      final url = AppConfig.webSocketUrl(publicKey);

      expect(url, contains('wss://'));
      expect(url, contains(publicKey));
      expect(url, contains(AppConfig.serverIp));
    });

    test('Генерация WebSocket URL с специальными символами', () {
      const publicKey = 'key+with/special=chars';
      final url = AppConfig.webSocketUrl(publicKey);

      // URL должен быть правильно закодирован
      expect(url, isNotEmpty);
      expect(url, contains('wss://'));
    });

    test('Генерация HTTP URL', () {
      final url = AppConfig.httpUrl('/api/test');

      expect(url, contains('https://'));
      expect(url, contains(AppConfig.serverIp));
      expect(url, endsWith('/api/test'));
    });

    test('Список хостов определён и содержит primary', () {
      expect(AppConfig.apiHosts, isNotEmpty);
      expect(AppConfig.apiHosts, contains(AppConfig.primaryApiHost));
    });

    test('httpUrl поддерживает явный host', () {
      final url = AppConfig.httpUrl('/api/test', host: 'example.com');
      expect(url, equals('https://example.com/api/test'));
    });

    test('webSocketUrl поддерживает явный host', () {
      final url = AppConfig.webSocketUrl('pk', host: 'example.com');
      expect(url, equals('wss://example.com/ws/pk'));
    });

    test('httpUrls возвращает URL для всех хостов', () {
      final urls = AppConfig.httpUrls('/api/check-update').toList();
      expect(urls.length, equals(AppConfig.apiHosts.length));
      for (final h in AppConfig.apiHosts) {
        expect(urls, contains('https://$h/api/check-update'));
      }
    });

    test('Генерация HTTP URL с разными путями', () {
      final url1 = AppConfig.httpUrl('/api/check-update');
      final url2 = AppConfig.httpUrl('/api/users');

      expect(url1, contains('/api/check-update'));
      expect(url2, contains('/api/users'));
      expect(url1, startsWith('https://'));
      expect(url2, startsWith('https://'));
    });

    test('Changelog данные присутствуют', () {
      expect(AppConfig.changelogData, isNotEmpty);
      expect(AppConfig.changelogData.length, greaterThan(0));
    });

    test('Changelog содержит необходимые поля', () {
      for (final entry in AppConfig.changelogData) {
        expect(entry.containsKey('version'), isTrue);
        expect(entry.containsKey('date'), isTrue);
        expect(entry.containsKey('changes'), isTrue);
        expect(entry['changes'], isA<List>());
      }
    });

    test('Changelog версии корректны', () {
      for (final entry in AppConfig.changelogData) {
        final version = entry['version'] as String;
        expect(version, isNotEmpty);
      }
    });
  });

  group('AppConfig runtime host switch', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      // static _activeHost — сбрасываем на прод, чтобы не протекало между тестами.
      await AppConfig.setActiveHost(AppConfig.primaryApiHost);
    });

    test('setActiveHost на тестовый хост — serverIp/apiHosts/httpUrl следуют',
        () async {
      await AppConfig.setActiveHost(AppConfig.testApiHost);
      expect(AppConfig.serverIp, AppConfig.testApiHost);
      expect(AppConfig.apiHosts, [AppConfig.testApiHost]);
      expect(AppConfig.isTestHost, isTrue);
      expect(AppConfig.httpUrl('/x'), 'https://${AppConfig.testApiHost}/x');
    });

    test('хост вне allowlist игнорируется', () async {
      await AppConfig.setActiveHost(AppConfig.testApiHost);
      await AppConfig.setActiveHost('evil.example.com');
      expect(AppConfig.serverIp, AppConfig.testApiHost);
    });

    test('reloadActiveHostFromPrefs: мусор -> откат на прод', () async {
      SharedPreferences.setMockInitialValues(
          {AppConfig.kPrefActiveHost: 'evil.example.com'});
      final prefs = await SharedPreferences.getInstance();
      final resolved = await AppConfig.reloadActiveHostFromPrefs(prefs);
      expect(resolved, AppConfig.primaryApiHost);
      expect(AppConfig.serverIp, AppConfig.primaryApiHost);
    });

    test('reloadActiveHostFromPrefs: валидный тестовый хост применяется',
        () async {
      SharedPreferences.setMockInitialValues(
          {AppConfig.kPrefActiveHost: AppConfig.testApiHost});
      final prefs = await SharedPreferences.getInstance();
      final resolved = await AppConfig.reloadActiveHostFromPrefs(prefs);
      expect(resolved, AppConfig.testApiHost);
    });
  });
}




