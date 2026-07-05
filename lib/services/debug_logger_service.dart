// lib/services/debug_logger_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Глобальный сервис логирования для отладки на реальных устройствах
/// 
/// Использование:
/// ```dart
/// DebugLogger.log('WS', 'Подключение к серверу');
/// DebugLogger.log('CALL', 'Входящий звонок от ${contactName}');
/// ```
class DebugLogger {
  // Singleton
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  // Максимальное количество хранимых логов
  static const int _maxLogs = 1000;

  // Хранилище логов
  static final List<LogEntry> _logs = [];

  // Stream для уведомления UI об обновлениях
  static final StreamController<void> _updateController = StreamController.broadcast();
  static Stream<void> get onUpdate => _updateController.stream;

  // Stream для передачи каждого лога (телеметрия/анализ)
  static final StreamController<LogEntry> _entryController = StreamController.broadcast();
  static Stream<LogEntry> get onEntry => _entryController.stream;

  // === Персистентное файловое логирование (для тест-сборок) ===
  // Пишем логи в файл, чтобы они переживали рестарт приложения и их можно было
  // выгрузить/переслать (кнопка «Поделиться» в экране отладки) без подключения
  // телефона к ПК. Включается через enableFileLogging() из main (за флагом
  // AppConfig.debugFileLogging).
  static IOSink? _fileSink;
  static File? _logFile;
  static bool _fileEnabled = false;
  static const int _maxFileBytes = 4 * 1024 * 1024; // ~4 МБ, дальше ротация

  /// Включить запись логов в файл (переживают рестарт). Идемпотентно, best-effort.
  static Future<void> enableFileLogging() async {
    if (_fileEnabled) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/orpheus_debug.log');
      // Ротация: слишком большой файл -> оставляем последнюю половину.
      if (await f.exists() && await f.length() > _maxFileBytes) {
        final content = await f.readAsString();
        await f.writeAsString(content.substring(content.length ~/ 2));
      }
      _logFile = f;
      _fileSink = f.openWrite(mode: FileMode.append);
      _fileEnabled = true;
      _fileSink!.writeln(
          '\n=== SESSION START ${DateTime.now().toIso8601String()} ===');
      // Досыпаем накопленное в RAM до включения файла.
      for (final e in _logs) {
        _fileSink!.writeln(e.toFormattedString());
      }
    } catch (_) {
      _fileEnabled = false;
    }
  }

  static bool get isFileLoggingEnabled => _fileEnabled;

  /// Путь к файлу логов (для шаринга). Сбрасывает буфер на диск.
  static Future<String?> flushAndGetLogFilePath() async {
    try {
      await _fileSink?.flush();
    } catch (_) {}
    return _logFile?.path;
  }

  /// Добавить лог
  static void log(
    String tag,
    String message, {
    LogLevel level = LogLevel.info,
    Map<String, dynamic>? context,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
      context: context,
    );
    
    _logs.add(entry);
    
    // Ограничиваем размер
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    
    // Уведомляем UI и телеметрию
    _updateController.add(null);
    _entryController.add(entry);

    // Персистентная запись в файл (тест-сборки) — переживает рестарт.
    if (_fileEnabled) {
      try {
        _fileSink?.writeln(entry.toFormattedString());
      } catch (_) {}
    }

    // В release НЕ пишем в системный logcat (утечка метаданных/событий
    // безопасности на рутованном устройстве / в bug-report — аудит QUAL-1/OPS-6).
    // Логи по-прежнему доступны в in-app экране отладки (RAM-буфер) и телеметрии.
    if (kDebugMode) {
      print('[${entry.levelIcon}] [${entry.tag}] ${entry.message}');
    }
  }

  /// Информационный лог
  static void info(String tag, String message, {Map<String, dynamic>? context}) {
    log(tag, message, level: LogLevel.info, context: context);
  }

  /// Предупреждение
  static void warn(String tag, String message, {Map<String, dynamic>? context}) {
    log(tag, message, level: LogLevel.warning, context: context);
  }

  /// Ошибка
  static void error(String tag, String message, {Map<String, dynamic>? context}) {
    log(tag, message, level: LogLevel.error, context: context);
  }

  /// Успех
  static void success(String tag, String message, {Map<String, dynamic>? context}) {
    log(tag, message, level: LogLevel.success, context: context);
  }

  /// Получить все логи
  static List<LogEntry> get logs => List.unmodifiable(_logs);

  /// Получить логи по тегу
  static List<LogEntry> getLogsByTag(String tag) {
    return _logs.where((e) => e.tag == tag).toList();
  }

  /// Очистить все логи
  static void clear() {
    _logs.clear();
    _updateController.add(null);
  }

  /// Экспорт логов в текст
  static String exportToText() {
    final buffer = StringBuffer();
    buffer.writeln('=== ORPHEUS DEBUG LOGS ===');
    buffer.writeln('Export: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total entries: ${_logs.length}');
    buffer.writeln('');
    
    for (final entry in _logs) {
      buffer.writeln(entry.toFormattedString());
    }
    
    return buffer.toString();
  }
}

/// Уровни логирования
enum LogLevel {
  info,
  warning,
  error,
  success,
}

/// Запись лога
class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final LogLevel level;
  final Map<String, dynamic>? context;

  LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    required this.level,
    this.context,
  });

  String get levelIcon {
    switch (level) {
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.success:
        return '✅';
    }
  }

  String get timeString {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}.'
           '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  String toFormattedString() {
    final ctx = context != null && context!.isNotEmpty
        ? ' | ${context.toString()}'
        : '';
    return '[$timeString] [$levelIcon $tag] $message$ctx';
  }
}

