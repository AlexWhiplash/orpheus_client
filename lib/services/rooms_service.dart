import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart' show cryptoService;
import 'package:orpheus_project/models/room_message_model.dart';
import 'package:orpheus_project/models/room_model.dart';

class RoomsService {
  RoomsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  String? get _pubkey => cryptoService.publicKeyBase64;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Pubkey': _pubkey ?? '',
      };

  Future<List<Room>> loadRooms() async {
    if (_pubkey == null) return [];
    final url = AppConfig.httpUrl('/api/rooms');
    final response = await _httpClient
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final roomsRaw = data['rooms'] as List<dynamic>? ?? [];
    return roomsRaw
        .whereType<Map<String, dynamic>>()
        .map(Room.fromJson)
        .toList();
  }

  Future<RoomCreateResult> createRoom(String name) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms');
    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: _headers,
          body: json.encode({'name': name}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final roomJson = data['room'] as Map<String, dynamic>? ?? data;
    final inviteCode = data['invite_code'] as String? ??
        roomJson['invite_code'] as String? ??
        '';
    return RoomCreateResult(
      room: Room.fromJson(roomJson),
      inviteCode: inviteCode,
    );
  }

  Future<Room> joinRoom(String inviteCode) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms/join');
    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: _headers,
          body: json.encode({'invite_code': inviteCode}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final roomJson = data['room'] as Map<String, dynamic>? ?? data;
    return Room.fromJson(roomJson);
  }

  Future<({List<RoomMessage> messages, bool hasMore})> loadMessages(
    String roomId, {
    int limit = 100,
    int? beforeId,
  }) async {
    if (_pubkey == null) return (messages: <RoomMessage>[], hasMore: false);
    var path = '/api/rooms/$roomId/messages?limit=$limit';
    if (beforeId != null) path += '&before_id=$beforeId';
    final url = AppConfig.httpUrl(path);
    final response = await _httpClient
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final messagesRaw = data['messages'] as List<dynamic>? ?? [];
    final messages = messagesRaw
        .whereType<Map<String, dynamic>>()
        .map(RoomMessage.fromJson)
        .toList();
    final hasMore = data['has_more'] == true;
    return (messages: messages, hasMore: hasMore);
  }

  Future<Map<String, dynamic>> loadRoomPrefs(String roomId) async {
    if (_pubkey == null) {
      return {
        'notifications_enabled': true,
        'warning_dismissed': false,
      };
    }
    final url = AppConfig.httpUrl('/api/rooms/$roomId/prefs');
    final response = await _httpClient
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateRoomPrefs(
    String roomId, {
    bool? notificationsEnabled,
    bool? warningDismissed,
  }) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms/$roomId/prefs');
    final body = <String, dynamic>{};
    if (notificationsEnabled != null) {
      body['notifications_enabled'] = notificationsEnabled;
    }
    if (warningDismissed != null) {
      body['warning_dismissed'] = warningDismissed;
    }
    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: _headers,
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage(
    String roomId,
    String text, {
    bool asOrpheus = false,
  }) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms/$roomId/message');
    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: _headers,
          body: json.encode({
            'text': text,
            if (asOrpheus) 'author_type': 'orpheus',
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return data;
  }

  Future<String> rotateInvite(String roomId) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms/$roomId/rotate-invite');
    final response = await _httpClient
        .post(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return data['invite_code'] as String? ?? '';
  }

  Future<void> panicClear(String roomId) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms/$roomId/panic-clear');
    final response = await _httpClient
        .post(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  Future<void> leaveRoom(String roomId) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms/$roomId/leave');
    final response = await _httpClient
        .post(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  /// Delete the room for everyone. Owner-only: the server checks is_owner
  /// against X-Pubkey and returns 403 for non-owners.
  Future<void> deleteRoom(String roomId) async {
    if (_pubkey == null) throw Exception('Keys not initialized');
    final url = AppConfig.httpUrl('/api/rooms/$roomId/delete');
    final response = await _httpClient
        .post(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }
}
