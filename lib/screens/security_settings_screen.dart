// lib/screens/security_settings_screen.dart
// Экран настроек безопасности

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/screens/pin_setup_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/message_cleanup_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  final AuthService auth;

  SecuritySettingsScreen({super.key, AuthService? auth})
      : auth = auth ?? AuthService.instance;

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> with SingleTickerProviderStateMixin {
  late final AuthService _auth;
  final _localAuth = LocalAuthentication();
  
  bool _canUseBiometrics = false;
  bool _showCallerNameOnLock = false;
  late AnimationController _revealController;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth;

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _checkBiometrics();
    _loadCallPrivacy();
  }

  Future<void> _loadCallPrivacy() async {
    final value = await DeviceSettingsService.showCallerNameWhenLocked();
    if (mounted) setState(() => _showCallerNameOnLock = value);
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics || 
                      await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(() => _canUseBiometrics = canAuth);
      }
    } catch (e) {
      print("Biometrics check error: $e");
    }
  }

  void _refresh() {
    setState(() {});
  }

  Future<void> _openPinSetup(PinSetupMode mode) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PinSetupScreen(
          mode: mode,
          onSuccess: _refresh,
        ),
      ),
    );
    
    if (result == true && mounted) {
      _refresh();
    }
  }

  Future<void> _onRetentionPolicyChanged(MessageRetentionPolicy newPolicy) async {
    final l10n = L10n.of(context);
    // Получаем preview количества сообщений для удаления
    final toDelete = await MessageCleanupService.instance.getCleanupPreview(newPolicy);
    
    // Если будут удалены сообщения — запрашиваем подтверждение
    if (toDelete > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(l10n.confirmation),
          content: Text(
            l10n.willDeleteMessages(toDelete),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
    }
    
    // Применяем новую политику
    await _auth.setMessageRetention(newPolicy);
    
    // Запускаем очистку по новой политике
    final result = await MessageCleanupService.instance.onRetentionPolicyChanged(newPolicy);
    
    if (mounted) {
      _refresh();
      
      // Показываем результат
      final message = result.isSuccess && result.deletedCount > 0
          ? l10n.deleted(result.deletedCount)
          : l10n.policyApplied(newPolicy.displayName);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _toggleBiometrics(bool enabled) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (enabled) {
      // Включение требует подтверждения биометрией (иначе кто угодно с
      // разблокированным экраном включит вход по своему отпечатку).
      try {
        final didAuth = await _localAuth.authenticate(
          localizedReason: l10n.confirmForBiometry,
          persistAcrossBackgrounding: true,
          biometricOnly: true,
        );

        if (!didAuth) {
          // Не подтвердил — тумблер вернётся в «выкл» (config не менялся).
          _refresh();
          return;
        }

        // Реально сохраняем флаг: теперь lock_screen предложит вход по биометрии.
        await _auth.setBiometricEnabled(true);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.biometryEnabled)),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.biometryFailed)),
        );
      }
    } else {
      // Выключение — без биометрического запроса.
      await _auth.setBiometricEnabled(false);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final config = _auth.config;
    final isPinEnabled = config.isPinEnabled;
    final isDuressEnabled = config.isDuressEnabled;
    final isWipeCodeEnabled = config.isWipeCodeEnabled;
    final inactivityOptions = <int, String>{
      30: l10n.inactivity30s,
      60: l10n.inactivity1m,
      300: l10n.inactivity5m,
      600: l10n.inactivity10m,
    };
    final inactivitySeconds = inactivityOptions.containsKey(config.inactivityLockSeconds)
        ? config.inactivityLockSeconds
        : 60;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          l10n.securityTitle,
          style: const TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Секция PIN-кода
            _buildSectionHeader(l10n.pinCodeSection, Icons.lock_outline),
            const SizedBox(height: 12),
            
            if (!isPinEnabled) ...[
              _buildInfoCard(
                icon: Icons.info_outline,
                text: l10n.pinNotSet,
                color: Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.add,
                title: l10n.setPinCode,
                subtitle: l10n.setPinCodeDesc,
                onTap: () => _openPinSetup(PinSetupMode.setPin),
              ),
            ] else ...[
              _buildPinStatusCard(config.pinLength, l10n),
              const SizedBox(height: 12),
              _buildSelectTile(
                icon: Icons.timer_outlined,
                title: l10n.inactivityLockTitle,
                subtitle: l10n.inactivityLockDesc,
                value: inactivitySeconds,
                options: inactivityOptions,
                onChanged: (value) async {
                  await _auth.setInactivityLockSeconds(value);
                  _refresh();
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                icon: Icons.edit,
                title: l10n.changePinCode,
                subtitle: l10n.digitCode(config.pinLength),
                onTap: () => _openPinSetup(PinSetupMode.changePin),
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                icon: Icons.lock_open,
                title: l10n.disablePinCode,
                isDestructive: true,
                onTap: () => _openPinSetup(PinSetupMode.disablePin),
              ),
            ],
            
            const SizedBox(height: 32),
            
            // Секция биометрии (только если PIN включен)
            if (isPinEnabled && _canUseBiometrics) ...[
              _buildSectionHeader(l10n.biometrySection, Icons.fingerprint),
              const SizedBox(height: 12),
              _buildSwitchTile(
                icon: Icons.fingerprint,
                title: l10n.unlockWithBiometry,
                subtitle: l10n.quickEntryWithoutPin,
                value: config.isBiometricEnabled,
                onChanged: _toggleBiometrics,
              ),
              const SizedBox(height: 32),
            ],
            
            // Приватность звонка: показывать ли имя звонящего на локскрине
            _buildSwitchTile(
              icon: Icons.phonelink_lock,
              title: l10n.callerNameOnLockTitle,
              subtitle: l10n.callerNameOnLockDesc,
              value: _showCallerNameOnLock,
              onChanged: (v) async {
                await DeviceSettingsService.setShowCallerNameWhenLocked(v);
                if (mounted) setState(() => _showCallerNameOnLock = v);
              },
            ),
            const SizedBox(height: 32),

            // Секция кода принуждения (только если PIN включен)
            if (isPinEnabled) ...[
              _buildSectionHeader(l10n.duressCodeSection, Icons.shield_outlined),
              const SizedBox(height: 12),
              
              _buildInfoCard(
                icon: Icons.warning_amber,
                text: l10n.duressCodeInfo,
                color: Colors.amber,
                isMultiLine: true,
              ),
              const SizedBox(height: 12),
              
              if (!isDuressEnabled) ...[
                _buildActionButton(
                  icon: Icons.add,
                  title: l10n.setDuressCode,
                  subtitle: l10n.setDuressCodeDesc(config.pinLength),
                  onTap: () => _openPinSetup(PinSetupMode.setDuress),
                  accentColor: Colors.amber,
                ),
              ] else ...[
                _buildInfoCard(
                  icon: Icons.check_circle_outline,
                  text: l10n.duressCodeSet(config.pinLength),
                  color: const Color(0xFF6AD394),
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  icon: Icons.delete_outline,
                  title: l10n.disableDuressCode,
                  isDestructive: true,
                  onTap: () => _openPinSetup(PinSetupMode.disableDuress),
                ),
              ],
              
              const SizedBox(height: 32),
            ],

            // Секция кода удаления (только если PIN включен)
            if (isPinEnabled) ...[
              _buildSectionHeader(l10n.wipeCodeSection, Icons.delete_forever),
              const SizedBox(height: 12),

              _buildInfoCard(
                icon: Icons.warning_amber,
                text: l10n.wipeCodeInfo,
                color: Colors.red,
                isMultiLine: true,
              ),
              const SizedBox(height: 12),

              if (!isWipeCodeEnabled) ...[
                _buildActionButton(
                  icon: Icons.add,
                  title: l10n.setWipeCode,
                  subtitle: l10n.setWipeCodeDesc(config.pinLength),
                  onTap: () => _openPinSetup(PinSetupMode.setWipeCode),
                  accentColor: Colors.red,
                ),
              ] else ...[
                _buildInfoCard(
                  icon: Icons.check_circle_outline,
                  text: l10n.wipeCodeSet(config.pinLength),
                  color: const Color(0xFF6AD394),
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  icon: Icons.delete_outline,
                  title: l10n.disableWipeCode,
                  isDestructive: true,
                  onTap: () => _openPinSetup(PinSetupMode.disableWipeCode),
                ),
              ],

              const SizedBox(height: 32),
            ],
            
            // Секция автоматического удаления
            if (isPinEnabled) ...[
              _buildSectionHeader(l10n.bruteForceProtection, Icons.delete_forever),
              const SizedBox(height: 12),
              
              _buildSwitchTile(
                icon: Icons.delete_sweep,
                title: l10n.deleteAfterAttempts,
                subtitle: l10n.autoWipeOnWrongPin,
                value: config.isAutoWipeEnabled,
                onChanged: (enabled) async {
                  await _auth.setAutoWipe(enabled);
                  _refresh();
                },
                isDestructive: true,
              ),
              
              if (config.isAutoWipeEnabled) ...[
                const SizedBox(height: 8),
                _buildInfoCard(
                  icon: Icons.warning,
                  text: l10n.autoWipeWarning,
                  color: Colors.red,
                ),
              ],
              
              const SizedBox(height: 32),
            ],
            
            // Экстренное удаление (жест) — выключено по умолчанию
            _buildSectionHeader(l10n.emergencyWipe, Icons.bolt),
            const SizedBox(height: 12),
            _buildSwitchTile(
              icon: Icons.touch_app,
              title: l10n.enablePanicGesture,
              subtitle: l10n.panicGestureFullDesc,
              value: config.isPanicGestureEnabled,
              onChanged: (enabled) async {
                await _auth.setPanicGestureEnabled(enabled);
                _refresh();
              },
              isDestructive: true,
            ),
            const SizedBox(height: 10),
            _buildInfoCard(
              icon: Icons.info_outline,
              text: l10n.panicGestureWarning,
              color: Colors.orange,
              isMultiLine: true,
            ),
            
            const SizedBox(height: 32),
            
            // Секция автоудаления сообщений
            _buildSectionHeader(l10n.autoDeleteMessages, Icons.auto_delete),
            const SizedBox(height: 12),
            
            _buildInfoCard(
              icon: Icons.info_outline,
              text: l10n.autoDeleteInfo,
              color: Colors.blue,
              isMultiLine: true,
            ),
            const SizedBox(height: 12),
            
            _MessageRetentionSelector(
              currentPolicy: _auth.messageRetention,
              onPolicyChanged: _onRetentionPolicyChanged,
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade500, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String text,
    required Color color,
    bool isMultiLine = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withOpacity(0.9),
                fontSize: 13,
                height: isMultiLine ? 1.4 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Карточка статуса PIN с индикатором длины — вау-эффект ✨
  Widget _buildPinStatusCard(int pinLength, L10n l10n) {
    const color = Color(0xFF6AD394);
    final isShortPin = pinLength == 4;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.verified_user,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.pinCodeSet,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isShortPin 
                            ? Colors.amber.withOpacity(0.2)
                            : color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l10n.digitCode(pinLength),
                        style: TextStyle(
                          color: isShortPin ? Colors.amber : color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isShortPin 
                      ? '${l10n.fastEntry} • ~10 000 ${l10n.combinations}'
                      : '${l10n.enhancedSecurity} • ~1 000 000 ${l10n.combinations}',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    Color? accentColor,
  }) {
    final color = accentColor ?? (isDestructive ? Colors.red.shade400 : const Color(0xFFB0BEC5));
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDestructive 
                  ? Colors.red.withOpacity(0.2) 
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDestructive ? Colors.red.shade300 : Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade700, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red.shade400 : const Color(0xFFB0BEC5);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDestructive 
              ? Colors.red.withOpacity(0.2) 
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDestructive ? Colors.red.shade300 : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: isDestructive ? Colors.red : const Color(0xFF6AD394),
            activeTrackColor: (isDestructive ? Colors.red : const Color(0xFF6AD394)).withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required int value,
    required Map<int, String> options,
    required ValueChanged<int> onChanged,
  }) {
    final color = const Color(0xFFB0BEC5);
    final items = options.entries
        .map(
          (entry) => DropdownMenuItem<int>(
            value: entry.key,
            child: Text(entry.value),
          ),
        )
        .toList(growable: false);
    final effectiveValue = options.containsKey(value) ? value : options.keys.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          DropdownButton<int>(
            value: effectiveValue,
            items: items,
            dropdownColor: const Color(0xFF1A1A1A),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white),
            onChanged: (next) {
              if (next == null) return;
              onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}

/// Виджет выбора политики автоудаления сообщений
class _MessageRetentionSelector extends StatelessWidget {
  const _MessageRetentionSelector({
    required this.currentPolicy,
    required this.onPolicyChanged,
  });

  final MessageRetentionPolicy currentPolicy;
  final ValueChanged<MessageRetentionPolicy> onPolicyChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < MessageRetentionPolicy.values.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.white.withOpacity(0.05)),
            _buildOption(MessageRetentionPolicy.values[i], l10n),
          ],
        ],
      ),
    );
  }

  String _getDisplayName(MessageRetentionPolicy policy, L10n l10n) {
    switch (policy) {
      case MessageRetentionPolicy.all:
        return l10n.retentionAll;
      case MessageRetentionPolicy.day:
        return l10n.retentionDay;
      case MessageRetentionPolicy.week:
        return l10n.retentionWeekOption;
      case MessageRetentionPolicy.month:
        return l10n.retentionMonthOption;
    }
  }

  String _getSubtitle(MessageRetentionPolicy policy, L10n l10n) {
    switch (policy) {
      case MessageRetentionPolicy.all:
        return l10n.retentionAllSubtitle;
      case MessageRetentionPolicy.day:
        return l10n.retentionDaySubtitle;
      case MessageRetentionPolicy.week:
        return l10n.retentionWeekSubtitle;
      case MessageRetentionPolicy.month:
        return l10n.retentionMonthSubtitle;
    }
  }

  Widget _buildOption(MessageRetentionPolicy policy, L10n l10n) {
    final isSelected = policy == currentPolicy;
    final icon = _getIconForPolicy(policy);
    final color = _getColorForPolicy(policy);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPolicyChanged(policy),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(isSelected ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getDisplayName(policy, l10n),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getSubtitle(policy, l10n),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6AD394).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF6AD394),
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForPolicy(MessageRetentionPolicy policy) {
    switch (policy) {
      case MessageRetentionPolicy.all:
        return Icons.all_inclusive;
      case MessageRetentionPolicy.day:
        return Icons.today;
      case MessageRetentionPolicy.week:
        return Icons.date_range;
      case MessageRetentionPolicy.month:
        return Icons.calendar_month;
    }
  }

  Color _getColorForPolicy(MessageRetentionPolicy policy) {
    switch (policy) {
      case MessageRetentionPolicy.all:
        return const Color(0xFFB0BEC5);
      case MessageRetentionPolicy.day:
        return Colors.red.shade400;
      case MessageRetentionPolicy.week:
        return Colors.orange.shade400;
      case MessageRetentionPolicy.month:
        return Colors.blue.shade400;
    }
  }
}
