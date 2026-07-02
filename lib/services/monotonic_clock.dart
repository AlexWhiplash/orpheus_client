// lib/services/monotonic_clock.dart

import 'package:flutter/services.dart';

/// Монотонные часы (Android SystemClock.elapsedRealtime) — миллисекунды с
/// загрузки устройства, НЕуязвимые к смене системного времени.
///
/// Нужны для тамперо-устойчивой прогрессивной блокировки от брутфорса PIN
/// (аудит LOGIC-6): по обычным `DateTime.now()` блокировка обходится переводом
/// часов вперёд. elapsedRealtime так обмануть нельзя.
class MonotonicClock {
  static const MethodChannel _channel =
      MethodChannel('com.example.orpheus_project/settings');

  /// Текущее монотонное время в мс, либо `null` если недоступно (не-Android /
  /// ошибка канала). При `null` вызывающий код откатывается на wall-clock —
  /// то есть поведение не хуже прежнего.
  static Future<int?> elapsedRealtimeMs() async {
    try {
      final v = await _channel.invokeMethod<int>('getElapsedRealtime');
      return v;
    } catch (_) {
      return null;
    }
  }
}
