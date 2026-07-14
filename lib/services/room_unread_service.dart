import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orpheus_project/models/room_model.dart';

/// Tracks unread state for rooms, so the "Rooms" tab can show a "has new" dot.
///
/// Rooms are not stored in the local DB (history is pulled over HTTP), so unread
/// is tracked here: a per-room "last seen" timestamp (persisted) plus an in-memory
/// set of rooms that received a live message while not being viewed. A room is
/// unread if it received a live message, or its server-side last message is newer
/// than the last time it was opened.
///
/// Singleton (.instance), consistent with the rest of the services.
class RoomUnreadService {
  RoomUnreadService._();
  static final RoomUnreadService instance = RoomUnreadService._();

  static const String _prefKey = 'room_last_seen_v1';

  /// True when any room has unread messages. UI (home tab badge) listens to this.
  final ValueNotifier<bool> hasUnread = ValueNotifier<bool>(false);

  /// The room currently open on screen. Live messages for it are being read and
  /// must not mark it unread. Set/cleared by RoomChatScreen.
  String? activeRoomId;

  Map<String, int> _lastSeen = <String, int>{}; // roomId -> last seen (ms)
  final Set<String> _unread = <String>{};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) {
          _lastSeen = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, json.encode(_lastSeen));
    } catch (_) {}
  }

  void _recompute() {
    hasUnread.value = _unread.isNotEmpty;
  }

  /// A live room message arrived. Ignores the room currently on screen.
  void noteIncoming(String roomId) {
    if (roomId.isEmpty || roomId == activeRoomId) return;
    if (_unread.add(roomId)) _recompute();
  }

  /// Recompute unread from the loaded rooms list (catches messages that arrived
  /// while the app was closed): a room is unread if its last message is newer than
  /// when it was last opened. The very first run seeds "seen up to now" for every
  /// room, so pre-existing history does not light the badge after an upgrade.
  Future<void> syncWithRooms(List<Room> rooms) async {
    await _ensureLoaded();
    final firstRun = _lastSeen.isEmpty;
    var changed = false;
    for (final r in rooms) {
      final lastMs = r.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      if (firstRun) {
        _lastSeen[r.id] = lastMs;
        changed = true;
      } else if (lastMs > (_lastSeen[r.id] ?? 0)) {
        _unread.add(r.id);
      }
    }
    if (changed) await _persist();
    _recompute();
  }

  /// The user opened a room -> mark it seen up to now and clear its badge.
  Future<void> markSeen(String roomId) async {
    if (roomId.isEmpty) return;
    await _ensureLoaded();
    final wasUnread = _unread.remove(roomId);
    _lastSeen[roomId] = DateTime.now().millisecondsSinceEpoch;
    await _persist();
    if (wasUnread) _recompute();
  }

  @visibleForTesting
  void debugResetForTesting() {
    _lastSeen = <String, int>{};
    _unread.clear();
    activeRoomId = null;
    _loaded = false;
    hasUnread.value = false;
  }
}
