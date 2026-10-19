import 'package:flutter/material.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';

/// Виджет выбора языка (используется на Welcome Screen и в Settings)
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    super.key,
    this.compact = false,
    this.onChanged,
  });
  
  /// Компактный режим (только иконка/код языка)
  final bool compact;
  
  /// Callback при смене языка
  final VoidCallback? onChanged;

  /// Открыть выбор языка из своей строки настроек (сгруппированный список профиля).
  static Future<void> showPicker(BuildContext context, {VoidCallback? onChanged}) =>
      LanguageSelector(onChanged: onChanged)
          ._showLanguageDialog(context, L10n.of(context));

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final currentLocale = LocaleService.instance.effectiveLocale;
    
    if (compact) {
      return _CompactButton(
        currentLocale: currentLocale,
        onTap: () => _showLanguageDialog(context, l10n),
      );
    }
    
    return _FullButton(
      currentLocale: currentLocale,
      l10n: l10n,
      onTap: () => _showLanguageDialog(context, l10n),
    );
  }
  
  Future<void> _showLanguageDialog(BuildContext context, L10n l10n) async {
    final selected = await showModalBottomSheet<Locale?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _LanguageBottomSheet(l10n: l10n),
    );
    
    if (selected != null || selected == null) {
      // selected == null && был выбран — значит выбрана системная
      // Но нам нужно проверить, был ли вообще сделан выбор
    }
    
    onChanged?.call();
  }
}

class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.currentLocale,
    required this.onTap,
  });
  
  final Locale currentLocale;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withOpacity(0.8),
      borderRadius: AppRadii.sm,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.sm,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: AppRadii.sm,
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                currentLocale.languageCode.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullButton extends StatelessWidget {
  const _FullButton({
    required this.currentLocale,
    required this.l10n,
    required this.onTap,
  });
  
  final Locale currentLocale;
  final L10n l10n;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    final isSystem = LocaleService.instance.isSystemLocale;
    final displayName = isSystem 
        ? l10n.systemDefault
        : LocaleService.getLanguageName(currentLocale);
    
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.10),
          borderRadius: AppRadii.sm,
        ),
        child: const Icon(Icons.language, color: AppColors.accent, size: 20),
      ),
      title: Text(
        l10n.language,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(displayName),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
    );
  }
}

class _LanguageBottomSheet extends StatefulWidget {
  const _LanguageBottomSheet({required this.l10n});
  
  final L10n l10n;
  
  @override
  State<_LanguageBottomSheet> createState() => _LanguageBottomSheetState();
}

class _LanguageBottomSheetState extends State<_LanguageBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final currentSelected = LocaleService.instance.selectedLocale;
    
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              widget.l10n.selectLanguage,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Системный язык
          _LanguageOption(
            title: widget.l10n.systemDefault,
            subtitle: 'Auto',
            isSelected: currentSelected == null,
            onTap: () => _selectLocale(null),
          ),
          
          const Divider(height: 1, indent: 56),
          
          // English
          _LanguageOption(
            title: widget.l10n.english,
            subtitle: 'English',
            isSelected: currentSelected?.languageCode == 'en',
            onTap: () => _selectLocale(const Locale('en')),
          ),
          
          const Divider(height: 1, indent: 56),
          
          // Русский
          _LanguageOption(
            title: widget.l10n.russian,
            subtitle: 'Русский',
            isSelected: currentSelected?.languageCode == 'ru',
            onTap: () => _selectLocale(const Locale('ru')),
          ),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }
  
  Future<void> _selectLocale(Locale? locale) async {
    await LocaleService.instance.setLocale(locale);
    if (mounted) {
      Navigator.pop(context, locale);
    }
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });
  
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.outline,
            width: 2,
          ),
          color: isSelected ? AppColors.accent : Colors.transparent,
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 14, color: Colors.black)
            : null,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: title != subtitle ? Text(subtitle) : null,
    );
  }
}
