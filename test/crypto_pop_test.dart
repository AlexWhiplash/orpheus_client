import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/crypto_service.dart';

// Эталонный вектор вычислен на сервере (Python: cryptography HKDF + PyNaCl Ed25519 +
// X25519). Совпадение доказывает интероп Dart<->Python по всей цепочке:
// root_seed -> HKDF -> Ed25519(address)/X25519(enc) -> подписи pop/bind.
const _rootSeedB64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
const _address = 'OYA5Fn3D3ZYoo448fez8TEP1ZhZbGrabxh4GwvTbIDk';
const _enc = '4/33QYyRnIs6ICdKT5ByVSGFY76vdNU+BpbwFl0Y8BA=';
const _popSig =
    'OvM78wwfMdJigSMBlf-Nfze-pMRKc90vODpYZSsymOygGFx-HoBjt4yvu0P8AtYXfGfeIoN2IqStqHX6GNv9Cw';
const _bindSig =
    'Eh0MZevUjMKKJSaOrB5lIbzawGhnEJALZocsexBEnytbebbfigdFUhUeF5JnvqxdTNzgtQs4ZDKl--Xe0B7dBg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PoP identity interop vector (Dart <-> Python)', () async {
    final crypto = CryptoService();
    await crypto.deriveFromSeedForTest(base64.decode(_rootSeedB64));

    expect(crypto.addressBase64, _address);
    expect(crypto.encryptionKeyBase64, _enc);

    final nonce = List<int>.filled(32, 0xAB);
    final popSig = await crypto.signPopProof(nonce, 1712345678000);
    expect(popSig, _popSig);

    final bundle = await crypto.identityBundle();
    expect(bundle['address'], _address);
    expect(bundle['enc'], _enc);
    expect(bundle['sig'], _bindSig);
  });

  test('isValidAddress: адрес принимается, X25519-ключ и мусор отклоняются', () {
    // Валидный Ed25519-адрес (base64url без padding, 32 байта).
    expect(CryptoService.isValidAddress(_address), isTrue);
    expect(CryptoService.isValidAddress('  $_address  '), isTrue); // trim

    // Старый X25519 enc-ключ (стандартный base64 с '+/=') — это НЕ адрес.
    expect(CryptoService.isValidAddress(_enc), isFalse);

    // Мусор / неверная длина / недопустимый алфавит / лишний padding.
    expect(CryptoService.isValidAddress(''), isFalse);
    expect(CryptoService.isValidAddress('not-a-real-key'), isFalse);
    expect(CryptoService.isValidAddress(_popSig), isFalse); // 64 байта — слишком длинно
    expect(CryptoService.isValidAddress('$_address='), isFalse); // padding недопустим
  });

  test('derivation is deterministic', () async {
    final c1 = CryptoService();
    final c2 = CryptoService();
    final seed = List<int>.generate(32, (i) => (i * 7 + 3) % 256);
    await c1.deriveFromSeedForTest(seed);
    await c2.deriveFromSeedForTest(seed);
    expect(c1.addressBase64, c2.addressBase64);
    expect(c1.encryptionKeyBase64, c2.encryptionKeyBase64);
    expect(c1.addressBase64, isNotNull);
  });
}
