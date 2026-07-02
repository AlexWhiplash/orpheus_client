// lib/models/contact_model.dart

class Contact {
  final int? id;
  final String name;
  final String publicKey;

  /// Время последнего сообщения (epoch ms) для сортировки и отображения в списке.
  /// null/0 — переписки ещё не было. Не персистится в таблице contacts —
  /// вычисляется в getContacts() из messages (аудит PROD-4).
  final int? lastMessageTime;

  Contact({
    this.id,
    required this.name,
    required this.publicKey,
    this.lastMessageTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'publicKey': publicKey,
    };
  }
}