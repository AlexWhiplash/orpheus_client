import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local, per-pubkey display names for room participants who are NOT in your
/// contacts. Lets you "pin" a name to someone you met or who introduced
/// themselves, without adding them as a contact (a room only exposes an address,
/// not the X25519 key needed for a direct chat).
///
/// Stored locally (never sent anywhere), keyed by the participant's pubkey, so a
/// name you set applies wherever you see that person across rooms. Singleton
/// (.instance), consistent with the other services.
class RoomAliasService {
  RoomAliasService._();
  static final RoomAliasService instance = RoomAliasService._();

  static const String _prefKey = 'room_participant_aliases_v1';

  /// All saved aliases as pubkey -> name.
  Future<Map<String, String>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null) return <String, String>{};
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    return <String, String>{};
  }

  /// Set (or, with an empty name, clear) the alias for a participant.
  Future<void> setAlias(String pubkey, String name) async {
    if (pubkey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await getAll();
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        all.remove(pubkey);
      } else {
        all[pubkey] = trimmed;
      }
      await prefs.setString(_prefKey, json.encode(all));
    } catch (_) {}
  }
}
