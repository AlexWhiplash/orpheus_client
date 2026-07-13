import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

/// Персистентная очередь входящих чат-конвертов, доставленных push-изолятом.
///
/// ПРОБЛЕМА: при убитом/фоновом приложении WebSocket держит ТОЛЬКО push-изолят.
/// Для сервера получатель при этом «онлайн», поэтому сервер доставляет сообщение
/// вживую в сокет и НЕ кладёт его в оффлайн-очередь. А push-изолят расшифровать и
/// записать в зашифрованную БД не может (ключей нет) — он лишь показывает
/// обезличенное уведомление. Итог: уведомление есть, а при открытии приложения
/// сообщения нет — оно потеряно (регресс перехода FCM -> постоянный foreground-сервис).
///
/// РЕШЕНИЕ: push-изолят складывает СЫРОЙ (E2E-зашифрованный) конверт сюда, а main-
/// изолят при старте сливает очередь через обычный обработчик входящих
/// (расшифровка + строгий mutual-add + запись в БД + дедуп по message_id).
///
/// На диске лежит только шифртекст payload + публичные поля (адрес отправителя,
/// его enc-ключ, подпись) — расшифровать без ключей из secure storage нельзя,
/// поэтому обычный SharedPreferences здесь приватностно допустим (как в
/// PendingCallStorage). Изоляты — РАЗНЫЕ процессы со своим кэшем prefs, поэтому
/// и запись, и чтение делают reload() для синхронизации с диском.
class PendingInboxStorage {
  static const _key = 'pending_inbox_envelopes';

  /// Предел очереди (страховка от неограниченного роста, если приложение долго
  /// не открывают). Держим последние N — более старые вытесняются.
  static const int _maxItems = 500;

  /// TTL конверта: за пределами окна сообщение считается протухшим и отбрасывается.
  static const int maxAgeMs = 14 * 24 * 60 * 60 * 1000; // 14 суток

  PendingInboxStorage._();
  static final instance = PendingInboxStorage._();

  /// Положить сырой конверт (вызывает push-изолят). Дедуп по message_id, чтобы
  /// повторная доставка не копила дубли. reload() — увидеть записи, сделанные
  /// main-изолятом (другой процесс).
  Future<void> append(Map<String, dynamic> envelope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = prefs.getStringList(_key) ?? <String>[];

      final msgId = envelope['message_id']?.toString();
      if (msgId != null && msgId.isNotEmpty) {
        for (final raw in list) {
          try {
            final env = (json.decode(raw) as Map)['env'];
            if (env is Map && env['message_id']?.toString() == msgId) {
              return; // уже в очереди
            }
          } catch (_) {}
        }
      }

      list.add(json.encode({
        'env': envelope,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));

      // Держим только последние _maxItems.
      final trimmed = list.length > _maxItems
          ? list.sublist(list.length - _maxItems)
          : list;

      await prefs.setStringList(_key, trimmed);
      DebugLogger.info('PENDING_INBOX',
          'Конверт сохранён (в очереди ${trimmed.length})');
    } catch (e) {
      DebugLogger.error('PENDING_INBOX', 'append error: $e');
    }
  }

  /// Прочитать непротухшие конверты БЕЗ удаления (вызывает main-изолят при старте).
  /// Недеструктивно намеренно: удаляем только реально обработанное (removeProcessed),
  /// иначе крэш посреди обработки или параллельный append из push-изолята потеряли бы
  /// сообщение. Каждый элемент несёт свой сырой ключ (`raw`) для точечного удаления.
  Future<List<PendingEnvelope>> peekAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = prefs.getStringList(_key);
      if (list == null || list.isEmpty) return const [];

      final now = DateTime.now().millisecondsSinceEpoch;
      final out = <PendingEnvelope>[];
      for (final raw in list) {
        try {
          final decoded = json.decode(raw) as Map<String, dynamic>;
          final ts = (decoded['ts'] as num?)?.toInt() ?? 0;
          if (now - ts > maxAgeMs) continue; // протух
          final env = decoded['env'];
          if (env is Map<String, dynamic>) {
            out.add(PendingEnvelope(raw: raw, envelope: env));
          }
        } catch (_) {}
      }
      return out;
    } catch (e) {
      DebugLogger.error('PENDING_INBOX', 'peekAll error: $e');
      return const [];
    }
  }

  /// Удалить из очереди ТОЛЬКО перечисленные (реально обработанные) сырые элементы.
  /// reload + фильтр по значению: конверт, добавленный push-изолятом во время
  /// обработки, не входит в `rawItems` и потому переживёт удаление. Заодно чистим
  /// протухшие, чтобы очередь не копила мёртвый груз.
  Future<void> removeProcessed(Set<String> rawItems) async {
    if (rawItems.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = prefs.getStringList(_key);
      if (list == null || list.isEmpty) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final kept = <String>[];
      for (final raw in list) {
        if (rawItems.contains(raw)) continue; // обработан — убираем
        try {
          final ts = (json.decode(raw) as Map)['ts'] as num?;
          if (ts != null && now - ts.toInt() > maxAgeMs) continue; // протух
        } catch (_) {}
        kept.add(raw);
      }
      if (kept.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setStringList(_key, kept);
      }
      DebugLogger.info('PENDING_INBOX',
          'Обработано ${rawItems.length}, в очереди осталось ${kept.length}');
    } catch (e) {
      DebugLogger.error('PENDING_INBOX', 'removeProcessed error: $e');
    }
  }
}

/// Сырой конверт из очереди + его ключ для точечного удаления.
class PendingEnvelope {
  final String raw;
  final Map<String, dynamic> envelope;
  const PendingEnvelope({required this.raw, required this.envelope});
}
