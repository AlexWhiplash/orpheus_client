import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart' show cryptoService, isAppInForeground;
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';

/// Отправка клиентских логов на сервер для отладки.
///
/// ВЫКЛЮЧЕНА по умолчанию (opt-in): включается только явно через [setEnabled]
/// (например, из скрытого экрана отладочных логов). Даже во включённом виде
/// НЕ выгружает личности контактов (`peer_pubkey` и т.п.) и отпечаток устройства —
/// см. AUDIT_REPORT SEC-2.
class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  static const int _maxQueueSize = 5000;
  static const int _batchSize = 50;
  static const Duration _flushInterval = Duration(seconds: 5);
  static const String _prefsKey = 'telemetry_enabled';

  /// Ключи контекста, идентифицирующие контактов пользователя (граф общения).
  /// Никогда не покидают устройство в телеметрии.
  static const Set<String> _sensitiveContextKeys = {
    'peer_pubkey',
    'caller_key',
    'caller_pubkey',
    'sender_key',
    'sender_pubkey',
    'recipient_pubkey',
    'pubkey',
    'public_key',
  };

  final http.Client _httpClient = http.Client();
  final List<LogEntry> _queue = [];
  StreamSubscription<LogEntry>? _entrySubscription;
  Timer? _flushTimer;
  bool _sending = false;

  String? _osName;

  bool _enabled = false;
  bool get isEnabled => _enabled;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      _enabled = false;
    }
    if (_enabled) _start();
  }

  /// Включить/выключить отправку телеметрии. Значение сохраняется.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
    if (value) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    _osName ??= _detectOs();
    _entrySubscription ??= DebugLogger.onEntry.listen(_onLogEntry);
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => flush());
  }

  void _stop() {
    _entrySubscription?.cancel();
    _entrySubscription = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _queue.clear();
  }

  void _onLogEntry(LogEntry entry) {
    if (!_enabled) return;
    _queue.add(entry);
    if (_queue.length > _maxQueueSize) {
      _queue.removeRange(0, _queue.length - _maxQueueSize);
    }
    if (_queue.length >= _batchSize) {
      flush();
    }
  }

  Future<void> flush() async {
    if (!_enabled || _sending || _queue.isEmpty) return;
    final pubkey = cryptoService.publicKeyBase64;
    if (pubkey == null || pubkey.isEmpty) return;

    _sending = true;
    final batch = _queue.take(_batchSize).toList();
    _queue.removeRange(0, batch.length);

    try {
      final payload = {
        'source': 'client',
        'entries': batch.map(_serializeEntry).toList(),
      };
      final body = json.encode(payload);

      for (final url in AppConfig.httpUrls('/api/logs/batch')) {
        final ok = await _trySend(url, pubkey, body);
        if (ok) break;
      }
    } catch (_) {
      // Ошибки телеметрии не должны влиять на приложение
    } finally {
      _sending = false;
    }
  }

  Map<String, dynamic> _serializeEntry(LogEntry entry) {
    final context = entry.context;
    return {
      'timestamp': entry.timestamp.toIso8601String(),
      'level': entry.level.name,
      'tag': entry.tag,
      'category': entry.tag,
      'message': entry.message,
      // details очищены от личностей контактов; peer_pubkey и отпечаток
      // устройства (device_info) больше НЕ отправляются (AUDIT_REPORT SEC-2).
      'details': _sanitizeContext(context),
      'call_id': (context ?? const {})['call_id'],
      'app_version': AppConfig.appVersion,
      'os': _osName,
      'network': NetworkMonitorService.instance.currentState.name,
      'app_state': isAppInForeground ? 'foreground' : 'background',
    };
  }

  /// Убирает из контекста ключи, идентифицирующие контактов пользователя.
  Map<String, dynamic> _sanitizeContext(Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) return const {};
    final out = <String, dynamic>{};
    context.forEach((k, v) {
      if (!_sensitiveContextKeys.contains(k)) out[k] = v;
    });
    return out;
  }

  Future<bool> _trySend(String url, String pubkey, String body) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Pubkey': pubkey,
        },
        body: body,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _detectOs() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }

  void dispose() {
    _stop();
    _httpClient.close();
  }
}
