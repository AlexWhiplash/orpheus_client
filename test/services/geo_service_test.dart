import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orpheus_project/services/geo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  GeoEndpoint textEndpoint(String host) =>
      GeoEndpoint('https://$host/country', (body) => body);

  GeoEndpoint jsonEndpoint(String host) => GeoEndpoint(
        'https://$host/',
        (body) => (jsonDecode(body) as Map<String, dynamic>)['country'] as String?,
      );

  test('первый эндпоинт отвечает — возвращает код, один запрос', () async {
    var calls = 0;
    final geo = GeoService.forTesting(
      httpClient: MockClient((req) async {
        calls++;
        return http.Response('RU\n', 200);
      }),
      endpoints: [textEndpoint('a.test')],
      isOnline: () async => true,
    );

    expect(await geo.getIpCountry(), 'RU');
    expect(calls, 1);
  });

  test('первый упал (500) — побеждает второй, lowercase нормализуется',
      () async {
    final geo = GeoService.forTesting(
      httpClient: MockClient((req) async {
        if (req.url.host == 'a.test') return http.Response('oops', 500);
        return http.Response('{"ip":"1.2.3.4","country":"nl"}', 200);
      }),
      endpoints: [textEndpoint('a.test'), jsonEndpoint('b.test')],
      isOnline: () async => true,
    );

    expect(await geo.getIpCountry(), 'NL');
  });

  test('исключение и мусорные ответы отвергаются — null', () async {
    final geo = GeoService.forTesting(
      httpClient: MockClient((req) async {
        switch (req.url.host) {
          case 'a.test':
            throw Exception('network down');
          case 'b.test':
            return http.Response('<html>error</html>', 200);
          default:
            return http.Response('RU1', 200);
        }
      }),
      endpoints: [
        textEndpoint('a.test'),
        textEndpoint('b.test'),
        textEndpoint('c.test'),
      ],
      isOnline: () async => true,
    );

    expect(await geo.getIpCountry(), isNull);
  });

  test('редирект (3xx) — провал эндпоинта, переход к следующему', () async {
    final requests = <http.Request>[];
    final geo = GeoService.forTesting(
      httpClient: MockClient((req) async {
        requests.add(req);
        if (req.url.host == 'a.test') {
          return http.Response('', 302,
              headers: {'location': 'https://evil.test/'});
        }
        return http.Response('DE', 200);
      }),
      endpoints: [textEndpoint('a.test'), textEndpoint('b.test')],
      isOnline: () async => true,
    );

    expect(await geo.getIpCountry(), 'DE');
    // Реальный IOClient (в отличие от MockClient) следует редиректам, если
    // followRedirects не выключен — фиксируем намерение явно.
    expect(requests.map((r) => r.followRedirects), everyElement(isFalse));
  });

  test('слишком большое тело отвергается', () async {
    final geo = GeoService.forTesting(
      httpClient: MockClient((req) async {
        return http.Response('x' * 5000, 200);
      }),
      endpoints: [textEndpoint('a.test')],
      isOnline: () async => true,
    );

    expect(await geo.getIpCountry(), isNull);
  });

  test('кэш: повторный вызов в TTL не ходит в сеть, forceRefresh пробивает',
      () async {
    var calls = 0;
    final geo = GeoService.forTesting(
      httpClient: MockClient((req) async {
        calls++;
        return http.Response('RU', 200);
      }),
      endpoints: [textEndpoint('a.test')],
      isOnline: () async => true,
    );

    expect(await geo.getIpCountry(), 'RU');
    expect(await geo.getIpCountry(), 'RU');
    expect(calls, 1);

    expect(await geo.getIpCountry(forceRefresh: true), 'RU');
    expect(calls, 2);
  });

  test('офлайн: сеть не трогается, возвращается кэш или null', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('RU', 200);
    });

    final cold = GeoService.forTesting(
      httpClient: client,
      endpoints: [textEndpoint('a.test')],
      isOnline: () async => false,
    );
    expect(await cold.getIpCountry(), isNull);
    expect(calls, 0);

    SharedPreferences.setMockInitialValues({
      'geo_country_code': 'RU',
      'geo_country_ts': DateTime.now().millisecondsSinceEpoch,
    });
    final cached = GeoService.forTesting(
      httpClient: client,
      endpoints: [textEndpoint('a.test')],
      isOnline: () async => false,
    );
    expect(await cached.getIpCountry(), 'RU');
    expect(calls, 0);
  });

  test('протухший prefs-кэш: идёт в сеть, при провале возвращает старое значение',
      () async {
    SharedPreferences.setMockInitialValues({
      'geo_country_code': 'KZ',
      'geo_country_ts': DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
    });
    final geo = GeoService.forTesting(
      httpClient: MockClient((req) async => http.Response('oops', 500)),
      endpoints: [textEndpoint('a.test')],
      isOnline: () async => true,
    );

    expect(await geo.getIpCountry(), 'KZ');
  });
}
