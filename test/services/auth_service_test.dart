import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/models/security_config.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';

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
    // ARCH-1: verifyPin(duress) теперь пушит duress-режим в DatabaseService.instance
    // (синглтон). Сбрасываем после каждого теста, чтобы флаг не «протёк» в поздний
    // тест (fail-safe, но чистим для изоляции). setDuressMode не трогает реальную БД.
    tearDown(() => DatabaseService.instance.setDuressMode(false));

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

      final r1 = await auth.verifyPin('000000');
      expect(r1, equals(PinVerifyResult.invalid));
      expect(auth.config.failedAttempts, equals(1));
    });

    test('lockout: после достижения 5 неудачных попыток следующая попытка возвращает lockedOut', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      auth.lock();

      for (var i = 0; i < 5; i++) {
        final r = await auth.verifyPin('000000');
        expect(r, equals(PinVerifyResult.invalid));
      }
      expect(auth.config.failedAttempts, equals(5));
      expect(auth.config.isLockedOut, isTrue);

      final duringLock = await auth.verifyPin('123456');
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
      final r = await auth.verifyPin('654321');
      expect(r, equals(PinVerifyResult.duress));
      expect(auth.isUnlocked, isTrue);
      expect(auth.isDuressMode, isTrue);
    });

    test('duress: сеттеры настроек безопасности не меняют реальный конфиг',
        () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      await auth.setAutoWipe(true, attempts: 7);
      await auth.setPanicGestureEnabled(true);
      await auth.setBiometricEnabled(true);
      await auth.setInactivityLockSeconds(30);
      await auth.setMessageRetention(MessageRetentionPolicy.week);

      auth.debugSetDuressMode(true);
      addTearDown(() => auth.debugSetDuressMode(false));

      // Наблюдатель без основного PIN пытается снять защиты жертвы.
      await auth.setAutoWipe(false);
      await auth.setPanicGestureEnabled(false);
      await auth.setBiometricEnabled(false);
      await auth.setInactivityLockSeconds(600);
      await auth.setMessageRetention(MessageRetentionPolicy.all);

      expect(auth.config.isAutoWipeEnabled, isTrue);
      expect(auth.config.autoWipeAttempts, equals(7));
      expect(auth.config.isPanicGestureEnabled, isTrue);
      expect(auth.config.isBiometricEnabled, isTrue);
      expect(auth.config.inactivityLockSeconds, equals(30));
      expect(auth.config.messageRetention, equals(MessageRetentionPolicy.week));

      // И то же самое в persisted-конфиге, а не только в памяти.
      final reloaded = AuthService.createForTesting(secureStorage: storage);
      await reloaded.init();
      expect(reloaded.config.isAutoWipeEnabled, isTrue);
      expect(reloaded.config.inactivityLockSeconds, equals(30));
    });

    test('вне duress те же сеттеры работают (иначе тест выше был бы пустым)',
        () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      await auth.setAutoWipe(true, attempts: 7);
      await auth.setInactivityLockSeconds(30);

      await auth.setAutoWipe(false);
      await auth.setInactivityLockSeconds(600);

      expect(auth.config.isAutoWipeEnabled, isFalse);
      expect(auth.config.inactivityLockSeconds, equals(600));
    });

    test('confirmMainPin внутри duress подтверждает, но НЕ снимает режим', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      expect(await auth.setDuressCode('123456', '654321'), isTrue);

      auth.lock();
      expect(await auth.verifyPin('654321'), equals(PinVerifyResult.duress));
      expect(auth.isDuressMode, isTrue);

      // Жертву заставили подтвердить чувствительное действие основным PIN.
      expect(await auth.confirmMainPin('123456'), isTrue);
      // Подтвердили ОДНО действие, а не вышли из режима: иначе на экране остался бы
      // пустой профиль над разгейченной базой.
      expect(auth.isDuressMode, isTrue,
          reason: 'подтверждение PIN не должно снимать duress-гейт');

      // Duress-код и мусор как подтверждение не проходят.
      expect(await auth.confirmMainPin('654321'), isFalse);
      expect(auth.isDuressMode, isTrue);
      expect(await auth.confirmMainPin('000000'), isFalse);
      expect(auth.isDuressMode, isTrue);
    });

    test('confirmMainPin вне duress работает как обычная проверка', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');

      expect(await auth.confirmMainPin('123456'), isTrue);
      expect(auth.isDuressMode, isFalse);
      expect(await auth.confirmMainPin('999999'), isFalse);
    });

    test('duress: вход не оставляет следа в логе — экран логов доступен наблюдателю',
        () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');
      expect(await auth.setDuressCode('123456', '654321'), isTrue);

      auth.lock();
      expect(await auth.verifyPin('654321'), equals(PinVerifyResult.duress));

      // Трассу берём ЦЕЛИКОМ, без предварительного clear(): слово не должно
      // всплывать ни при настройке кода, ни при входе — экран логов доступен
      // наблюдателю из duress-сессии.
      final trace = DebugLogger.logs
          .map((e) => '${e.tag} ${e.message}')
          .join('\n')
          .toLowerCase();
      expect(trace.contains('duress'), isFalse,
          reason: 'запись про duress в логе — самый разрушительный tell: $trace');
    });

    test('wipeCode: возвращает wipeCode и НЕ инкрементит failedAttempts', () async {
      final storage = _InMemoryAuthStorage();
      final auth = AuthService.createForTesting(secureStorage: storage);
      await auth.init();
      await auth.setPin('123456');

      final ok = await auth.setWipeCode('123456', '111111');
      expect(ok, isTrue);

      // Сперва “набьём” попытки, чтобы было что проверять на reset/no-increment.
      await auth.verifyPin('000000');
      await auth.verifyPin('000000');
      expect(auth.config.failedAttempts, equals(2));

      auth.lock();
      final r = await auth.verifyPin('111111');
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

      expect(await auth.verifyPin('000000'), equals(PinVerifyResult.invalid));
      expect(await auth.verifyPin('000000'), equals(PinVerifyResult.invalid));
      expect(await auth.verifyPin('000000'), equals(PinVerifyResult.autoWipe));
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
      final result = await auth.verifyPin('1234');
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
      expect(await auth.verifyPin('5678'), equals(PinVerifyResult.success));
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






