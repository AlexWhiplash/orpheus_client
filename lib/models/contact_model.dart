// lib/models/contact_model.dart

class Contact {
  final int? id;
  final String name;

  /// Сетевой АДРЕС контакта (Ed25519 pub, b64url) — бизнес-ключ + маршрутизация.
  final String publicKey;

  /// Ключ ШИФРОВАНИЯ контакта (X25519 pub, b64) для ECDH. Может быть null, пока
  /// не получен (из QR-bundle, directory или inline в первом сообщении).
  final String? encryptionKey;

  /// Время последнего сообщения (epoch ms) для сортировки и отображения в списке.
  /// null/0 — переписки ещё не было. Не персистится в таблице contacts —
  /// вычисляется в getContacts() из messages (аудит PROD-4).
  final int? lastMessageTime;

  Contact({
    this.id,
    required this.name,
    required this.publicKey,
    this.encryptionKey,
    this.lastMessageTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'publicKey': publicKey,
      'encryptionKey': encryptionKey,
    };
  }
}