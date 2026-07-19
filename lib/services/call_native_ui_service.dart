import 'package:flutter/services.dart';

/// Мост в Android MainActivity для управления поведением во время звонка:
/// - showWhenLocked / turnScreenOn
/// - (опционально) dismiss keyguard
///
/// Важно: best-effort. Отсутствие нативной реализации не должно ломать звонки.
class CallNativeUiService {
  static const MethodChannel _callChannel = MethodChannel('com.example.orpheus_project/call');

  static Future<void> enableCallMode() async {
    try {
      await _callChannel.invokeMethod('enableCallMode');
    } catch (_) {
      // best-effort
    }
  }

  static Future<void> disableCallMode() async {
    try {
      await _callChannel.invokeMethod('disableCallMode');
    } catch (_) {
      // best-effort
    }
  }

  /// Поднять нативный микрофонный foreground-сервис на время звонка (Android).
  /// Держит микрофон, когда приложение свёрнуто во время разговора. Вызывать из
  /// видимого CallScreen (иначе старт microphone-FGS отклонят правила Android 14).
  static Future<void> startCallAudio({String? title}) async {
    try {
      await _callChannel.invokeMethod('startCallAudio', {'title': title});
    } catch (_) {
      // best-effort: обычный звонок при видимом экране и так получает микрофон.
    }
  }

  /// Остановить микрофонный сервис (звонок завершён).
  static Future<void> stopCallAudio() async {
    try {
      await _callChannel.invokeMethod('stopCallAudio');
    } catch (_) {
      // best-effort
    }
  }

  /// Взять proximity wake lock: экран гаснет и тач отключается, пока датчик у уха
  /// закрыт (как штатная звонилка; заодно защищает от ушных тапов по кнопкам).
  /// Брать при соединении и выключенном динамике. Best-effort.
  static Future<void> acquireProximityLock() async {
    try {
      await _callChannel.invokeMethod('acquireProximityLock');
    } catch (_) {
      // best-effort: нет датчика/реализации -> просто без гашения экрана.
    }
  }

  /// Отпустить proximity wake lock (динамик включён / звонок завершён).
  static Future<void> releaseProximityLock() async {
    try {
      await _callChannel.invokeMethod('releaseProximityLock');
    } catch (_) {
      // best-effort
    }
  }
}


