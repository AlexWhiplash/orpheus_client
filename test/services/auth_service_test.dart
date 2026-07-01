import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/security_config.dart';
import 'package:orpheus_project/services/auth_service.dart';

class _InMemoryAuthStorage implements AuthSecureStorage {
  final Map<String, String> _kv = {};

  @override
  Future<String?> read({required String key}) async => _kv[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _kv[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _kv.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _kv.clear();
  }
}

void main() {
  group('AuthService (контракты безопасности)', () {
    test('init: без конфига в storage — SecurityConfig.empty и приложение разблокировано', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);

      await auth.init();

      expect(auth.config, equals(SecurityConfig.empty));
      expect(auth.requiresUnlock, isFalse);
      expect(auth.isUnlocked, isTrue);
      expect(auth.isDuressMode, isFalse);
    });

    test('setPin + restart: PIN требует unlock после перезапуска (storage roundtrip)', () async {
      final storage = _InMemoryAuthStorage();

      final auth1 = AuthService.createForTesting(secureStorage: storage);
      await auth1.init();
      await auth1.setPin('123456');
      expect(auth1.config.isPinEnabled, isTrue);
      expect(auth1.config.requiresUnlock, isTrue);
      expect(auth1.isUnlocked, isTrue);

      final auth2 = AuthService.createForTesting(secureStorage: storage);
      await auth2.init();
      expect(auth2.config.isPinEnabled, isTrue);
      expect(auth2.requiresUnlock, isTrue);
      expect(auth2.isUnlocked, isFalse); // по контракту: после запуска нужно вводить PIN
    });

    test('verifyPin: неверный PIN увеличивает failedAttempts и возвращает invalid', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      auth.lock();
      expect(auth.isUnlocked, isFalse);

      final r1 = auth.verifyPin('000000');
      expect(r1, equals(PinVerifyResult.invalid));
      expect(auth.config.failedAttempts, equals(1));

      // сохранение происходит async внутри сервиса; даём очереди отработать
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });

    test('lockout: после достижения 5 неудачных попыток следующая попытка возвращает lockedOut', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      auth.lock();

      for (var i = 0; i < 5; i++) {
        final r = auth.verifyPin('000000');
        expect(r, equals(PinVerifyResult.invalid));
      }
      expect(auth.config.failedAttempts, equals(5));
      expect(auth.config.isLockedOut, isTrue);

      final duringLock = auth.verifyPin('123456');
      expect(duringLock, equals(PinVerifyResult.lockedOut));
      expect(auth.isUnlocked, isFalse);
    });

    test('duress: ввод duress-кода разблокирует и включает isDuressMode', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');

      final ok = await auth.setDuressCode('123456', '654321');
      expect(ok, isTrue);

      auth.lock();
      final r = auth.verifyPin('654321');
      expect(r, equals(PinVerifyResult.duress));
      expect(auth.isUnlocked, isTrue);
      expect(auth.isDuressMode, isTrue);
    });

    test('wipeCode: возвращает wipeCode и НЕ инкрементит failedAttempts', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');

      final ok = await auth.setWipeCode('123456', '111111');
      expect(ok, isTrue);

      // Сперва “набьём” попытки, чтобы было что проверять на reset/no-increment.
      auth.verifyPin('000000');
      auth.verifyPin('000000');
      expect(auth.config.failedAttempts, equals(2));

      auth.lock();
      final r = auth.verifyPin('111111');
      expect(r, equals(PinVerifyResult.wipeCode));
      // Важно: wipeCode — осознанное действие, попытки сбрасываются.
      expect(auth.config.failedAttempts, equals(0));
      // И не должен автоматически “разблокировать”, пока UI не подтвердит wipe.
      expect(auth.isUnlocked, isFalse);
    });

    test('autoWipe: при включенном auto-wipe возвращает autoWipe при достижении лимита', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      await auth.setAutoWipe(true, attempts: 3);

      expect(auth.verifyPin('000000'), equals(PinVerifyResult.invalid));
      expect(auth.verifyPin('000000'), equals(PinVerifyResult.invalid));
      expect(auth.verifyPin('000000'), equals(PinVerifyResult.autoWipe));
      expect(auth.config.failedAttempts, equals(3));
    });

    test('disablePin: требует правильный текущий PIN', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');

      final wrong = await auth.disablePin('000000');
      expect(wrong, isFalse);
      expect(auth.config.isPinEnabled, isTrue);

      final ok = await auth.disablePin('123456');
      expect(ok, isTrue);
      expect(auth.config.isPinEnabled, isFalse);
      expect(auth.requiresUnlock, isFalse);
      expect(auth.isUnlocked, isTrue);
    });

    test('init: повреждённый JSON в storage — сервис падает в safe-default (unlocked)', () async {
      final storage = _InMemoryAuthStorage();
      // Ключ приватный, но контракт важнее: симулируем “битый” конфиг через setPin, затем порчу.
      final auth1 = AuthService.createForTesting(secureStorage: storage);
      await auth1.init();
      await auth1.setPin('123456');

      // Портим всё значение целиком
      storage._kv['orpheus_security_config'] = '{not json';

      final auth2 = AuthService.createForTesting(secureStorage: storage);
      await auth2.init();
      expect(auth2.isUnlocked, isTrue);
      expect(auth2.requiresUnlock, isFalse);
      expect(auth2.config, equals(SecurityConfig.empty));
    });

    test('init: читает то, что пишет (структура JSON совместима)', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');

      final raw = storage._kv['orpheus_security_config'];
      expect(raw, isNotNull);
      final decoded = json.decode(raw!) as Map<String, dynamic>;
      expect(decoded['isPinEnabled'], isTrue);
      expect(decoded['pinHash'], isNotNull);
      expect(decoded['pinSalt'], isNotNull);
    });

    test('setPin с 4-значным PIN: сохраняет pinLength=4 и успешно верифицирует', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      
      await auth.setPin('1234', pinLength: 4);
      
      expect(auth.config.isPinEnabled, isTrue);
      expect(auth.config.pinLength, equals(4));
      
      auth.lock();
      final result = auth.verifyPin('1234');
      expect(result, equals(PinVerifyResult.success));
      expect(auth.isUnlocked, isTrue);
    });

    test('pinLength: default=6 для обратной совместимости при отсутствии поля в storage', () async {
      final storage = _InMemoryAuthStorage();
      // Симулируем старый конфиг без pinLength
      storage._kv['orpheus_security_config'] = json.encode({
        'isPinEnabled': true,
        'pinHash': 'some_hash',
        'pinSalt': 'some_salt',
        // pinLength отсутствует — должен быть 6 по умолчанию
      });
      
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      
      expect(auth.config.pinLength, equals(6));
    });

    test('changePin: сохраняет текущую длину PIN', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      
      await auth.setPin('1234', pinLength: 4);
      expect(auth.config.pinLength, equals(4));
      
      final success = await auth.changePin('1234', '5678');
      expect(success, isTrue);
      expect(auth.config.pinLength, equals(4)); // длина сохранена
      
      auth.lock();
      expect(auth.verifyPin('5678'), equals(PinVerifyResult.success));
    });

    test('setPin с 6-значным PIN (по умолчанию): сохраняет pinLength=6', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      
      await auth.setPin('123456'); // без указания pinLength — default 6
      
      expect(auth.config.pinLength, equals(6));
    });
  });
}






