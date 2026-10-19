import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/screens/debug_logs_screen.dart';
import 'package:orpheus_project/screens/help_screen.dart';
import 'package:orpheus_project/screens/purchase_screen.dart';
import 'package:orpheus_project/screens/security_settings_screen.dart';
import 'package:orpheus_project/screens/support_chat_screen.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/updates_screen.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/language_selector.dart';
import 'package:orpheus_project/widgets/settings_group.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Счётчик тапов для скрытого меню отладки
  int _secretTapCount = 0;
  DateTime? _lastTapTime;

  // Состояние копирования
  bool _isCopied = false;

  // Статистика
  Map<String, int> _stats = const {'contacts': 0, 'messages': 0, 'sent': 0};

  // App info (реальная версия/билд из платформы)
  String? _appVersionLabel;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAppInfo();
    LocaleService.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  Future<void> _showNotificationSettingsDialog() async {
    final l10n = L10n.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        icon: Icons.notifications_none,
        title: l10n.notificationSettings,
        contentWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  DeviceSettingsService.showSetupDialog(context);
                },
                child: Text(l10n.systemNotificationSettings),
              ),
            ),
          ],
        ),
        primaryLabel: l10n.close,
      ),
    );
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStats() async {
    final stats = await DatabaseService.instance.getProfileStats();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersionLabel = '${info.version}+${info.buildNumber}');
    } catch (e) {
      DebugLogger.warn('APPINFO', 'Failed to get app version: $e');
    }
  }

  void _handleSecretTap() {
    // Под duress экран логов недоступен: в нём лежит RAM-лог реальной сессии, а
    // кнопка «Поделиться» отдаёт файл лога с диска (его DebugLogger.clear() не
    // трогает). Молча ничего не делаем — жест и так секретный, отсутствие реакции
    // ничего не выдаёт.
    if (authService.isDuressMode) return;
    final now = DateTime.now();

    if (_lastTapTime != null && now.difference(_lastTapTime!).inSeconds > 2) {
      _secretTapCount = 0;
    }

    _lastTapTime = now;
    _secretTapCount++;

    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      DebugLogger.info('UI', 'Debug logs screen opened via secret tap');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DebugLogsScreen()),
      );
    }
  }

  Future<void> _exportAccount() async {
    final l10n = L10n.of(context);

    // Under duress the system gate must be skipped entirely: with
    // biometricOnly: false it accepts the DEVICE passcode, which a coercing
    // observer normally has — and what is exported is the 32-byte root seed, the
    // whole identity. Only the app PIN proves the real owner is asking, and
    // _verifyWithAppPin goes through confirmMainPin, which accepts the main PIN
    // only (the duress code is rejected) and does NOT lift the duress gate.
    final requireAppPin = authService.isDuressMode;

    // Try system authentication (biometric + device credentials)
    bool authenticated = false;
    bool systemAuthAvailable = false;
    try {
      final LocalAuthentication auth = LocalAuthentication();
      systemAuthAvailable = !requireAppPin &&
          (await auth.canCheckBiometrics || await auth.isDeviceSupported());

      if (systemAuthAvailable) {
        authenticated = await auth.authenticate(
          localizedReason: l10n.confirmIdentity,
          persistAcrossBackgrounding: true,
          biometricOnly: false,
        );
        // User explicitly cancelled — don't fall through to PIN
        if (!authenticated) return;
      }
    } catch (e) {
      debugPrint('System auth failed, falling back to app PIN: $e');
    }

    // Fallback: verify with app PIN when system auth unavailable or threw
    if (!authenticated && mounted) {
      authenticated = await _verifyWithAppPin(l10n);
    }

    if (!authenticated || !mounted) return;

    try {
      final privateKey = await cryptoService.getPrivateKeyBase64();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => _ExportKeyDialog(privateKey: privateKey),
      );
    } catch (e) {
      debugPrint('Export key error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authError)),
        );
      }
    }
  }

  Future<bool> _verifyWithAppPin(L10n l10n) async {
    if (!authService.config.isPinEnabled) {
      // No app PIN set — user already authenticated via lock screen
      return true;
    }

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PinVerifyDialog(
        title: l10n.confirmIdentity,
        pinLength: authService.config.pinLength,
      ),
    );

    if (pin == null || !mounted) return false;

    // confirmMainPin, а не verifyPin: внутри duress-сессии обычная проверка сняла бы
    // гейт БД и оставила пустой профиль над реальными данными.
    if (await authService.confirmMainPin(pin)) return true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.wrongPin)),
      );
    }
    return false;
  }

  Future<void> _copyToClipboard(String text) async {
    final l10n = L10n.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _isCopied = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.idCopied)),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isCopied = false);
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );

    if (confirmed != true) return;

    await authService.performWipe();
    // State reset (_keysExist=false) is handled by AuthService.onWipeCompleted.
    // Just pop to root — _buildHome() now returns WelcomeScreen.
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Мой QR — тот же QrImageView, что раньше стоял карточкой на экране, теперь
  /// за кнопкой в нижнем листе. Данные те же: публичный ключ.
  void _showMyQr(String myKey, L10n l10n) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => MyQrSheet(myKey: myKey, l10n: l10n),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final myKey = cryptoService.addressBase64 ?? l10n.error;
    final versionLabel = _appVersionLabel ?? AppConfig.appVersion;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleSecretTap,
          child: Text(l10n.profile),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileIdentityCard(
              myKey: myKey,
              l10n: l10n,
              isCopied: _isCopied,
              onCopy: () => _copyToClipboard(myKey),
              onShowQr: () => _showMyQr(myKey, l10n),
            ),
            const SizedBox(height: 14),
            ProfileStatsGroup(stats: _stats, l10n: l10n),
            const SizedBox(height: 14),
            ProfileMenuGroups(
              l10n: l10n,
              onShare: () => SharePlus.instance
                  .share(ShareParams(text: l10n.shareMessage(myKey))),
              onBuyPremium: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PurchaseScreen(
                    onConfirmed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
              onSecurity: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => SecuritySettingsScreen()),
              // mounted-guarded: a duress unlock drops this route and completes the
              // future after Settings itself has been disposed.
              ).then((_) {
                if (mounted) setState(() {});
              }),
              onSupport: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SupportChatScreen()),
              ),
              onHelp: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpScreen()),
              ),
              onUpdates: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UpdatesScreen()),
              ),
              onExport: _exportAccount,
              onNotifications: _showNotificationSettingsDialog,
              onLanguage: () => LanguageSelector.showPicker(
                context,
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(height: 14),
            ProfileVersionGroup(
              versionLabel: versionLabel,
              l10n: l10n,
              registrationDate: cryptoService.registrationDate,
              onCheckUpdates: () => UpdateService.checkForUpdate(context, showNoUpdateFeedback: true),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: _showDeleteAccountDialog,
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                label: Text(l10n.deleteAccount,
                    style: const TextStyle(color: AppColors.danger)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Части профиля. Публичные (без «_») только ради визуального превью в
// test/visual_preview: состояние и сервисы остаются в _SettingsScreenState.
// ─────────────────────────────────────────────────────────────────────────────

/// Карточка личности: аватар-квадрат, «Ваш ID», ключ моноширинным, кнопка «Мой QR».
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.myKey,
    required this.l10n,
    required this.isCopied,
    required this.onCopy,
    required this.onShowQr,
    this.showBadge = true,
  });

  final String myKey;
  final L10n l10n;
  final bool isCopied;
  final VoidCallback onCopy;
  final VoidCallback onShowQr;

  /// Превью без BadgeService выключает табличку.
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final gradient = AppAvatarColors.gradientFromName(myKey);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.sm,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      ),
                      boxShadow: AppShadows.bevel(),
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: AppColors.textPrimary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                l10n.yourId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (showBadge) ...[
                              const SizedBox(width: 8),
                              UserBadge(pubkey: myKey, compact: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          myKey,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.mono(
                            fontSize: 11.5,
                            color: AppColors.textTertiary,
                            letterSpacing: 0.3,
                          ).copyWith(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isCopied ? Icons.check : Icons.copy,
                    size: 18,
                    color:
                        isCopied ? AppColors.success : AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: AppColors.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: AppColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onShowQr,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_2,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.myQrCodeButton,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Нижний лист с моим QR-кодом (тот же QR, что раньше был карточкой на экране).
class MyQrSheet extends StatelessWidget {
  const MyQrSheet({super.key, required this.myKey, required this.l10n});
  final String myKey;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(l10n.qrCode, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadii.md,
              ),
              child: QrImageView(
                data: myKey,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: AppColors.bg),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.bg,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              myKey,
              textAlign: TextAlign.center,
              style: AppTypography.mono(
                fontSize: 11.5,
                color: AppColors.textTertiary,
              ).copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Статистика: три моноширинных числа в группе.
class ProfileStatsGroup extends StatelessWidget {
  const ProfileStatsGroup({super.key, required this.stats, required this.l10n});
  final Map<String, int> stats;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.sm,
      ),
      child: Row(
        children: [
          _stat(context, stats['contacts'] ?? 0,
              l10n.contactsCount(stats['contacts'] ?? 0)),
          _divider(),
          _stat(context, stats['messages'] ?? 0,
              l10n.messagesCount(stats['messages'] ?? 0)),
          _divider(),
          _stat(context, stats['sent'] ?? 0, l10n.sentCount),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 28, color: AppColors.divider);

  Widget _stat(BuildContext context, int value, String label) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: AppTypography.mono(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Пункты профиля в сгруппированных списках.
class ProfileMenuGroups extends StatelessWidget {
  const ProfileMenuGroups({
    super.key,
    required this.l10n,
    required this.onShare,
    required this.onBuyPremium,
    required this.onSecurity,
    required this.onSupport,
    required this.onHelp,
    required this.onUpdates,
    required this.onExport,
    required this.onNotifications,
    required this.onLanguage,
  });

  final L10n l10n;
  final VoidCallback onShare;
  final VoidCallback onBuyPremium;
  final VoidCallback onSecurity;
  final VoidCallback onSupport;
  final VoidCallback onHelp;
  final VoidCallback onUpdates;
  final VoidCallback onExport;
  final VoidCallback onNotifications;
  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context) {
    final isSystem = LocaleService.instance.isSystemLocale;
    final languageValue = isSystem
        ? l10n.systemDefault
        : LocaleService.getLanguageName(LocaleService.instance.effectiveLocale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.shield_outlined,
            label: l10n.security,
            subtitle: l10n.securityDesc,
            onTap: onSecurity,
          ),
          SettingsRow(
            icon: Icons.key_outlined,
            label: l10n.exportAccount,
            subtitle: l10n.exportAccountDesc,
            onTap: onExport,
            tone: AppColors.danger,
          ),
          SettingsRow(
            icon: Icons.share_outlined,
            label: l10n.share,
            onTap: onShare,
          ),
        ]),
        const SizedBox(height: 14),
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.language,
            label: l10n.language,
            value: languageValue,
            onTap: onLanguage,
          ),
          SettingsRow(
            icon: Icons.notifications_none,
            label: l10n.notificationSettings,
            subtitle: l10n.notificationSettingsDesc,
            onTap: onNotifications,
          ),
        ]),
        const SizedBox(height: 14),
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.support_agent,
            label: l10n.support,
            subtitle: l10n.supportDesc,
            onTap: onSupport,
          ),
          SettingsRow(
            icon: Icons.help_outline,
            label: l10n.howToUse,
            subtitle: l10n.howToUseDesc,
            onTap: onHelp,
          ),
          SettingsRow(
            icon: Icons.history,
            label: l10n.updateHistory,
            onTap: onUpdates,
          ),
          SettingsRow(
            icon: Icons.workspace_premium_outlined,
            label: l10n.buyLicense,
            onTap: onBuyPremium,
          ),
        ]),
      ],
    );
  }
}

/// Версия: «Orpheus» + номер сборки моноширинным, дата создания аккаунта, «Проверить».
class ProfileVersionGroup extends StatelessWidget {
  const ProfileVersionGroup({
    super.key,
    required this.versionLabel,
    required this.l10n,
    required this.registrationDate,
    required this.onCheckUpdates,
  });

  final String versionLabel;
  final L10n l10n;
  final DateTime? registrationDate;
  final VoidCallback onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    final locale = LocaleService.instance.effectiveLocale.languageCode;
    final dateFormat = locale == 'ru' ? 'dd.MM.yyyy' : 'MMM d, yyyy';

    return SettingsGroup(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(
                        text: 'Orpheus ',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(
                        text: versionLabel,
                        style: AppTypography.mono(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ]),
                  ),
                  if (registrationDate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.accountCreated(
                          DateFormat(dateFormat).format(registrationDate!)),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
                onPressed: onCheckUpdates, child: Text(l10n.checkUpdates)),
          ],
        ),
      ),
    ]);
  }
}

class _ExportKeyDialog extends StatelessWidget {
  const _ExportKeyDialog({required this.privateKey});
  final String privateKey;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.privateKey),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.privateKeyWarning,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: AppRadii.md,
              border: Border.all(color: AppColors.danger.withOpacity(0.25)),
            ),
            child: SelectableText(
              privateKey,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: AppTypography.monoFamily,
                    color: AppColors.danger,
                  ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close)),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: privateKey));
            Navigator.pop(context);
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.keyCopied)));
          },
          child: Text(l10n.copy),
        ),
      ],
    );
  }
}

class _PinVerifyDialog extends StatefulWidget {
  const _PinVerifyDialog({required this.title, required this.pinLength});
  final String title;
  final int pinLength;

  @override
  State<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<_PinVerifyDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscure,
        keyboardType: TextInputType.number,
        maxLength: widget.pinLength,
        decoration: InputDecoration(
          hintText: l10n.enterPin,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onChanged: (value) {
          if (value.length == widget.pinLength) {
            Navigator.pop(context, value);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.deleteAccountWarning),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: Text(l10n.deleteAccountConfirm),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel)),
        TextButton(
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}
