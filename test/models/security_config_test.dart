import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/security_config.dart';

void main() {
  group('SecurityConfig (контракты безопасности)', () {
    test('requiresUnlock: true только когда включён PIN и задан pinHash', () {
      expect(SecurityConfig.empty.requiresUnlock, isFalse);

      final cfg1 = const SecurityConfig(isPinEnabled: true, pinHash: null, pinSalt: 's');
      expect(cfg1.requiresUnlock, isFalse);

      final cfg2 = const SecurityConfig(isPinEnabled: true, pinHash: 'h', pinSalt: 's');
      expect(cfg2.requiresUnlock, isTrue);
    });

    test('toMap/fromMap: roundtrip сохраняет ключевые поля', () {
      final now = DateTime.utc(2025, 1, 27, 12, 0, 0);
      final original = SecurityConfig(
        isPinEnabled: true,
        pinHash: 'pinHash',
        pinSalt: 'pinSalt',
        isDuressEnabled: true,
        duressHash: 'duressHash',
        duressSalt: 'duressSalt',
        isWipeCodeEnabled: true,
        wipeCodeHash: 'wipeHash',
        wipeCodeSalt: 'wipeSalt',
        isAutoWipeEnabled: true,
        autoWipeAttempts: 12,
        isPanicGestureEnabled: true,
        failedAttempts: 7,
        lastFailedAttempt: now,
        isBiometricEnabled: true,
      );

      final decoded = SecurityConfig.fromMap(original.toMap());

      expect(decoded.isPinEnabled, isTrue);
      expect(decoded.pinHash, equals('pinHash'));
      expect(decoded.pinSalt, equals('pinSalt'));
      expect(decoded.isDuressEnabled, isTrue);
      expect(decoded.duressHash, equals('duressHash'));
      expect(decoded.duressSalt, equals('duressSalt'));
      expect(decoded.isWipeCodeEnabled, isTrue);
      expect(decoded.wipeCodeHash, equals('wipeHash'));
      expect(decoded.wipeCodeSalt, equals('wipeSalt'));
      expect(decoded.isAutoWipeEnabled, isTrue);
      expect(decoded.autoWipeAttempts, equals(12));
      expect(decoded.isPanicGestureEnabled, isTrue);
      expect(decoded.failedAttempts, equals(7));
      expect(decoded.lastFailedAttempt?.toIso8601String(), equals(now.toIso8601String()));
      expect(decoded.isBiometricEnabled, isTrue);
    });

    group('lockout durations (ADR 0003)', () {
      // ADR 0003:
      // 5 попыток  → 30 сек
      // 10 попыток → 1 мин
      // 15 попыток → 5 мин
      // 20 попыток → 30 мин

      SecurityConfig _cfg({required int attempts, required DateTime lastFailedAttempt}) {
        return SecurityConfig(
          isPinEnabled: true,
          pinHash: 'h',
          pinSalt: 's',
          failedAttempts: attempts,
          lastFailedAttempt: lastFailedAttempt,
        );
      }

      test('до 5 попыток блокировки нет', () {
        final now = DateTime.now();
        expect(_cfg(attempts: 4, lastFailedAttempt: now).isLockedOut, isFalse);
      });

      test('5..9 попыток: 30 секунд', () {
        final now = DateTime.now();
        // Внутри окна
        expect(_cfg(attempts: 5, lastFailedAttempt: now).isLockedOut, isTrue);
        expect(_cfg(attempts: 9, lastFailedAttempt: now).isLockedOut, isTrue);
        // После окна
        expect(_cfg(attempts: 5, lastFailedAttempt: now.subtract(const Duration(seconds: 31))).isLockedOut, isFalse);
      });

      test('10..14 попыток: 1 минута', () {
        final now = DateTime.now();
        expect(_cfg(attempts: 10, lastFailedAttempt: now).isLockedOut, isTrue);
        expect(_cfg(attempts: 14, lastFailedAttempt: now).isLockedOut, isTrue);
        expect(_cfg(attempts: 10, lastFailedAttempt: now.subtract(const Duration(seconds: 61))).isLockedOut, isFalse);
      });

      test('15..19 попыток: 5 минут', () {
        final now = DateTime.now();
        expect(_cfg(attempts: 15, lastFailedAttempt: now).isLockedOut, isTrue);
        expect(_cfg(attempts: 19, lastFailedAttempt: now).isLockedOut, isTrue);
        expect(_cfg(attempts: 15, lastFailedAttempt: now.subtract(const Duration(minutes: 5, seconds: 1))).isLockedOut, isFalse);
      });

      test('20+ попыток: 30 минут', () {
        final now = DateTime.now();
        expect(_cfg(attempts: 20, lastFailedAttempt: now).isLockedOut, isTrue);
        expect(_cfg(attempts: 999, lastFailedAttempt: now).isLockedOut, isTrue);
        expect(_cfg(attempts: 20, lastFailedAttempt: now.subtract(const Duration(minutes: 30, seconds: 1))).isLockedOut, isFalse);
      });
    });

    group('isLockedOutMonotonic (тамперо-устойчивая блокировка, LOGIC-6)', () {
      SecurityConfig cfg({required int attempts, required int failedElapsedMs}) {
        return SecurityConfig(
          isPinEnabled: true,
          pinHash: 'h',
          pinSalt: 's',
          failedAttempts: attempts,
          // wall-clock ставим "давно", чтобы fallback НЕ маскировал монотонную логику
          lastFailedAttempt:
              DateTime.now().subtract(const Duration(hours: 1)),
          lastFailedElapsedMs: failedElapsedMs,
        );
      }

      test('монотонно: внутри окна — заблокировано, после — нет', () {
        // 5 попыток → 30с. Сбой на elapsed=1_000_000.
        final c = cfg(attempts: 5, failedElapsedMs: 1000000);
        // now через 10с — заблокировано
        expect(c.isLockedOutMonotonic(1000000 + 10000), isTrue);
        // now через 31с — разблокировано
        expect(c.isLockedOutMonotonic(1000000 + 31000), isFalse);
      });

      test('перевод wall-clock вперёд НЕ снимает блокировку (монотонные часы честны)',
          () {
        // wall-clock уже "час назад" (был бы разблокирован по wall), но монотонно
        // прошло всего 5с из 30с → всё ещё заблокировано.
        final c = cfg(attempts: 5, failedElapsedMs: 1000000);
        expect(c.isLockedOutMonotonic(1000000 + 5000), isTrue);
      });

      test('nowElapsedMs == null (недоступны монотонные часы) → fallback на wall-clock',
          () {
        // wall-clock "час назад" → по fallback разблокировано.
        final c = cfg(attempts: 5, failedElapsedMs: 1000000);
        expect(c.isLockedOutMonotonic(null), isFalse);
      });

      test('ребут (now < сохранённого elapsed) → fallback на wall-clock', () {
        final c = cfg(attempts: 5, failedElapsedMs: 1000000);
        // now меньше сохранённого (elapsedRealtime сбросился) → wall fallback (час назад → false)
        expect(c.isLockedOutMonotonic(500), isFalse);
      });

      test('до 5 попыток монотонной блокировки нет', () {
        expect(cfg(attempts: 4, failedElapsedMs: 1000000)
            .isLockedOutMonotonic(1000000 + 1000), isFalse);
      });
    });

    test('shouldAutoWipe: true когда isAutoWipeEnabled и failedAttempts >= autoWipeAttempts', () {
      const base = SecurityConfig(isAutoWipeEnabled: true, autoWipeAttempts: 10);
      expect(base.copyWith(failedAttempts: 9).shouldAutoWipe, isFalse);
      expect(base.copyWith(failedAttempts: 10).shouldAutoWipe, isTrue);
      expect(base.copyWith(failedAttempts: 999).shouldAutoWipe, isTrue);
    });
  });
}






