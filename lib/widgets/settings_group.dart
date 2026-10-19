import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Сгруппированные списки настроек (визуальная система Orpheus v1).
///
/// Группа — поверхность с радиусом 14 без свечения, строки разделены тонкой линией.
/// Строка: иконка 22dp (textSecondary), подпись, справа значение моноширинным
/// textTertiary, переключатель или шеврон.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: 52,
          color: AppColors.divider,
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.sm,
      ),
      clipBehavior: Clip.antiAlias,
      // Material-предок для ripple строк: без него InkWell рисует под фоном группы.
      child: Material(
        type: MaterialType.transparency,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

/// Подпись над группой: моноширинный, разрядка, textTertiary.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: AppTypography.mono(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color ?? AppColors.textTertiary,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
    this.tone,
    this.labelColor,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;

  /// Значение справа (моноширинный textTertiary), например «6 цифр» или «1.1.9».
  final String? value;
  final Color? valueColor;

  /// Свой виджет справа (переключатель, выпадающий список). Заменяет шеврон.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Цвет иконки для предупреждений/опасных действий (warning / danger).
  final Color? tone;
  final Color? labelColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 22, color: tone ?? AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: labelColor ?? AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 10),
            Text(
              value!,
              style: AppTypography.mono(
                fontSize: 12.5,
                color: valueColor ?? AppColors.textTertiary,
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (onTap != null && showChevron) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// Пояснение под/в группе: тихая строка с иконкой. [color] — warning/danger/info.
class SettingsNote extends StatelessWidget {
  const SettingsNote({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.textTertiary,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color == AppColors.textTertiary
                    ? AppColors.textSecondary
                    : color.withOpacity(0.9),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
