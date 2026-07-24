import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:rxdart/rxdart.dart';

import 'package:orpheus_project/services/websocket_service.dart';

class PresenceService {
  PresenceService(this._ws, {this.maxPubkeysPerMessage = 500}) {
    _wsSub = _ws.stream.listen(_onRawMessage);
    _statusSub = _ws.status.distinct().listen((status) {
      if (status == ConnectionStatus.Connected) {
        _resubscribeAll();
      } else if (status == ConnectionStatus.Disconnected ||
          status == ConnectionStatus.AuthFailed) {
        // Без соединения презенс неизвестен: сбрасываем, чтобы «онлайн»
        // не залипал (device-тест b44: контакт горел зелёным при мёртвой
        // сети). После реконнекта состояние вернётся presence-state'ом
        // на полную переподписку.
        if (_states.value.isNotEmpty) {
          _states.add(<String, bool>{});
        }
      }
    });
  }

  final WebSocketService _ws;
  final int maxPubkeysPerMessage;

  final BehaviorSubject<Map<String, bool>> _states =
      BehaviorSubject.seeded(<String, bool>{});

  Stream<Map<String, bool>> get stream => _states.stream;

  bool isOnline(String pubkey) => _states.value[pubkey] == true;

  final Set<String> _watchedPubkeys = <String>{};

  StreamSubscription<String>? _wsSub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  void addWatchedPubkeys(Iterable<String> pubkeys) {
    final merged = <String>{..._watchedPubkeys, ..._normalizePubkeys(pubkeys)};
    setWatchedPubkeys(merged);
  }

  void setWatchedPubkeys(Iterable<String> pubkeys) {
    final next = _normalizePubkeys(pubkeys).toSet();

    final toSubscribe = next.difference(_watchedPubkeys);
    final toUnsubscribe = _watchedPubkeys.difference(next);

    _watchedPubkeys
      ..clear()
      ..addAll(next);

    // Если WS не подключен — ничего не шлём. При реконнекте уйдёт полный subscribe.
    if (_ws.currentStatus != ConnectionStatus.Connected) return;

    if (toUnsubscribe.isNotEmpty) {
      _sendUnsubscribe(toUnsubscribe);
    }

    if (toSubscribe.isNotEmpty) {
      _sendSubscribe(toSubscribe);
    }
  }

  void _resubscribeAll() {
    if (_watchedPubkeys.isEmpty) return;
    _sendSubscribe(_watchedPubkeys);
  }

  void _onRawMessage(String messageJson) {
    Map<String, dynamic>? data;
    try {
      final decoded = json.decode(messageJson);
      if (decoded is! Map) return;
      data = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    final type = data['type'];

    if (type == 'presence-state') {
      final statesRaw = data['states'];
      if (statesRaw is! Map) return;

      final next = Map<String, bool>.from(_states.value);
      for (final entry in statesRaw.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is String && v is bool) {
          next[k] = v;
        }
      }
      _states.add(next);
      return;
    }

    if (type == 'presence-update') {
      final pubkey = data['pubkey'];
      final online = data['online'];
      if (pubkey is! String || online is! bool) return;

      final next = Map<String, bool>.from(_states.value);
      next[pubkey] = online;
      _states.add(next);
      return;
    }
  }

  void _sendSubscribe(Iterable<String> pubkeys) {
    if (_ws.currentStatus != ConnectionStatus.Connected) return;

    final list = _normalizePubkeys(pubkeys);
    for (final chunk in _chunk(list, maxPubkeysPerMessage)) {
      _ws.sendRawMessage(json.encode({
        'type': 'presence-subscribe',
        'pubkeys': chunk,
      }));
    }
  }

  void _sendUnsubscribe(Iterable<String> pubkeys) {
    if (_ws.currentStatus != ConnectionStatus.Connected) return;

    final list = _normalizePubkeys(pubkeys);
    for (final chunk in _chunk(list, maxPubkeysPerMessage)) {
      _ws.sendRawMessage(json.encode({
        'type': 'presence-unsubscribe',
        'pubkeys': chunk,
      }));
    }
  }

  List<String> _normalizePubkeys(Iterable<String> pubkeys) {
    final out = <String>[];
    final seen = <String>{};

    for (final pk in pubkeys) {
      final v = pk.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }

    return out;
  }

  Iterable<List<String>> _chunk(List<String> items, int size) sync* {
    if (items.isEmpty) return;
    if (size <= 0) {
      yield items;
      return;
    }

    for (var i = 0; i < items.length; i += size) {
      final end = min(i + size, items.length);
      yield items.sublist(i, end);
    }
  }

  void dispose() {
    _wsSub?.cancel();
    _statusSub?.cancel();
    _states.close();
  }
}

