// lib/services/crypto_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart'; // Для compute
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  // Общий экземпляр приложения: main/performWipe работают с ним, чтобы состояние
  // ключей (в т.ч. очистка в памяти при wipe) было согласованным (аудит ARCH-7 /
  // SEC-5). Конструктор оставлен публичным — тестам нужны отдельные экземпляры.
  static final CryptoService instance = CryptoService();

  final _secureStorage = const FlutterSecureStorage();

  static const _privateKeyStoreKey = 'orpheus_private_key_data';
  static const _publicKeyStoreKey = 'orpheus_public_key_data';
  static const _registrationDateKey = 'orpheus_registration_date';

  // Алгоритмы (используются в основном потоке для генерации ключей)
  final keyExchangeAlgorithm = X25519();

  // Храним ключи в памяти
  SimpleKeyPair? _keyPair;
  SimplePublicKey? _publicKey;
  DateTime? _registrationDate;

  String? get publicKeyBase64 => _publicKey != null ? base64.encode(_publicKey!.bytes) : null;
  DateTime? get registrationDate => _registrationDate;

  // --- ИНИЦИАЛИЗАЦИЯ И УПРАВЛЕНИЕ КЛЮЧАМИ ---

  Future<bool> init() async {
    final privateKeyB64 = await _secureStorage.read(key: _privateKeyStoreKey);
    final publicKeyB64 = await _secureStorage.read(key: _publicKeyStoreKey);
    final registrationDateStr = await _secureStorage.read(key: _registrationDateKey);

    if (privateKeyB64 != null && publicKeyB64 != null) {
      final privateKeyBytes = base64.decode(privateKeyB64);
      final publicKeyBytes = base64.decode(publicKeyB64);

      _publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519);
      _keyPair = SimpleKeyPairData(
        privateKeyBytes,
        publicKey: _publicKey!,
        type: KeyPairType.x25519,
      );
      
      // Загружаем дату регистрации
      if (registrationDateStr != null) {
        _registrationDate = DateTime.tryParse(registrationDateStr);
      }
      
      print("Keys loaded.");
      return true;
    }
    return false;
  }

  Future<void> generateNewKeys() async {
    _keyPair = await keyExchangeAlgorithm.newKeyPair();
    final privateKeyData = await _keyPair!.extract();
    _publicKey = await _keyPair!.extractPublicKey();

    // Сохраняем дату создания аккаунта
    _registrationDate = DateTime.now();
    await _secureStorage.write(
      key: _registrationDateKey, 
      value: _registrationDate!.toIso8601String(),
    );

    await _saveKeys(privateKeyData.bytes, _publicKey!.bytes);
    print("New keys generated.");
  }

  Future<void> importPrivateKey(String privateKeyB64) async {
    try {
      final privateKeyBytes = base64.decode(privateKeyB64);

      _keyPair = await keyExchangeAlgorithm.newKeyPairFromSeed(privateKeyBytes);
      final privateKeyData = await _keyPair!.extract();
      _publicKey = await _keyPair!.extractPublicKey();

      await _saveKeys(privateKeyData.bytes, _publicKey!.bytes);
      print("Keys imported successfully.");
    } catch (e) {
      throw Exception("Invalid key format");
    }
  }

  Future<String> getPrivateKeyBase64() async {
    if (_keyPair == null) throw Exception("No keys available");
    final data = await _keyPair!.extract();
    return base64.encode(data.bytes);
  }

  Future<void> _saveKeys(List<int> privateBytes, List<int> publicBytes) async {
    await _secureStorage.write(key: _privateKeyStoreKey, value: base64.encode(privateBytes));
    await _secureStorage.write(key: _publicKeyStoreKey, value: base64.encode(publicBytes));
  }

  /// Полное удаление аккаунта - удаляет все ключи и данные
  Future<void> deleteAccount() async {
    await _secureStorage.delete(key: _privateKeyStoreKey);
    await _secureStorage.delete(key: _publicKeyStoreKey);
    await _secureStorage.delete(key: _registrationDateKey);
    
    _keyPair = null;
    _publicKey = null;
    _registrationDate = null;
    
    print("Account deleted.");
  }

  // --- ШИФРОВАНИЕ (В ИЗОЛЯТАХ) ---

  Future<String> encrypt(String recipientPublicKeyBase64, String message) async {
    if (_keyPair == null) throw Exception("Keys not initialized!");

    // Извлекаем сырые байты, чтобы передать их в изолят
    final keyData = await _keyPair!.extract();
    final myPrivateKeyBytes = keyData.bytes;
    final myPublicKeyBytes = (await _keyPair!.extractPublicKey()).bytes;

    // Запускаем тяжелую задачу в отдельном потоке
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

    // Восстанавливаем ключи
    final myPublicKey = SimplePublicKey(myPublicKeyBytes, type: KeyPairType.x25519);
    final myKeyPair = SimpleKeyPairData(
      myPrivateKeyBytes,
      publicKey: myPublicKey,
      type: KeyPairType.x25519,
    );

    final recipientPublicKey = SimplePublicKey(base64.decode(recipientKeyB64), type: KeyPairType.x25519);

    // Вычисляем общий секрет
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    // Шифруем
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

    // Восстанавливаем ключи
    final myPublicKey = SimplePublicKey(myPublicKeyBytes, type: KeyPairType.x25519);
    final myKeyPair = SimpleKeyPairData(
      myPrivateKeyBytes,
      publicKey: myPublicKey,
      type: KeyPairType.x25519,
    );

    final senderPublicKey = SimplePublicKey(base64.decode(senderKeyB64), type: KeyPairType.x25519);

    // Вычисляем общий секрет
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: senderPublicKey,
    );

    // Дешифруем
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