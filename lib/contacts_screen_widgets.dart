part of 'contacts_screen.dart';

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.isOnline,
    required this.unreadCount,
    required this.onTap,
    required this.onLongPress,
  });

  final Contact contact;
  final bool isOnline;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Компактная метка времени последнего сообщения для строки контакта.
  /// Только время/дата — без текста сообщения (приватность: содержимое не
  /// показываем на главном экране; уведомления тоже скрывают контент). PROD-4.
  static String _formatLastTime(int? ms, String locale) {
    if (ms == null || ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) return DateFormat.Hm(locale).format(dt); // 14:32
    if (dt.year == now.year) return DateFormat.MMMd(locale).format(dt); // 12 июн.
    return DateFormat('dd.MM.yyyy', locale).format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    final subtitle = _formatLastTime(
      contact.lastMessageTime,
      Localizations.localeOf(context).languageCode,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppRadii.md,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.md,
            border: Border.all(
                color: hasUnread
                    ? AppColors.accent.withOpacity(0.22)
                    : AppColors.outline),
          ),
          child: Row(
            children: [
              _Avatar(
                name: contact.name,
                isOnline: isOnline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.name,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: hasUnread
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        UserBadge(pubkey: contact.publicKey, compact: true),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTypography.mono(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (hasUnread)
                _UnreadPill(count: unreadCount)
              else
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.isOnline,
  });

  final String name;
  final bool isOnline;

  String get letter => name.isNotEmpty ? name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppAvatarColors.gradientFromName(name);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(color: AppColors.outline),
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.bg,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog({
    required this.nameController,
    required this.keyController,
    required this.onAdd,
    required this.onScanQR,
  });

  final TextEditingController nameController;
  final TextEditingController keyController;
  final Future<void> Function() onAdd;
  final VoidCallback onScanQR;

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  bool _isSaving = false;
  String? _error;

  /// Сетевой адрес контакта — Ed25519 pub в base64url без padding (см.
  /// CryptoService.isValidAddress). Отсекаем мусор/опечатки и СТАРЫЙ X25519-ключ
  /// (стандартный base64), чтобы не создавать «битый» контакт, которому нельзя
  /// писать/звонить: роутинг и строгий mutual-add работают именно по адресу (аудит UI-7).
  bool _isValidPublicKey(String key) => CryptoService.isValidAddress(key);

  Future<void> _submit(L10n l10n) async {
    final name = widget.nameController.text.trim();
    final key = widget.keyController.text.trim();
    if (name.isEmpty || key.isEmpty) {
      setState(() => _error = l10n.fillAllFields);
      return;
    }
    if (!_isValidPublicKey(key)) {
      setState(() => _error = l10n.invalidPublicKey);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.onAdd(); // родитель сохраняет контакт и закрывает диалог
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = '${l10n.error}: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lg,
          side: BorderSide(color: AppColors.outline)),
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
                    color: AppColors.accent.withOpacity(0.10),
                    borderRadius: AppRadii.sm,
                  ),
                  child: const Icon(Icons.person_add,
                      color: AppColors.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Text(l10n.newContact,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 18),
            Text(l10n.contactName, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            AppTextField(
              controller: widget.nameController,
              hintText: l10n.enterName,
              prefixIcon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            Text(l10n.publicKey,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            AppTextField(
              controller: widget.keyController,
              hintText: l10n.pasteOrScanKey,
              prefixIcon: Icons.key,
              maxLines: 2,
              suffixIcon: IconButton(
                icon:
                    const Icon(Icons.qr_code_scanner, color: AppColors.accent),
                onPressed: _isSaving ? null : widget.onScanQR,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: l10n.cancel,
                    variant: AppButtonVariant.secondary,
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: l10n.add,
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : () => _submit(l10n),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactActionsSheet extends StatelessWidget {
  const _ContactActionsSheet({
    required this.contact,
    required this.onRename,
    required this.onDelete,
  });

  final Contact contact;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Индикатор
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Заголовок с именем контакта
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppAvatarColors.gradientFromName(contact.name),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      contact.name.isNotEmpty
                          ? contact.name[0].toUpperCase()
                          : '?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '…${contact.publicKey.substring(contact.publicKey.length - 8)}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.textTertiary,
                                    fontFamily: AppTypography.monoFamily,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            // Действия
            Builder(
              builder: (context) {
                final l10n = L10n.of(context);
                return Column(
                  children: [
                    _ActionTile(
                      icon: Icons.edit_outlined,
                      label: l10n.rename,
                      onTap: onRename,
                    ),
                    _ActionTile(
                      icon: Icons.delete_outline,
                      label: l10n.delete,
                      color: AppColors.danger,
                      onTap: onDelete,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: effectiveColor, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: effectiveColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteContactDialog extends StatelessWidget {
  const _DeleteContactDialog(
      {required this.contactName, required this.onDelete});

  final String contactName;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lg,
        side: BorderSide(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever,
                  color: AppColors.danger, size: 28),
            ),
            const SizedBox(height: 16),
            Text(l10n.deleteContactFull(contactName),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              l10n.deleteContactFullWarning,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
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
                    label: l10n.delete,
                    variant: AppButtonVariant.danger,
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ORACLE CONTACT ROW — ВАУ-контакт Оракула Орфея (AI)
// ══════════════════════════════════════════════════════════════════════════════

class _OracleContactRow extends StatefulWidget {
  const _OracleContactRow({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_OracleContactRow> createState() => _OracleContactRowState();
}

class _OracleContactRowState extends State<_OracleContactRow> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: AppRadii.md,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: AppRadii.md,
            border: Border.all(color: AppColors.outline),
            boxShadow: AppShadows.bevel(),
          ),
          child: Row(
            children: [
              const _OracleAvatar(),
              const SizedBox(width: 14),
              // Информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Имя Оракула: FittedBox(scaleDown) — при крупном
                        // системном шрифте «Оракул Орфея» ужимается, а не режется в «...».
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.aiAssistantName,
                              maxLines: 1,
                              softWrap: false,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // AI Badge — стальная табличка
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                size: 10,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'AI',
                                style: AppTypography.mono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Статус "Всегда онлайн"
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.aiAssistantOnline,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textTertiary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Аватар Оракула: стальная плитка с серебряной иконкой.
class _OracleAvatar extends StatelessWidget {
  const _OracleAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.outline),
      ),
      child: const Icon(
        Icons.psychology,
        color: AppColors.primary,
        size: 28,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADD CONTACT HINT — Подсказка для добавления первого контакта
// ══════════════════════════════════════════════════════════════════════════════

class _AddContactHint extends StatelessWidget {
  const _AddContactHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.md,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.md,
            border: Border.all(
              color: AppColors.outline,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.outline),
                ),
                child: const Icon(
                  Icons.person_add_outlined,
                  color: AppColors.textTertiary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.noContacts,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.addFirstContact,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.action,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.add_circle_outline,
                color: AppColors.action.withOpacity(0.7),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
