// lib/screens/lock_screen.dart
// Экран блокировки с PIN-кодом

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/models/security_config.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/locale_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final VoidCallback onDuressMode;
  final Future<void> Function(WipeReason reason) onWipe;
  final AuthService auth;

  LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onDuressMode,
    required this.onWipe,
    AuthService? auth,
  }) : auth = auth ?? AuthService.instance;

  /// Для виджет/юнит-тестов: можно подменить AuthService, чтобы не зависеть от плагинов.
  LockScreen.forTesting({
    super.key,
    required this.onUnlocked,
    required this.onDuressMode,
    required this.onWipe,
    required AuthService auth,
  }) : auth = auth;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  late final AuthService _auth;
  final _localAuth = LocalAuthentication();
  
  String _enteredPin = '';
  bool _isError = false;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _lockoutTimer;
  
  // Анимации
  late AnimationController _shakeController;
  late AnimationController _pulseController;
  late AnimationController _revealController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();

    _auth = widget.auth;
    
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    
    // Проверяем блокировку
    _checkLockout();
    
    // Пытаемся использовать биометрию
    _tryBiometricAuth();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pulseController.dispose();
    _revealController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _checkLockout() {
    if (_auth.config.isLockedOut) {
      _startLockoutTimer();
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_auth.config.isLockedOut) {
        timer.cancel();
        setState(() {});
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _tryBiometricAuth() async {
    if (!_auth.config.isBiometricEnabled) return;
    
    final locale = LocaleService.instance.effectiveLocale.languageCode;
    final isRu = locale == 'ru';
    
    try {
      final canAuth = await _localAuth.canCheckBiometrics || 
                      await _localAuth.isDeviceSupported();
      if (!canAuth) return;
      
      final didAuth = await _localAuth.authenticate(
        localizedReason: isRu ? 'Разблокируйте Orpheus' : 'Unlock Orpheus',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      
      if (didAuth && mounted) {
        // Биометрия успешна — проверяем основной PIN для разблокировки
        // (биометрия только как быстрый вход, не как duress)
        widget.onUnlocked();
      }
    } catch (e) {
      // Ошибка биометрии
    }
  }

  /// Длина PIN из конфигурации (4 или 6)
  int get _pinLength => _auth.config.pinLength;

  void _onDigitPressed(String digit) {
    if (_auth.config.isLockedOut || _isLoading) return;
    
    HapticFeedback.lightImpact();
    
    setState(() {
      if (_enteredPin.length < _pinLength) {
        _enteredPin += digit;
        _isError = false;
        _errorMessage = null;
      }
    });
    
    // Автоматическая проверка при достижении нужной длины
    if (_enteredPin.length == _pinLength) {
      _verifyPin();
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isEmpty || _isLoading) return;
    
    HapticFeedback.lightImpact();
    
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _isError = false;
      _errorMessage = null;
    });
  }

  Future<void> _verifyPin() async {
    setState(() => _isLoading = true);
    
    // Небольшая задержка для UX
    await Future.delayed(const Duration(milliseconds: 300));
    
    final result = await _auth.verifyPin(_enteredPin);
    
    if (!mounted) return;
    
    setState(() => _isLoading = false);
    
    switch (result) {
      case PinVerifyResult.success:
        HapticFeedback.mediumImpact();
        widget.onUnlocked();
        break;
        
      case PinVerifyResult.duress:
        HapticFeedback.mediumImpact();
        widget.onDuressMode();
        break;

      case PinVerifyResult.wipeCode:
        HapticFeedback.heavyImpact();
        await _showWipeConfirmDialog();
        break;
        
      case PinVerifyResult.invalid:
        _showError();
        break;
        
      case PinVerifyResult.lockedOut:
        _showLockout();
        break;
        
      case PinVerifyResult.autoWipe:
        await widget.onWipe(WipeReason.autoWipe);
        break;
    }
  }

  Future<void> _showWipeConfirmDialog() async {
    // Сброс ввода, чтобы после отмены не оставался код
    setState(() {
      _enteredPin = '';
      _isError = false;
      _errorMessage = null;
    });

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _HoldToWipeDialog(),
    );

    if (confirmed == true && mounted) {
      await widget.onWipe(WipeReason.wipeCode);
    }
  }

  void _showError() {
    final l10n = L10n.of(context);
    HapticFeedback.heavyImpact();
    
    setState(() {
      _isError = true;
      _enteredPin = '';
      
      final remaining = _auth.attemptsUntilWipe;
      if (remaining != null && remaining <= 3) {
        _errorMessage = l10n.attemptsLeft(remaining);
      } else {
        _errorMessage = l10n.wrongPin;
      }
    });
    
    _shakeController.forward().then((_) {
      _shakeController.reset();
    });
  }

  void _showLockout() {
    HapticFeedback.heavyImpact();
    
    setState(() {
      _isError = true;
      _enteredPin = '';
    });
    
    _startLockoutTimer();
  }

  String _formatDuration(Duration duration) {
    final locale = LocaleService.instance.effectiveLocale.languageCode;
    final isRu = locale == 'ru';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return isRu ? '$seconds сек' : '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locale = LocaleService.instance.effectiveLocale.languageCode;
    final isRu = locale == 'ru';
    final isLockedOut = _auth.config.isLockedOut;
    final timeUntilUnlock = _auth.timeUntilUnlock;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Фоновые частицы
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => CustomPaint(
              size: Size.infinite,
              painter: _LockParticlesPainter(_pulseController.value),
            ),
          ),
          
          // Основной контент
          SafeArea(
            child: FadeTransition(
              opacity: _revealController,
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  
                  // Логотип
                  _buildLogo(),
                  
                  const SizedBox(height: 24),
                  
                  // Заголовок
                  Text(
                    isLockedOut 
                        ? (isRu ? 'ЗАБЛОКИРОВАНО' : 'LOCKED') 
                        : (isRu ? 'ВВЕДИТЕ PIN' : 'ENTER PIN'),
                    style: TextStyle(
                      color: isLockedOut ? Colors.red.shade400 : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Сообщение об ошибке или таймер
                  if (isLockedOut && timeUntilUnlock != null)
                    Text(
                      isRu 
                          ? 'Повтор через ${_formatDuration(timeUntilUnlock)}'
                          : 'Retry in ${_formatDuration(timeUntilUnlock)}',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 14,
                      ),
                    )
                  else if (_errorMessage != null)
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 14,
                      ),
                    ),
                  
                  const SizedBox(height: 32),
                  
                  // PIN индикаторы
                  _buildPinIndicators(),
                  
                  const Spacer(flex: 1),
                  
                  // PIN-pad
                  if (!isLockedOut) _buildPinPad(),
                  
                  const Spacer(flex: 2),
                  
                  // Биометрия
                  if (_auth.config.isBiometricEnabled && !isLockedOut)
                    _buildBiometricButton(l10n),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF121212),
            border: Border.all(
              color: const Color(0xFFB0BEC5).withOpacity(0.2 + 0.1 * _pulseController.value),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB0BEC5).withOpacity(0.1 + 0.05 * _pulseController.value),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.png',
              width: 60,
              height: 60,
              errorBuilder: (c, e, s) => const Icon(
                Icons.shield,
                color: Color(0xFFB0BEC5),
                size: 40,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPinIndicators() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final shake = sin(_shakeAnimation.value * pi * 4) * 10;
        
        return Transform.translate(
          offset: Offset(shake, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pinLength, (index) {
              final isFilled = index < _enteredPin.length;
              final isActive = index == _enteredPin.length;
              
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: isFilled ? 16 : 14,
                height: isFilled ? 16 : 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isError
                      ? Colors.red.shade400
                      : isFilled
                          ? const Color(0xFFB0BEC5)
                          : Colors.transparent,
                  border: Border.all(
                    color: _isError
                        ? Colors.red.shade400
                        : isActive
                            ? const Color(0xFFB0BEC5)
                            : Colors.grey.shade700,
                    width: isActive ? 2 : 1,
                  ),
                  boxShadow: isFilled && !_isError
                      ? [
                          BoxShadow(
                            color: const Color(0xFFB0BEC5).withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildPinPad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          _buildPinRow(['1', '2', '3']),
          const SizedBox(height: 16),
          _buildPinRow(['4', '5', '6']),
          const SizedBox(height: 16),
          _buildPinRow(['7', '8', '9']),
          const SizedBox(height: 16),
          _buildPinRow(['', '0', 'backspace']),
        ],
      ),
    );
  }

  Widget _buildPinRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((digit) {
        if (digit.isEmpty) {
          return const SizedBox(width: 72);
        }
        if (digit == 'backspace') {
          return _buildBackspaceButton();
        }
        return _buildDigitButton(digit);
      }).toList(),
    );
  }

  Widget _buildDigitButton(String digit) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : () => _onDigitPressed(digit),
        borderRadius: BorderRadius.circular(36),
        splashColor: const Color(0xFFB0BEC5).withOpacity(0.3),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _onBackspacePressed,
        borderRadius: BorderRadius.circular(36),
        splashColor: Colors.red.withOpacity(0.2),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.grey.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              color: Colors.grey.shade500,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton(L10n l10n) {
    return TextButton.icon(
      onPressed: _tryBiometricAuth,
      icon: Icon(
        Icons.fingerprint,
        color: Colors.grey.shade500,
      ),
      label: Text(
        l10n.useBiometry,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Причина выполнения wipe (для логов/аналитики/UX)
enum WipeReason {
  /// Код удаления (wipe code)
  wipeCode,
  /// Авто-wipe после неверных попыток
  autoWipe,
}

class _HoldToWipeDialog extends StatefulWidget {
  const _HoldToWipeDialog();

  @override
  State<_HoldToWipeDialog> createState() => _HoldToWipeDialogState();
}

class _HoldToWipeDialogState extends State<_HoldToWipeDialog> {
  static const _holdDuration = Duration(seconds: 2);
  Timer? _timer;
  double _progress = 0;
  bool _isHolding = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (_isHolding) return;
    setState(() {
      _isHolding = true;
      _progress = 0;
    });

    final start = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final elapsed = DateTime.now().difference(start);
      final p = (elapsed.inMilliseconds / _holdDuration.inMilliseconds).clamp(0.0, 1.0);
      if (!mounted) return;
      setState(() => _progress = p);
      if (p >= 1.0) {
        t.cancel();
        Navigator.of(context).pop(true);
      }
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    setState(() {
      _isHolding = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Язык берём из виджет-дерева (как и l10n выше), а не из глобального синглтона —
    // в проде MaterialApp.locale резолвится из того же LocaleService.effectiveLocale.
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return AlertDialog(
      backgroundColor: const Color(0xFF120505),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.red.withOpacity(0.35)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isRu ? 'УДАЛИТЬ ВСЕ ДАННЫЕ?' : 'DELETE ALL DATA?',
              style: const TextStyle(color: Colors.red, fontSize: 14, letterSpacing: 1),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.deleteAccountWarning,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.06),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.red.withOpacity(0.9)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isHolding 
                ? (isRu ? 'Удерживайте...' : 'Hold...')
                : (isRu ? 'Удерживайте кнопку ниже 2 секунды' : 'Hold the button below for 2 seconds'),
            style: TextStyle(color: Colors.red.shade200, fontSize: 12),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onLongPressStart: (_) => _startHold(),
                onLongPressEnd: (_) => _cancelHold(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      isRu ? 'УДЕРЖИВАТЬ' : 'HOLD',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Частицы на фоне экрана блокировки
class _LockParticlesPainter extends CustomPainter {
  final double animationValue;
  _LockParticlesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = Random(42);
    
    for (int i = 0; i < 30; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final particleSize = 1.0 + random.nextDouble() * 2;
      
      final opacity = 0.05 + 0.08 * sin(animationValue * pi * 2 + i * 0.3);
      
      canvas.drawCircle(
        Offset(x, y),
        particleSize,
        paint..color = const Color(0xFFB0BEC5).withOpacity(opacity.clamp(0.02, 0.15)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
