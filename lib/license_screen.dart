import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/screens/purchase_screen.dart';
import 'package:orpheus_project/screens/support_chat_screen.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_card.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';

class LicenseScreen extends StatefulWidget {
  final VoidCallback onLicenseConfirmed;
  const LicenseScreen({
    super.key,
    required this.onLicenseConfirmed,
    Stream<String>? debugWsStreamOverride,
  }) : _debugWsStreamOverride = debugWsStreamOverride;

  final Stream<String>? _debugWsStreamOverride;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final TextEditingController _promoController = TextEditingController();
  StreamSubscription? _wsSubscription;

  bool _isActivatingPromo = false;
  String? _promoError;

  @override
  void initState() {
    super.initState();

    final wsStream = widget._debugWsStreamOverride ?? websocketService.stream;
    _wsSubscription = wsStream.listen((message) {
      try {
        final data = json.decode(message);
        if (data['type'] == 'payment-confirmed' ||
            (data['type'] == 'license-status' && data['status'] == 'active')) {
          widget.onLicenseConfirmed();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  void _openPurchase() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseScreen(onConfirmed: widget.onLicenseConfirmed),
      ),
    );
  }

  void _openSupport() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SupportChatScreen()),
    );
  }

  /// Проверка доступности хоста (без переключения). Возвращает латентность в мс
  /// или null, если хост недоступен.
  ///
  /// На бэке НЕТ /health (он отдаёт 404), поэтому бьём лёгкий публичный эндпоинт и
  /// считаем ДОСТУПНОСТЬЮ любой HTTP-ответ: сервер ответил => DNS+TLS+сеть в порядке
  /// (даже 4xx подтверждает, что хост живой). Недоступность = только исключение или
  /// таймаут (не резолвится DNS / нет сети / сервер не отвечает).
  Future<int?> _pingHost(String host) async {
    try {
      final sw = Stopwatch()..start();
      await http
          .get(Uri.parse(
              AppConfig.httpUrl('/api/public/releases?limit=1', host: host)))
          .timeout(const Duration(seconds: 8));
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// Постоянный баннер, когда активен не-прод сервер (чтобы «пустые контакты» на
  /// тестовом сервере не приняли за поломку).
  Widget _testServerBanner(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      width: double.infinity,
      color: AppColors.danger.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Text(
        '${l10n.serverTestBanner}: ${AppConfig.serverIp}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.danger,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 1,
        ),
      ),
    );
  }

  /// Скрытый (long-press по заголовку, только тест-сборки) диалог выбора сервера:
  /// prod / test из фиксированного allowlist, проверка связи, применить, сброс на прод.
  Future<void> _showServerDialog() async {
    final l10n = L10n.of(context);
    String selected = AppConfig.serverIp;
    bool testing = false;
    String? testMsg;
    Color testColor = AppColors.textSecondary;

    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setInner) {
          Widget option(String host, String label) {
            final active = selected == host;
            return InkWell(
              borderRadius: AppRadii.sm,
              onTap: () => setInner(() {
                selected = host;
                testMsg = null;
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.action.withOpacity(0.10)
                      : Colors.transparent,
                  borderRadius: AppRadii.sm,
                  border: Border.all(
                    color: active ? AppColors.action : AppColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: active ? AppColors.action : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: Theme.of(dialogCtx).textTheme.labelLarge),
                          Text(
                            host,
                            style: Theme.of(dialogCtx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.lg,
              side: BorderSide(color: AppColors.outline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.serverSwitchTitle,
                      style: Theme.of(dialogCtx).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    l10n.serverCurrent(AppConfig.serverIp),
                    style: Theme.of(dialogCtx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 16),
                  option(AppConfig.primaryApiHost, l10n.serverProduction),
                  option(AppConfig.testApiHost, l10n.serverTest),
                  if (testMsg != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      testMsg!,
                      style: Theme.of(dialogCtx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: testColor),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AppButton(
                    label: l10n.serverTestConnection,
                    variant: AppButtonVariant.secondary,
                    isLoading: testing,
                    onPressed: testing
                        ? null
                        : () async {
                            setInner(() {
                              testing = true;
                              testMsg = null;
                            });
                            final ms = await _pingHost(selected);
                            setInner(() {
                              testing = false;
                              if (ms != null) {
                                testMsg = l10n.serverConnectionOk(ms);
                                testColor = AppColors.success;
                              } else {
                                testMsg = l10n.serverConnectionFailed;
                                testColor = AppColors.danger;
                              }
                            });
                          },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: l10n.serverResetProd,
                          variant: AppButtonVariant.tertiary,
                          onPressed: () => Navigator.pop(
                              dialogCtx, AppConfig.primaryApiHost),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          label: l10n.serverApply,
                          onPressed: () => Navigator.pop(dialogCtx, selected),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (chosen == null || !mounted) return;
    if (chosen == AppConfig.serverIp) {
      setState(() {});
      return;
    }
    await switchApiServer(chosen);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.serverSwitched(chosen))),
    );
  }

  Future<void> _activatePromo() async {
    final l10n = L10n.of(context);
    final code = _promoController.text.trim();
    if (code.isEmpty) {
      setState(() => _promoError = l10n.enterCodeError);
      return;
    }

    setState(() {
      _isActivatingPromo = true;
      _promoError = null;
    });

    try {
      final myPubkey = cryptoService.publicKeyBase64;
      if (myPubkey == null) throw Exception(l10n.keysNotInitialized);

      final url = Uri.parse(AppConfig.httpUrl('/api/activate-promo'));
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({"pubkey": myPubkey, "code": code}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'ok') {
        if (!mounted) return;
        await AppDialog.show(
          context: context,
          icon: Icons.check_circle,
          iconColor: AppColors.success,
          title: l10n.done,
          content: l10n.licenseActivated,
          primaryLabel: l10n.ok,
        );
        // Активация подтверждена сервером (HTTP ok) — входим в приложение СРАЗУ.
        // Раньше вход ждал пуш license-status: active по WebSocket, но сервер его
        // после activate-promo не шлёт -> лицензия списывалась, а приложение не
        // пускало (device-тест). onLicenseConfirmed идемпотентен (setState+persist).
        if (mounted) widget.onLicenseConfirmed();
      } else {
        setState(() => _promoError = data['message'] ?? l10n.invalidCode);
      }
    } catch (_) {
      setState(() => _promoError = l10n.connectionError);
    } finally {
      if (mounted) setState(() => _isActivatingPromo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AppScaffold(
        safeArea: false,
        appBar: AppBar(
          // Тест-сборки: long-press по заголовку открывает выбор сервера (prod/test).
          // В релизе (debugFileLogging=false) — обычный текст, переключатель недоступен.
          title: AppConfig.debugFileLogging
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: _showServerDialog,
                  child: Text(l10n.activation),
                )
              : Text(l10n.activation),
          // «Назад» показываем ТОЛЬКО если есть куда возвращаться. Как стартовый
          // гейт лицензии экран — корневой, под ним пусто: pop увёл бы в пустой
          // Navigator → чёрный мёртвый экран. canPop=false → кнопки нет.
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
        ),
        body: Column(
          children: [
            if (AppConfig.isTestHost) _testServerBanner(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
              Text(l10n.enterCode,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                l10n.activationCodeHint,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              AppButton(
                label: l10n.buyLicense,
                icon: Icons.workspace_premium,
                onPressed: _openPurchase,
              ),
              const SizedBox(height: 16),
              AppCard(
                radius: AppRadii.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.activationCode,
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _promoController,
                      hintText: 'XXXX-XXXX-XXXX',
                      prefixIcon: Icons.key,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.visiblePassword,
                      onSubmitted: (_) => _activatePromo(),
                    ),
                    if (_promoError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _promoError!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 14),
                    AppButton(
                      label: _isActivatingPromo ? l10n.checking : l10n.activateButton,
                      icon: Icons.check_circle_outline,
                      onPressed: _isActivatingPromo ? null : _activatePromo,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                radius: AppRadii.lg,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: AppRadii.sm,
                      ),
                      child: const Icon(Icons.info_outline,
                          color: AppColors.success),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.format,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: AppColors.success)),
                          const SizedBox(height: 4),
                          Text(
                            l10n.codeFormat,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.codeNotAccepted,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: 4),
              AppButton(
                label: l10n.support,
                icon: Icons.support_agent,
                variant: AppButtonVariant.tertiary,
                onPressed: _openSupport,
              ),
            ],
          ),
        ),
            ),
          ],
        ),
      ),
    );
  }
}
