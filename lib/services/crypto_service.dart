// lib/services/crypto_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // Для compute
import 'package:cryptography/cryptography.dart';
import 'package:orpheus_project/services/secure_storage_options.dart';

/// Модель идентичности (PoP): один 32-байтный root_seed -> через HKDF-SHA256
/// выводятся Ed25519 (сетевой АДРЕС + подпись proof-of-possession) и X25519
/// (ключ ШИФРОВАНИЯ, ECDH). Хранится только root_seed.
class CryptoService {
  // Общий экземпляр приложения: main/performWipe работают с ним, чтобы состояние
  // ключей (в т.ч. очистка в памяти при wipe) было согласованным (аудит ARCH-7 /
  // SEC-5). Конструктор оставлен публичным — тестам нужны отдельные экземпляры.
  static final CryptoService instance = CryptoService();

  final _secureStorage = appSecureStorage;

  static const _rootSeedStoreKey = 'orpheus_root_seed';
  // Legacy-ключи модели до PoP (X25519-only) — чистим при генерации/wipe.
  static const _legacyPrivateKeyStoreKey = 'orpheus_private_key_data';
  static const _legacyPublicKeyStoreKey = 'orpheus_public_key_data';
  static const _registrationDateKey = 'orpheus_registration_date';

  // HKDF-параметры (должны совпадать с эталонным вектором и серверными тест-векторами).
  static final List<int> _hkdfSalt = utf8.encode('orpheus-hkdf-v1');
  static const _edInfo = 'orpheus/identity/ed25519/v1';
  static const _xInfo = 'orpheus/encryption/x25519/v1';
  // Домен-разделители подписей (байт-в-байт как на сервере, app/pop.py).
  static const _popContext = 'orpheus-ws-pop-v1';
  static const _bindContext = 'orpheus-identity-bind-v1';

  // Алгоритмы
  final keyExchangeAlgorithm = X25519();
  final _signAlgorithm = Ed25519();

  // Ключи в памяти
  SimpleKeyPair? _keyPair; // X25519 (шифрование)
  SimplePublicKey? _publicKey; // X25519 pub (enc key)
  SimpleKeyPair? _edKeyPair; // Ed25519 (идентичность/подпись)
  SimplePublicKey? _edPublicKey; // Ed25519 pub (адрес)
  List<int>? _rootSeed; // root seed в памяти (для экспорта; как старый код держал приватник)
  Map<String, String>? _cachedBundle; // {address, enc, sig} — считается один раз при деривации
  DateTime? _registrationDate;

  /// Кэшированная самоподписанная связка {address, enc, sig} для синхронного
  /// прикрепления к исходящим сообщениям (inline-резолв enc-ключа у получателя).
  Map<String, String>? get cachedIdentityBundle => _cachedBundle;

  /// X25519 enc-ключ (base64). Совместимость: publicKeyBase64 == encryptionKeyBase64.
  String? get publicKeyBase64 => _publicKey != null ? base64.encode(_publicKey!.bytes) : null;
  String? get encryptionKeyBase64 => publicKeyBase64;

  /// Сетевой адрес = Ed25519 pub, base64url без padding.
  String? get addressBase64 => _edPublicKey != null ? _b64urlNoPad(_edPublicKey!.bytes) : null;

  DateTime? get registrationDate => _registrationDate;

  static String _b64urlNoPad(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  // --- ИНИЦИАЛИЗАЦИЯ И УПРАВЛЕНИЕ КЛЮЧАМИ ---

  Future<void> _deriveFromSeed(List<int> rootBytes) async {
    _rootSeed = List<int>.of(rootBytes);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final edSeed = await (await hkdf.deriveKey(
      secretKey: SecretKey(rootBytes),
      nonce: _hkdfSalt,
      info: utf8.encode(_edInfo),
    )).extractBytes();
    final xSeed = await (await hkdf.deriveKey(
      secretKey: SecretKey(rootBytes),
      nonce: _hkdfSalt,
      info: utf8.encode(_xInfo),
    )).extractBytes();

    _edKeyPair = await _signAlgorithm.newKeyPairFromSeed(edSeed);
    _edPublicKey = await _edKeyPair!.extractPublicKey();
    _keyPair = await keyExchangeAlgorithm.newKeyPairFromSeed(xSeed);
    _publicKey = await _keyPair!.extractPublicKey();
    _cachedBundle = await identityBundle();
  }

  /// Только для тестов: деривация ключей из seed без обращения к secure storage.
  @visibleForTesting
  Future<void> deriveFromSeedForTest(List<int> rootBytes) => _deriveFromSeed(rootBytes);

  Future<bool> init() async {
    final rootB64 = await _secureStorage.read(key: _rootSeedStoreKey);
    final registrationDateStr = await _secureStorage.read(key: _registrationDateKey);

    if (rootB64 != null) {
      await _deriveFromSeed(base64.decode(rootB64));
      if (registrationDateStr != null) {
        _registrationDate = DateTime.tryParse(registrationDateStr);
      }
      print("Identity loaded (Ed25519 address + X25519 enc from root seed).");
      return true;
    }
    return false;
  }

  Future<void> generateNewKeys() async {
    final rnd = Random.secure();
    final rootBytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    await _secureStorage.write(key: _rootSeedStoreKey, value: base64.encode(rootBytes));
    await _deriveFromSeed(rootBytes);

    _registrationDate = DateTime.now();
    await _secureStorage.write(
      key: _registrationDateKey,
      value: _registrationDate!.toIso8601String(),
    );

    // подчистим возможные legacy-ключи старой модели
    await _secureStorage.delete(key: _legacyPrivateKeyStoreKey);
    await _secureStorage.delete(key: _legacyPublicKeyStoreKey);
    print("New identity generated (root seed).");
  }

  /// Импорт бэкапа. Формат бэкапа = base64(root_seed) (32 байта).
  Future<void> importPrivateKey(String rootSeedB64) async {
    try {
      final rootBytes = base64.decode(rootSeedB64);
      if (rootBytes.length != 32) {
        throw Exception("root seed must be 32 bytes");
      }
      await _secureStorage.write(key: _rootSeedStoreKey, value: base64.encode(rootBytes));
      await _deriveFromSeed(rootBytes);
      print("Identity imported from root seed.");
    } catch (e) {
      throw Exception("Invalid key format");
    }
  }

  /// Экспорт бэкапа = base64(root_seed).
  Future<String> getPrivateKeyBase64() async {
    if (_rootSeed != null) return base64.encode(_rootSeed!);
    final rootB64 = await _secureStorage.read(key: _rootSeedStoreKey);
    if (rootB64 == null) throw Exception("No keys available");
    return rootB64;
  }

  /// Полное удаление аккаунта - удаляет все ключи и данные
  Future<void> deleteAccount() async {
    await _secureStorage.delete(key: _rootSeedStoreKey);
    await _secureStorage.delete(key: _legacyPrivateKeyStoreKey);
    await _secureStorage.delete(key: _legacyPublicKeyStoreKey);
    await _secureStorage.delete(key: _registrationDateKey);

    _keyPair = null;
    _publicKey = null;
    _edKeyPair = null;
    _edPublicKey = null;
    _rootSeed = null;
    _cachedBundle = null;
    _registrationDate = null;

    print("Account deleted.");
  }

  // --- PoP + IDENTITY-BIND ПОДПИСИ (Ed25519) ---

  List<int> _popMessage(List<int> addressRaw, List<int> nonce, int tsMs) {
    final ts = Uint8List(8);
    ByteData.view(ts.buffer).setUint64(0, tsMs, Endian.big);
    return <int>[...utf8.encode(_popContext), 0, ...addressRaw, ...nonce, ...ts];
  }

  /// Подпись proof-of-possession для WS-хендшейка. Возвращает base64url(sig) без padding.
  Future<String> signPopProof(List<int> nonce, int tsMs) async {
    if (_edKeyPair == null) throw Exception("Keys not initialized!");
    final msg = _popMessage(_edPublicKey!.bytes, nonce, tsMs);
    final sig = await _signAlgorithm.sign(msg, keyPair: _edKeyPair!);
    return _b64urlNoPad(sig.bytes);
  }

  static List<int> _b64urlDecode(String s) {
    final pad = (4 - s.length % 4) % 4;
    return base64Url.decode(s + ('=' * pad));
  }

  /// Проверка самоподписи связки адрес<->enc (Ed25519). Используется при приёме
  /// inline-bundle в сообщениях и при резолве из directory — enc-ключ незнакомца
  /// принимаем ТОЛЬКО если он подписан владельцем адреса.
  Future<bool> verifyIdentityBundle(String addressB64url, String encB64, String sigB64url) async {
    try {
      final edPub = _b64urlDecode(addressB64url);
      final xPub = base64.decode(encB64);
      final sig = _b64urlDecode(sigB64url);
      if (edPub.length != 32 || xPub.length != 32 || sig.length != 64) return false;
      final bindMsg = <int>[...utf8.encode(_bindContext), 0, ...edPub, ...xPub];
      final pubKey = SimplePublicKey(edPub, type: KeyPairType.ed25519);
      return await _signAlgorithm.verify(bindMsg, signature: Signature(sig, publicKey: pubKey));
    } catch (_) {
      return false;
    }
  }

  /// Самоподписанная связка адрес<->enc-ключ для directory/QR: {address, enc, sig}.
  Future<Map<String, String>> identityBundle() async {
    if (_edKeyPair == null) throw Exception("Keys not initialized!");
    final edPub = _edPublicKey!.bytes;
    final xPub = _publicKey!.bytes;
    final bindMsg = <int>[...utf8.encode(_bindContext), 0, ...edPub, ...xPub];
    final sig = await _signAlgorithm.sign(bindMsg, keyPair: _edKeyPair!);
    return {
      'address': _b64urlNoPad(edPub),
      'enc': base64.encode(xPub),
      'sig': _b64urlNoPad(sig.bytes),
    };
  }

  // --- ШИФРОВАНИЕ (В ИЗОЛЯТАХ) --- (X25519, без изменений)

  Future<String> encrypt(String recipientPublicKeyBase64, String message) async {
    if (_keyPair == null) throw Exception("Keys not initialized!");

    final keyData = await _keyPair!.extract();
    final myPrivateKeyBytes = keyData.bytes;
    final myPublicKeyBytes = (await _keyPair!.extractPublicKey()).bytes;

    return await compute(_encryptTask, {
      'myPrivateKey': myPrivateKeyBytes,
      'myPublicKey': myPublicKeyBytes,
      'recipientPublicKey': recipientPublicKeyBase64,
      'message': message,
    });
  }

  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload) async {
    if (_keyPair == null) throw Exception("Keys not initialized!");

    final keyData = await _keyPair!.extract();
    final myPrivateKeyBytes = keyData.bytes;
    final myPublicKeyBytes = (await _keyPair!.extractPublicKey()).bytes;

    return await compute(_decryptTask, {
      'myPrivateKey': myPrivateKeyBytes,
      'myPublicKey': myPublicKeyBytes,
      'senderPublicKey': senderPublicKeyBase64,
      'payload': encryptedPayload,
    });
  }

  // --- СТАТИЧЕСКИЕ ЗАДАЧИ ДЛЯ COMPUTE ---
  // Они не имеют доступа к `this`, поэтому все данные передаются через Map

  static Future<String> _encryptTask(Map<String, dynamic> data) async {
    final algorithm = X25519();
    final cipher = Chacha20.poly1305Aead();

    final myPrivateKeyBytes = data['myPrivateKey'] as List<int>;
    final myPublicKeyBytes = data['myPublicKey'] as List<int>;
    final recipientKeyB64 = data['recipientPublicKey'] as String;
    final message = data['message'] as String;

    final myPublicKey = SimplePublicKey(myPublicKeyBytes, type: KeyPairType.x25519);
    final myKeyPair = SimpleKeyPairData(
      myPrivateKeyBytes,
      publicKey: myPublicKey,
      type: KeyPairType.x25519,
    );

    final recipientPublicKey = SimplePublicKey(base64.decode(recipientKeyB64), type: KeyPairType.x25519);

    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final messageBytes = utf8.encode(message);
    final secretBox = await cipher.encrypt(messageBytes, secretKey: sharedSecret);

    return json.encode({
      'cipherText': base64.encode(secretBox.cipherText),
      'nonce': base64.encode(secretBox.nonce),
      'mac': base64.encode(secretBox.mac.bytes),
    });
  }

  static Future<String> _decryptTask(Map<String, dynamic> data) async {
    final algorithm = X25519();
    final cipher = Chacha20.poly1305Aead();

    final myPrivateKeyBytes = data['myPrivateKey'] as List<int>;
    final myPublicKeyBytes = data['myPublicKey'] as List<int>;
    final senderKeyB64 = data['senderPublicKey'] as String;
    final payloadJson = data['payload'] as String;

    final myPublicKey = SimplePublicKey(myPublicKeyBytes, type: KeyPairType.x25519);
    final myKeyPair = SimpleKeyPairData(
      myPrivateKeyBytes,
      publicKey: myPublicKey,
      type: KeyPairType.x25519,
    );

    final senderPublicKey = SimplePublicKey(base64.decode(senderKeyB64), type: KeyPairType.x25519);

    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: senderPublicKey,
    );

    final payloadMap = json.decode(payloadJson) as Map<String, dynamic>;
    final secretBox = SecretBox(
      base64.decode(payloadMap['cipherText']!),
      nonce: base64.decode(payloadMap['nonce']!),
      mac: Mac(base64.decode(payloadMap['mac']!)),
    );

    final decryptedBytes = await cipher.decrypt(secretBox, secretKey: sharedSecret);
    return utf8.decode(decryptedBytes);
  }
}
