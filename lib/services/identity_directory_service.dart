import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';

/// Резолв X25519 enc-ключа по Ed25519-адресу.
///
/// Порядок: 1) локальный контакт; 2) directory-кэш; 3) сервер `GET /api/identity/{address}`
/// с обязательной проверкой самоподписи bundle (enc-ключ незнакомца принимаем только
/// если он подписан владельцем адреса — защита от подмены сервером). Найденный ключ
/// кэшируется и дописывается в контакт.
class IdentityDirectoryService {
  IdentityDirectoryService._();
  static final IdentityDirectoryService instance = IdentityDirectoryService._();

  final http.Client _http = http.Client();
  final Map<String, String> _cache = {};

  Future<String?> resolveEncKey(String address) async {
    if (address.isEmpty) return null;

    final local = await DatabaseService.instance.getContactEncryptionKey(address);
    if (local != null && local.isNotEmpty) return local;

    final cached = _cache[address];
    if (cached != null && cached.isNotEmpty) return cached;

    for (final url in AppConfig.httpUrls('/api/identity/${Uri.encodeComponent(address)}')) {
      try {
        final resp = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) continue;
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final enc = data['enc'] as String?;
        final sig = data['sig'] as String?;
        if (enc == null || enc.isEmpty || sig == null || sig.isEmpty) continue;
        if (!await CryptoService.instance.verifyIdentityBundle(address, enc, sig)) continue;
        _cache[address] = enc;
        await DatabaseService.instance.addContactIfMissing(address, encryptionKey: enc);
        return enc;
      } catch (_) {}
    }
    return null;
  }

  /// Опубликовать свою подписанную связку адрес<->enc в directory (на регистрации).
  Future<bool> publishSelf() async {
    final bundle = CryptoService.instance.cachedIdentityBundle;
    if (bundle == null) return false;
    final body = json.encode(bundle);
    var ok = false;
    for (final url in AppConfig.httpUrls('/api/identity')) {
      try {
        final resp = await _http
            .post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) ok = true;
      } catch (_) {}
    }
    return ok;
  }
}
