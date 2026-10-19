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
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/settings_group.dart';

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
          backgroundColor: AppColors.surface,
          title: Text(l10n.confirmation),
          content: Text(
            l10n.willDeleteMessages(toDelete),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
    }
    
    // Применяем новую политику
    await _auth.setMessageRetention(newPolicy);

    // Сеттер — no-op под duress. Сверяемся с конфигом, а не с фактом вызова: иначе
    // экран бодро сообщает «политика применена», хотя ничего не применилось, и это
    // подсказка похуже, чем просто не сдвинувшийся выбор.
    if (_auth.messageRetention != newPolicy) {
      if (mounted) _refresh();
      return;
    }

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
        // Подтверждение — только если флаг действительно сохранился (под duress
        // сеттер no-op, и «биометрия включена» было бы ложью и подсказкой).
        if (_auth.config.isBiometricEnabled) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.biometryEnabled)),
          );
        }
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
    // Под duress с этого экрана убрано ВСЁ, что требует ввести текущий PIN, и обе
    // секции кодов целиком (см. места использования duressActive ниже).
    //
    // Почему так, а не «показать секции в состоянии „не настроено“», как было
    // сделано сначала: любая ветка настройки ведёт в PinSetupScreen, который на
    // первом шаге просит текущий PIN и принимает только настоящий. Наблюдатель,
    // видевший, как приложение открыли кодом принуждения, вводит этот код и получает
    // «неверный PIN» — доказуемое противоречие, которое проверяется за десять секунд
    // (найдено на device-тесте 26.07.2026). Отсутствие кнопки ему сравнить не с чем.
    final duressActive = _auth.isDuressMode;
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
    const sectionGap = SizedBox(height: 24);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(
          l10n.securityTitle,
          style: const TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Секция PIN-кода
            SettingsSectionLabel(l10n.pinCodeSection),
            SettingsGroup(children: [
              if (!isPinEnabled) ...[
                SettingsNote(
                  icon: Icons.info_outline,
                  text: l10n.pinNotSet,
                  color: AppColors.warning,
                ),
                _buildActionButton(
                  icon: Icons.add,
                  title: l10n.setPinCode,
                  subtitle: l10n.setPinCodeDesc,
                  onTap: () => _openPinSetup(PinSetupMode.setPin),
                ),
              ] else ...[
                _buildPinStatusCard(config.pinLength, l10n),
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
                // Под duress эти действия скрыты: каждое начинается с «введите
                // текущий PIN», а текущим для наблюдателя выглядит код принуждения —
                // и получает «неверный PIN» от кода, которым только что открыли
                // приложение. Это ДОКАЗУЕМОЕ противоречие. Отсутствие кнопки
                // наблюдателю проверить не с чем, поэтому убираем кнопки.
                if (!duressActive) ...[
                  _buildActionButton(
                    icon: Icons.edit_outlined,
                    title: l10n.changePinCode,
                    subtitle: l10n.digitCode(config.pinLength),
                    onTap: () => _openPinSetup(PinSetupMode.changePin),
                  ),
                  _buildActionButton(
                    icon: Icons.lock_open,
                    title: l10n.disablePinCode,
                    isDestructive: true,
                    onTap: () => _openPinSetup(PinSetupMode.disablePin),
                  ),
                ],
              ],
            ]),

            sectionGap,

            // Секция биометрии (только если PIN включен)
            if (isPinEnabled && _canUseBiometrics) ...[
              SettingsSectionLabel(l10n.biometrySection),
              SettingsGroup(children: [
                _buildSwitchTile(
                  icon: Icons.fingerprint,
                  title: l10n.unlockWithBiometry,
                  subtitle: l10n.quickEntryWithoutPin,
                  value: config.isBiometricEnabled,
                  onChanged: _toggleBiometrics,
                ),
              ]),
              sectionGap,
            ],

            // Приватность звонка: показывать ли имя звонящего на локскрине
            SettingsGroup(children: [
              _buildSwitchTile(
                icon: Icons.phonelink_lock,
                title: l10n.callerNameOnLockTitle,
                subtitle: l10n.callerNameOnLockDesc,
                value: _showCallerNameOnLock,
                onChanged: (v) async {
                  // Этот тумблер пишет в SharedPreferences, а не в гейтированную БД,
                  // поэтому под duress держатель кода принуждения необратимо включал
                  // бы жертве показ имени звонящего на локскрине. Гейт стоит здесь, а
                  // не в DeviceSettingsService: сервис статический и его читает
                  // push-изолят, где свой AuthService с duress == false.
                  if (duressActive) return;
                  await DeviceSettingsService.setShowCallerNameWhenLocked(v);
                  if (mounted) setState(() => _showCallerNameOnLock = v);
                },
              ),
            ]),
            sectionGap,

            // Секция кода принуждения (только если PIN включен).
            // Под duress секции кодов скрыты целиком. Оставить их без кнопок было бы
            // хуже: пустая секция сама рассказывает наблюдателю, что в приложении
            // ЕСТЬ код принуждения — то самое понятие, о котором ему знать незачем.
            if (isPinEnabled && !duressActive) ...[
              SettingsSectionLabel(l10n.duressCodeSection),
              SettingsGroup(children: [
                _buildInfoCard(
                  icon: Icons.warning_amber,
                  text: l10n.duressCodeInfo,
                  color: AppColors.warning,
                  isMultiLine: true,
                ),
                if (!isDuressEnabled) ...[
                  _buildActionButton(
                    icon: Icons.add,
                    title: l10n.setDuressCode,
                    subtitle: l10n.setDuressCodeDesc(config.pinLength),
                    onTap: () => _openPinSetup(PinSetupMode.setDuress),
                    accentColor: AppColors.warning,
                  ),
                ] else ...[
                  _buildInfoCard(
                    icon: Icons.check_circle_outline,
                    text: l10n.duressCodeSet(config.pinLength),
                    color: AppColors.success,
                  ),
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    title: l10n.disableDuressCode,
                    isDestructive: true,
                    onTap: () => _openPinSetup(PinSetupMode.disableDuress),
                  ),
                ],
              ]),
              sectionGap,
            ],

            // Секция кода удаления (только если PIN включен). Под duress — скрыта,
            // по той же причине, что и секция кода принуждения.
            if (isPinEnabled && !duressActive) ...[
              SettingsSectionLabel(l10n.wipeCodeSection),
              SettingsGroup(children: [
                _buildInfoCard(
                  icon: Icons.warning_amber,
                  text: l10n.wipeCodeInfo,
                  color: AppColors.danger,
                  isMultiLine: true,
                ),
                if (!isWipeCodeEnabled) ...[
                  _buildActionButton(
                    icon: Icons.add,
                    title: l10n.setWipeCode,
                    subtitle: l10n.setWipeCodeDesc(config.pinLength),
                    onTap: () => _openPinSetup(PinSetupMode.setWipeCode),
                    accentColor: AppColors.danger,
                  ),
                ] else ...[
                  _buildInfoCard(
                    icon: Icons.check_circle_outline,
                    text: l10n.wipeCodeSet(config.pinLength),
                    color: AppColors.success,
                  ),
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    title: l10n.disableWipeCode,
                    isDestructive: true,
                    onTap: () => _openPinSetup(PinSetupMode.disableWipeCode),
                  ),
                ],
              ]),
              sectionGap,
            ],

            // Секция автоматического удаления
            if (isPinEnabled) ...[
              SettingsSectionLabel(l10n.bruteForceProtection),
              SettingsGroup(children: [
                _buildSwitchTile(
                  icon: Icons.delete_sweep_outlined,
                  title: l10n.deleteAfterAttempts,
                  subtitle: l10n.autoWipeOnWrongPin,
                  value: config.isAutoWipeEnabled,
                  onChanged: (enabled) async {
                    await _auth.setAutoWipe(enabled);
                    _refresh();
                  },
                  isDestructive: true,
                ),
                if (config.isAutoWipeEnabled)
                  _buildInfoCard(
                    icon: Icons.warning_amber,
                    text: l10n.autoWipeWarning,
                    color: AppColors.danger,
                  ),
              ]),
              sectionGap,
            ],

            // Экстренное удаление (жест) — выключено по умолчанию
            SettingsSectionLabel(l10n.emergencyWipe),
            SettingsGroup(children: [
              _buildSwitchTile(
                icon: Icons.touch_app_outlined,
                title: l10n.enablePanicGesture,
                subtitle: l10n.panicGestureFullDesc,
                value: config.isPanicGestureEnabled,
                onChanged: (enabled) async {
                  await _auth.setPanicGestureEnabled(enabled);
                  _refresh();
                },
                isDestructive: true,
              ),
              _buildInfoCard(
                icon: Icons.info_outline,
                text: l10n.panicGestureWarning,
                color: AppColors.warning,
                isMultiLine: true,
              ),
            ]),

            sectionGap,

            // Секция автоудаления сообщений
            SettingsSectionLabel(l10n.autoDeleteMessages),
            _MessageRetentionSelector(
              currentPolicy: _auth.messageRetention,
              onPolicyChanged: _onRetentionPolicyChanged,
              info: _buildInfoCard(
                icon: Icons.info_outline,
                text: l10n.autoDeleteInfo,
                color: AppColors.textTertiary,
                isMultiLine: true,
              ),
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  /// Пояснение внутри группы (warning / danger / success / нейтральное).
  Widget _buildInfoCard({
    required IconData icon,
    required String text,
    required Color color,
    bool isMultiLine = false,
  }) {
    return SettingsNote(icon: icon, text: text, color: color);
  }

  /// Строка статуса PIN: длина кода моноширинным справа (короткий — warning).
  Widget _buildPinStatusCard(int pinLength, L10n l10n) {
    final isShortPin = pinLength == 4;
    return SettingsRow(
      icon: Icons.verified_user_outlined,
      label: l10n.pinCodeSet,
      subtitle: isShortPin
          ? '${l10n.fastEntry} • ~10 000 ${l10n.combinations}'
          : '${l10n.enhancedSecurity} • ~1 000 000 ${l10n.combinations}',
      value: l10n.digitCode(pinLength),
      valueColor: isShortPin ? AppColors.warning : AppColors.textTertiary,
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
    final tone = accentColor ?? (isDestructive ? AppColors.danger : null);
    return SettingsRow(
      icon: icon,
      label: title,
      subtitle: subtitle,
      onTap: onTap,
      tone: tone,
      labelColor: isDestructive ? AppColors.danger : null,
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
    return SettingsRow(
      icon: icon,
      label: title,
      subtitle: subtitle,
      tone: isDestructive ? AppColors.danger : null,
      trailing: Switch(value: value, onChanged: onChanged),
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
    final items = options.entries
        .map(
          (entry) => DropdownMenuItem<int>(
            value: entry.key,
            child: Text(entry.value),
          ),
        )
        .toList(growable: false);
    final effectiveValue = options.containsKey(value) ? value : options.keys.first;

    return SettingsRow(
      icon: icon,
      label: title,
      subtitle: subtitle,
      trailing: DropdownButton<int>(
        value: effectiveValue,
        items: items,
        dropdownColor: AppColors.surfaceElevated,
        underline: const SizedBox.shrink(),
        isDense: true,
        icon: const Icon(Icons.expand_more,
            size: 18, color: AppColors.textTertiary),
        style: AppTypography.mono(fontSize: 13, color: AppColors.textSecondary),
        onChanged: (next) {
          if (next == null) return;
          onChanged(next);
        },
      ),
    );
  }
}

/// Виджет выбора политики автоудаления сообщений
class _MessageRetentionSelector extends StatelessWidget {
  const _MessageRetentionSelector({
    required this.currentPolicy,
    required this.onPolicyChanged,
    this.info,
  });

  final MessageRetentionPolicy currentPolicy;
  final ValueChanged<MessageRetentionPolicy> onPolicyChanged;

  /// Пояснение первой строкой группы.
  final Widget? info;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingsGroup(
      children: [
        if (info != null) info!,
        for (final policy in MessageRetentionPolicy.values)
          _buildOption(policy, l10n),
      ],
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
    return SettingsRow(
      icon: _getIconForPolicy(policy),
      label: _getDisplayName(policy, l10n),
      subtitle: _getSubtitle(policy, l10n),
      labelColor: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
      onTap: () => onPolicyChanged(policy),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.action, size: 20)
          : const SizedBox(width: 20),
    );
  }

  IconData _getIconForPolicy(MessageRetentionPolicy policy) {
    switch (policy) {
      case MessageRetentionPolicy.all:
        return Icons.all_inclusive;
      case MessageRetentionPolicy.day:
        return Icons.today_outlined;
      case MessageRetentionPolicy.week:
        return Icons.date_range_outlined;
      case MessageRetentionPolicy.month:
        return Icons.calendar_month_outlined;
    }
  }
}
