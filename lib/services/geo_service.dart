// lib/services/geo_service.dart
// Определение страны по IP через цепочку сторонних HTTPS geo-сервисов.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';

/// Один HTTPS-эндпоинт цепочки. [parse] извлекает сырое значение страны
/// из тела ответа (plain text или поле JSON).
class GeoEndpoint {
  GeoEndpoint(this.url, this.parse) : assert(url.startsWith('https://'));

  final String url;
  final String? Function(String body) parse;
}

/// Страна пользователя по IP через сторонние сервисы.
///
/// Privacy-контракт:
/// - вызывается ТОЛЬКО с экрана «Система» (открытие экрана — явное действие
///   пользователя); никаких фоновых запросов;
/// - запрос без идентифицирующих заголовков (дефолтный Dart User-Agent —
///   общий для всех Dart-приложений, кастомный был бы фингерпринтом);
/// - сервис видит IP вызывающего — это сам механизм определения; эндпоинты
///   без ключей и квот, на двух разных инфраструктурах (Google LB +
///   Cloudflare), чтобы пережить деградацию любой одной из них;
/// - при любом сбое возвращает null — вызывающий падает на локаль устройства.
class GeoService {
  GeoService._({
    http.Client? httpClient,
    List<GeoEndpoint>? endpoints,
    Future<bool> Function()? isOnline,
  })  : _httpOverride = httpClient,
        _endpoints = endpoints ?? _defaultEndpoints,
        _isOnline = isOnline;

  static final GeoService instance = GeoService._();

  @visibleForTesting
  factory GeoService.forTesting({
    http.Client? httpClient,
    List<GeoEndpoint>? endpoints,
    Future<bool> Function()? isOnline,
  }) = GeoService._;

  static const String _prefsCodeKey = 'geo_country_code';
  static const String _prefsTsKey = 'geo_country_ts';
  static const Duration _cacheTtl = Duration(hours: 12);
  static const Duration _requestTimeout = Duration(seconds: 4);
  static const int _maxBodyBytes = 2048;

  static final RegExp _countryPattern = RegExp(r'^[A-Z]{2}$');

  // ipinfo.io — инфраструктура Google (не Cloudflare, что критично при
  // троттлинге Cloudflare со стороны РКН); country.is и geojs.io — Cloudflare,
  // без ключей и квот. Первый успешный ответ побеждает.
  static final List<GeoEndpoint> _defaultEndpoints = [
    GeoEndpoint('https://ipinfo.io/country', (body) => body),
    GeoEndpoint(
      'https://api.country.is/',
      (body) => (jsonDecode(body) as Map<String, dynamic>)['country'] as String?,
    ),
    GeoEndpoint('https://get.geojs.io/v1/ip/country', (body) => body),
  ];

  final http.Client? _httpOverride;
  final List<GeoEndpoint> _endpoints;
  final Future<bool> Function()? _isOnline;

  String? _cachedCode;
  DateTime? _cachedAt;
  Future<void>? _prefsLoad;
  Future<String?>? _inflight;

  /// Страна по IP (ISO 3166-1 alpha-2) или null, если цепочка недоступна.
  /// Свежий кэш (моложе 12 ч) возвращается без сетевого запроса;
  /// [forceRefresh] пробивает кэш.
  Future<String?> getIpCountry({bool forceRefresh = false}) async {
    await (_prefsLoad ??= _loadPrefsCache());

    // Отрицательная разница (timestamp из будущего — сбитые часы) = не свежий.
    final age = _cachedAt == null
        ? null
        : DateTime.now().difference(_cachedAt!);
    final isFresh = age != null && age >= Duration.zero && age < _cacheTtl;
    if (!forceRefresh && _cachedCode != null && isFresh) return _cachedCode;

    try {
      final online = await (_isOnline ?? NetworkMonitorService.instance.isOnline)();
      if (!online) return _cachedCode;
    } catch (_) {
      // Сбой монитора сети не должен блокировать цепочку — пробуем запрос.
    }

    final fetch = _inflight ??=
        _fetchChain().whenComplete(() => _inflight = null);
    final result = await fetch;
    return result ?? _cachedCode;
  }

  Future<String?> _fetchChain() async {
    final client = _httpOverride ?? http.Client();
    try {
      for (final endpoint in _endpoints) {
        final code = await _fetchOne(client, endpoint);
        if (code != null) {
          _storeCache(code);
          return code;
        }
      }
      return null;
    } finally {
      if (_httpOverride == null) client.close();
    }
  }

  Future<String?> _fetchOne(http.Client client, GeoEndpoint endpoint) async {
    try {
      final request = http.Request('GET', Uri.parse(endpoint.url))
        ..followRedirects = false;
      final response = await client.send(request).timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      if ((response.contentLength ?? 0) > _maxBodyBytes) return null;
      final bytes = await _readCapped(response.stream);
      if (bytes == null) return null;
      final code = endpoint.parse(utf8.decode(bytes))?.trim().toUpperCase();
      if (code == null || !_countryPattern.hasMatch(code)) return null;
      return code;
    } catch (_) {
      return null;
    }
  }

  /// Читает тело с жёстким лимитом байт и таймаутом, отменяя подписку на
  /// поток при превышении: chunked-ответ без Content-Length или бесконечный
  /// slow-drip от скомпрометированного эндпоинта не раздувает память.
  Future<List<int>?> _readCapped(http.ByteStream stream) {
    final completer = Completer<List<int>?>();
    final builder = BytesBuilder(copy: false);
    late final StreamSubscription<List<int>> sub;

    void finish(List<int>? result) {
      sub.cancel();
      if (!completer.isCompleted) completer.complete(result);
    }

    sub = stream.listen(
      (chunk) {
        builder.add(chunk);
        if (builder.length > _maxBodyBytes) finish(null);
      },
      onDone: () => finish(builder.takeBytes()),
      onError: (_) => finish(null),
      cancelOnError: true,
    );
    final timer = Timer(_requestTimeout, () => finish(null));
    return completer.future.whenComplete(timer.cancel);
  }

  void _storeCache(String code) {
    _cachedCode = code;
    _cachedAt = DateTime.now();
    // Fire-and-forget: prefs-кэш не критичен (panic wipe чистит его
    // общим prefs.clear()).
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString(_prefsCodeKey, code);
      await prefs.setInt(_prefsTsKey, _cachedAt!.millisecondsSinceEpoch);
    }).catchError((_) {});
  }

  Future<void> _loadPrefsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsCodeKey);
      final ts = prefs.getInt(_prefsTsKey);
      if (code != null && ts != null && _countryPattern.hasMatch(code)) {
        _cachedCode = code;
        _cachedAt = DateTime.fromMillisecondsSinceEpoch(ts);
      }
    } catch (_) {}
  }
}
