import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/identity_directory_service.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_card.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';
import 'package:orpheus_project/widgets/language_selector.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onAuthComplete;
  const WelcomeScreen({super.key, required this.onAuthComplete});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  final _importController = TextEditingController();

  Timer? _revealTimer;
  late final AnimationController _introController;
  late final AnimationController _haloController;
  bool _animationsStarted = false;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _buttonsOpacity;
  late final Animation<Offset> _buttonsSlide;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );

    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );

    _logoOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _titleOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.20, 0.80, curve: Curves.easeOut),
    );
    _titleSlide =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.20, 0.80, curve: Curves.easeOutCubic),
      ),
    );
    _buttonsOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );
    _buttonsSlide =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    
    // Слушаем изменения локали
    LocaleService.instance.addListener(_onLocaleChanged);

    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _introController.forward();
    });
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationsStarted) return;
    _animationsStarted = true;

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (!disableAnimations) {
      _haloController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _importController.dispose();
    _introController.dispose();
    _haloController.dispose();
    LocaleService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  bool _isCreating = false;

  Future<void> _createNewAccount() async {
    // Guard от двойного тапа: иначе повторный вызов перегенерировал бы ключи
    // поверх только что созданных (аудит UI-5).
    if (_isCreating) return;
    HapticFeedback.mediumImpact();
    setState(() => _isCreating = true);
    try {
      await cryptoService.generateNewKeys();
      // Публикуем подписанную связку адрес<->enc в directory (best-effort),
      // чтобы контакты могли зарезолвить наш enc-ключ.
      IdentityDirectoryService.instance.publishSelf();
      widget.onAuthComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${L10n.of(context).error}: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _importAccount(String key) async {
    HapticFeedback.lightImpact();
    await cryptoService.importPrivateKey(key);
    IdentityDirectoryService.instance.publishSelf();
    widget.onAuthComplete();
  }

  void _showImportDialog() {
    final l10n = L10n.of(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        return _ImportKeyDialog(
          controller: _importController,
          l10n: l10n,
          onImport: () async {
            // Capture value synchronously before any async work —
            // the controller may be disposed if parent navigates away.
            final key = _importController.text.trim();
            if (key.isEmpty) return;
            try {
              Navigator.pop(context);
              await _importAccount(key);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${l10n.error}: $e'),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l10n = L10n.of(context);
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bg,
                    AppColors.bg.withOpacity(0.94),
                    const Color(0xFF06070A),
                  ],
                ),
              ),
            ),
          ),

          // Дышащий нимб у логотипа
          if (!disableAnimations)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _haloController,
                      builder: (context, _) {
                        final v =
                            Curves.easeInOut.transform(_haloController.value);
                        return Container(
                          width: 320 + 26 * v,
                          height: 320 + 26 * v,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.accent.withOpacity(0.10 + 0.05 * v),
                                AppColors.info.withOpacity(0.06 + 0.04 * v),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

          // Кнопка выбора языка в правом верхнем углу
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: LanguageSelector(
                  compact: true,
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _introController,
                    builder: (context, _) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withOpacity(0.72),
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(28)),
                              border: Border.all(
                                  color: AppColors.outline.withOpacity(0.85)),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withOpacity(0.12),
                                  blurRadius: 26,
                                  spreadRadius: -12,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(20)),
                              child: Image.asset(
                                'assets/images/logo_mark.png',
                                height: 88,
                                width: 88,
                                fit: BoxFit.contain,
                                errorBuilder: (c, e, s) {
                                  return Container(
                                    width: 88,
                                    height: 88,
                                    color: AppColors.surface2,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.shield,
                                        size: 44, color: AppColors.accent),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _introController,
                    builder: (context, _) {
                      return SlideTransition(
                        position: _titleSlide,
                        child: Opacity(
                          opacity: _titleOpacity.value,
                          child: Column(
                            children: [
                              Text(
                                l10n.appName,
                                style: t.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.welcomeSubtitle,
                                style: t.bodyMedium
                                    ?.copyWith(color: AppColors.textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _introController,
                    builder: (context, _) {
                      return SlideTransition(
                        position: _buttonsSlide,
                        child: Opacity(
                          opacity: _buttonsOpacity.value,
                          child: Column(
                            children: [
                              AppButton(
                                label: l10n.createAccount,
                                icon: Icons.add_circle_outline,
                                isLoading: _isCreating,
                                onPressed: _isCreating ? null : _createNewAccount,
                              ),
                              const SizedBox(height: 10),
                              AppButton(
                                label: l10n.restoreFromKey,
                                variant: AppButtonVariant.secondary,
                                icon: Icons.key,
                                onPressed: _isCreating ? null : _showImportDialog,
                              ),
                              const SizedBox(height: 16),
                              AppCard(
                                radius: AppRadii.lg,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.success.withOpacity(0.12),
                                        borderRadius: AppRadii.sm,
                                        border: Border.all(
                                            color: AppColors.success
                                                .withOpacity(0.22)),
                                      ),
                                      child: const Icon(Icons.lock_outline,
                                          color: AppColors.success, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        l10n.e2eEncryption,
                                        style: t.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportKeyDialog extends StatelessWidget {
  const _ImportKeyDialog({
    required this.controller,
    required this.l10n,
    required this.onImport,
  });

  final TextEditingController controller;
  final L10n l10n;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lg,
        side: BorderSide(color: AppColors.outline),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: AppRadii.sm,
                    ),
                    child: const Icon(Icons.key, color: AppColors.warning, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.recovery,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.recoveryWarning,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: controller,
                hintText: l10n.pastePrivateKey,
                prefixIcon: Icons.vpn_key_outlined,
                maxLines: 4,
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: l10n.cancel,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: l10n.import,
                    onPressed: onImport,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
