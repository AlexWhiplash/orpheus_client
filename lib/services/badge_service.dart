// lib/services/badge_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';

/// Тип бейджа пользователя
enum BadgeType {
  core,
  owner,
  patron,
  benefactor,
  early,
}

/// Информация о бейдже для отображения
class BadgeInfo {
  final BadgeType type;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const BadgeInfo({
    required this.type,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  /// Строковое представление типа
  String get typeString => type.name;

  /// Все доступные бейджи
  static const Map<BadgeType, BadgeInfo> badges = {
    BadgeType.core: BadgeInfo(
      type: BadgeType.core,
      label: 'CORE',
      backgroundColor: Color(0xFFA91B47),
      textColor: Color(0xFFFFFFFF),
    ),
    BadgeType.owner: BadgeInfo(
      type: BadgeType.owner,
      label: 'OWNER',
      backgroundColor: Color(0xFF1E3A8A),  // Королевский синий
      textColor: Color(0xFFFFFFFF),
    ),
    BadgeType.patron: BadgeInfo(
      type: BadgeType.patron,
      label: 'PATRON',
      backgroundColor: Color(0xFF6B4E9E),
      textColor: Color(0xFFE8E0F0),
    ),
    BadgeType.benefactor: BadgeInfo(
      type: BadgeType.benefactor,
      label: 'BENEFACTOR',
      backgroundColor: Color(0xFFFFB300),  // Золотой
      textColor: Color(0xFF1A1A1A),         // Тёмный текст на золоте
    ),
    BadgeType.early: BadgeInfo(
      type: BadgeType.early,
      label: 'EARLY',
      backgroundColor: Color(0xFF4A4E54),
      textColor: Color(0xFFB0B8C0),
    ),
  };

  /// Получить BadgeInfo по строковому типу
  static BadgeInfo? fromString(String? badgeType) {
    if (badgeType == null || badgeType.isEmpty) return null;
    
    switch (badgeType.toLowerCase()) {
      case 'core':
        return badges[BadgeType.core];
      case 'owner':
        return badges[BadgeType.owner];
      case 'patron':
        return badges[BadgeType.patron];
      case 'benefactor':
        return badges[BadgeType.benefactor];
      case 'early':
        return badges[BadgeType.early];
      default:
        return null;
    }
  }
}

/// Сервис для получения и кеширования бейджей пользователей
class BadgeService {
  static final BadgeService instance = BadgeService._internal();
  BadgeService._internal();

  /// Кеш бейджей: pubkey -> badge_type (или null если нет бейджа)
  final Map<String, String?> _badgeCache = {};
  
  /// Время последнего запроса для каждого pubkey (для избежания частых запросов)
  final Map<String, DateTime> _lastFetch = {};

  /// Запросы «в полёте»: pubkey -> Future, чтобы одновременные вызовы по одному
  /// ключу переиспользовали один сетевой запрос, а не плодили дубли (аудит PERF-4).
  final Map<String, Future<BadgeInfo?>> _inFlight = {};
  
  /// Минимальный интервал между запросами для одного pubkey
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  /// Таймаут для HTTP запросов
  static const Duration _networkTimeout = Duration(seconds: 5);

  /// Получить бейдж пользователя (с кешированием)
  Future<BadgeInfo?> getBadge(String pubkey) async {
    // Проверяем кеш
    if (_badgeCache.containsKey(pubkey)) {
      final lastFetch = _lastFetch[pubkey];
      if (lastFetch != null &&
          DateTime.now().difference(lastFetch) < _cacheDuration) {
        // Возвращаем из кеша
        return BadgeInfo.fromString(_badgeCache[pubkey]);
      }
    }

    // Дедуп: если запрос по этому pubkey уже идёт — переиспользуем его,
    // не создавая второй сетевой запрос (аудит PERF-4).
    return _inFlight.putIfAbsent(
      pubkey,
      () => _fetchAndCache(pubkey).whenComplete(() => _inFlight.remove(pubkey)),
    );
  }

  /// Запрос бейджа с сервера + запись в кеш. При ошибке возвращает то, что было
  /// в кеше (или null).
  Future<BadgeInfo?> _fetchAndCache(String pubkey) async {
    try {
      final badgeType = await _fetchBadgeFromServer(pubkey);
      _badgeCache[pubkey] = badgeType;
      _lastFetch[pubkey] = DateTime.now();
      return BadgeInfo.fromString(badgeType);
    } catch (e) {
      print('[BADGE] Error fetching badge for ${pubkey.substring(0, 16)}...: $e');
      return BadgeInfo.fromString(_badgeCache[pubkey]);
    }
  }

  /// Получить бейдж синхронно из кеша (без запроса к серверу)
  BadgeInfo? getBadgeCached(String pubkey) {
    return BadgeInfo.fromString(_badgeCache[pubkey]);
  }

  /// Предзагрузить бейджи для списка контактов
  Future<void> preloadBadges(List<String> pubkeys) async {
    // Фильтруем те, которые не в кеше или устарели
    final toFetch = pubkeys.where((pk) {
      final lastFetch = _lastFetch[pk];
      if (lastFetch == null) return true;
      return DateTime.now().difference(lastFetch) >= _cacheDuration;
    }).toList();

    // Загружаем параллельно (но не более 5 одновременно)
    const batchSize = 5;
    for (var i = 0; i < toFetch.length; i += batchSize) {
      final batch = toFetch.skip(i).take(batchSize);
      await Future.wait(batch.map((pk) => getBadge(pk)));
    }
  }

  /// Очистить кеш
  void clearCache() {
    _badgeCache.clear();
    _lastFetch.clear();
  }

  /// Инвалидировать кеш для конкретного пользователя
  void invalidate(String pubkey) {
    _badgeCache.remove(pubkey);
    _lastFetch.remove(pubkey);
  }

  /// Запрос бейджа с сервера
  Future<String?> _fetchBadgeFromServer(String pubkey) async {
    final encodedPubkey = Uri.encodeComponent(pubkey);
    final path = '/api/badges/$encodedPubkey';

    for (final urlStr in AppConfig.httpUrls(path)) {
      try {
        final uri = Uri.parse(urlStr);
        final response = await http.get(uri).timeout(_networkTimeout);
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final badge = data['badge'];
          print('[BADGE] Fetched badge for ${pubkey.substring(0, 16)}...: $badge');
          return badge as String?;
        }
      } catch (e) {
        // Пробуем следующий хост
        continue;
      }
    }
    
    return null;
  }
}

