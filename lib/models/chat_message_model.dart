// lib/models/chat_message_model.dart

enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  final int? id; // Локальный автоинкремент БД (для точного обновления строки)
  /// Стабильный идентификатор сообщения (UUID), одинаковый у отправителя и
  /// получателя. Используется для дедупликации входящих и «удалить у обоих».
  /// null для старых сообщений / входящих от старых клиентов.
  final String? messageId;
  final String text;
  final bool isSentByMe;
  final DateTime timestamp;
  final MessageStatus status;
  final bool isRead; // Прочитано ли сообщение (для входящих)

  ChatMessage({
    this.id,
    this.messageId,
    required this.text,
    required this.isSentByMe,
    DateTime? timestamp,
    this.status = MessageStatus.sent, // По дефолту считаем отправленным
    this.isRead = true, // Свои сообщения всегда прочитаны, чужие - зависит
  }) : timestamp = timestamp ?? DateTime.now();

  /// Тексты-маркеры системных записей звонка в истории чата: они хранятся в
  /// таблице `messages` как обычные сообщения (chat_screen рисует их call-иконкой),
  /// но это НЕ переписка. Английские варианты — то, что реально пишет клиент
  /// (`_saveCallStatusMessageLocally`); русские — легаси от старых сборок. Набор
  /// нужен, чтобы не засчитывать звонки за сообщения в статистике профиля.
  static const Set<String> callEventTexts = {
    'Incoming call', 'Outgoing call', 'Missed call',
    'Входящий звонок', 'Исходящий звонок', 'Пропущен звонок',
  };

  /// Является ли запись системным событием звонка (а не перепиской).
  static bool isCallEvent(String text) => callEventTexts.contains(text);

  // Конвертация статуса в int для БД
  static int _statusToInt(MessageStatus status) => status.index;

  Map<String, dynamic> toMap(String contactKey) {
    return {
      'contactPublicKey': contactKey,
      'messageId': messageId,
      'text': text,
      'isSentByMe': isSentByMe ? 1 : 0,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': _statusToInt(status),
      'isRead': isRead ? 1 : 0,
    };
  }
}