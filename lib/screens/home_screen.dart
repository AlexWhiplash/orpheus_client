import 'package:flutter/material.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/rooms_screen.dart';
import 'package:orpheus_project/screens/settings_screen.dart';
import 'package:orpheus_project/screens/status_screen.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _betaDisclaimerDismissedKey = 'beta_disclaimer_dismissed_v1';

  int _currentIndex = 1; // По умолчанию открываем Контакты
  
  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocaleChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeShowBetaDisclaimer();
      if (!mounted) return;
      await _checkDeviceSettings();
    });
  }
  
  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _isBetaDisclaimerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_betaDisclaimerDismissedKey) ?? false;
  }

  Future<void> _setBetaDisclaimerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_betaDisclaimerDismissedKey, true);
  }

  Future<void> _maybeShowBetaDisclaimer() async {
    // Небольшая пауза, чтобы не "рвать" первый кадр.
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final dismissed = await _isBetaDisclaimerDismissed();
    if (dismissed || !mounted) return;

    // Берём язык из виджет-дерева (Localizations), а не из глобального синглтона:
    // в проде MaterialApp.locale резолвится из того же LocaleService.effectiveLocale,
    // так что поведение идентично, но диалог корректно следует за локалью дерева.
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    bool dontShowAgain = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.lg,
            side: BorderSide(color: AppColors.warning.withOpacity(0.25)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.info_outline, color: AppColors.warning, size: 28),
                ),
                const SizedBox(height: 16),
                Text(
                  isRu ? 'Бета-версия' : 'Beta Version',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isRu 
                      ? 'Сейчас приложение проходит закрытое тестирование. '
                        'Возможны непредвиденные сбои и ошибки. '
                        'Мы постоянно работаем над улучшением сервиса.'
                      : 'The app is currently in closed beta testing. '
                        'Unexpected crashes and errors may occur. '
                        'We are constantly working to improve the service.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: dontShowAgain,
                  onChanged: (value) {
                    setState(() {
                      dontShowAgain = value ?? false;
                    });
                  },
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  title: Text(
                    isRu ? 'Больше не показывать' : "Don't show again",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: isRu ? 'Понятно' : 'Got it',
                  onPressed: () async {
                    if (dontShowAgain) {
                      await _setBetaDisclaimerDismissed();
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkDeviceSettings() async {
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    final isDismissed = await DeviceSettingsService.isSetupDialogDismissed();
    if (isDismissed) return;
    
    final needsSetup = await DeviceSettingsService.needsManualSetup();
    if (needsSetup && mounted) {
      DeviceSettingsService.showSetupDialog(context);
    }
  }

  final List<Widget> _screens = [
    const StatusScreen(),
    const ContactsScreen(),
    const RoomsScreen(),
    const SettingsScreen(),
  ];

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: _screens[_currentIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.monitor_heart_outlined),
            selectedIcon: const Icon(Icons.monitor_heart),
            label: l10n.system,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: l10n.contacts,
          ),
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum),
            label: l10n.rooms,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.profile,
          ),
        ],
      ),
    );
  }
}
