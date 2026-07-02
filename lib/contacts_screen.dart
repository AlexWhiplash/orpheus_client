import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/qr_scan_screen.dart';
import 'package:orpheus_project/screens/ai_assistant_chat_screen.dart';
import 'package:orpheus_project/services/badge_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_shimmer.dart';
import 'package:orpheus_project/widgets/app_states.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class ContactsScreen extends StatefulWidget {
  /// В тестах можно отключить async-запросы счётчиков, чтобы не зависеть от SQLite/таймеров.
  final bool enableUnreadCounters;

  const ContactsScreen({super.key, this.enableUnreadCounters = true});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late Future<({List<Contact> contacts, Map<String, int> unreadCounts})>
      _modelFuture;
  StreamSubscription? _updateSubscription;
  Timer? _updateCheckTimer;
  Timer? _refreshDebounce;

  // Поиск по контактам (фильтр по имени в памяти — аудит PROD-3).
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _modelFuture = _loadModel();
    // Debounce: при пачке входящих (напр. бэклог на реконнекте) не пере-агрегируем
    // всю таблицу и не перерисовываем список на каждое сообщение (аудит PERF-3).
    _updateSubscription =
        messageUpdateController.stream.listen((_) => _scheduleRefresh());

    // В тестах не запускаем фоновые проверки обновлений (иначе появятся таймеры/сетевые запросы).
    if (!const bool.fromEnvironment('FLUTTER_TEST')) {
      _updateCheckTimer?.cancel();
      _updateCheckTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        UpdateService.checkForUpdate(context);
      });
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _refreshDebounce?.cancel();
    _updateSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  /// Коалесцируем частые события обновления (входящие сообщения) в один refresh.
  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), _refreshContacts);
  }

  void _refreshContacts() {
    if (!mounted) return;
    setState(() {
      _modelFuture = _loadModel();
    });
  }

  Future<({List<Contact> contacts, Map<String, int> unreadCounts})>
      _loadModel() async {
    final contacts = await DatabaseService.instance.getContacts();

    // Presence: подписываемся на статусы всех контактов (diff внутри сервиса).
    presenceService.setWatchedPubkeys(contacts.map((c) => c.publicKey));

    // Предзагрузка бейджей для всех контактов (в фоне, не блокируем UI)
    BadgeService.instance
        .preloadBadges(contacts.map((c) => c.publicKey).toList());

    final Map<String, int> unreadCounts;
    if (!widget.enableUnreadCounters) {
      unreadCounts = const <String, int>{};
    } else {
      unreadCounts = await DatabaseService.instance.getUnreadCountsForContacts(
        contacts.map((c) => c.publicKey).toList(),
      );
    }

    return (contacts: contacts, unreadCounts: unreadCounts);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        title: Text(l10n.contactsTitle),
        actions: [
          AppIconButton(
            icon: _isSearching ? Icons.search_off : Icons.search,
            tooltip: l10n.searchContactsHint,
            onPressed: _toggleSearch,
          ),
          AppIconButton(
            icon: Icons.person_add_outlined,
            tooltip: l10n.addContact,
            onPressed: _showAddContactDialog,
          ),
          AppIconButton(
            icon: Icons.qr_code_scanner,
            tooltip: l10n.scanQrTooltip,
            onPressed: () async {
              final scannedKey = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QrScanScreen()),
              );
              if (scannedKey != null) {
                _showAddContactDialogWithKey(scannedKey);
              }
            },
          ),
          AppIconButton(
            icon: Icons.refresh,
            tooltip: l10n.refreshTooltip,
            onPressed: _refreshContacts,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearching) _buildSearchField(l10n),
          Expanded(
            child: FutureBuilder<
          ({List<Contact> contacts, Map<String, int> unreadCounts})>(
        future: _modelFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ContactsListSkeleton();
          }

          if (snapshot.hasError) {
            return ErrorState(
              title: l10n.loadingError,
              message: snapshot.error.toString(),
              onRetry: _refreshContacts,
            );
          }

          final data = snapshot.data ??
              (contacts: <Contact>[], unreadCounts: const <String, int>{});
          final contacts = data.contacts;
          final unreadCounts = data.unreadCounts;

          // Показываем Оракула даже если контактов нет
          return StreamBuilder<Map<String, bool>>(
            stream: presenceService.stream,
            initialData: const <String, bool>{},
            builder: (context, presenceSnapshot) {
              final presence = presenceSnapshot.data ?? const <String, bool>{};
              return _buildContactsList(
                contacts: contacts,
                presence: presence,
                unreadCounts: unreadCounts,
                showEmptyHint: contacts.isEmpty,
              );
            },
          );
        },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(L10n l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: l10n.searchContactsHint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildContactsList({
    required List<Contact> contacts,
    required Map<String, bool> presence,
    required Map<String, int> unreadCounts,
    bool showEmptyHint = false,
  }) {
    final l10n = L10n.of(context);

    // Фильтр по имени в памяти (аудит PROD-3). При активном поиске прячем
    // Оракула и пустую подсказку — показываем только результаты.
    final query = _searchQuery.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final visible = searching
        ? contacts
            .where((c) => c.name.toLowerCase().contains(query))
            .toList()
        : contacts;

    if (searching && visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            l10n.noContactsFound,
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final showOracle = !searching;
    final showHint = showEmptyHint && !searching;
    final leading = (showOracle ? 1 : 0) + (showHint ? 1 : 0);
    final itemCount = visible.length + leading;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Первый элемент — Оракул Орфея (AI контакт), кроме режима поиска.
        if (showOracle && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _OracleContactRow(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AiAssistantChatScreen(),
                  ),
                );
              },
            ),
          );
        }

        // Подсказка для добавления контактов (если список пуст)
        if (showHint && index == (showOracle ? 1 : 0)) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 8),
            child: _AddContactHint(
              onTap: _showAddContactDialog,
            ),
          );
        }

        // Обычные контакты (со смещением индекса)
        final contactIndex = index - leading;
        if (contactIndex < 0 || contactIndex >= visible.length) {
          return const SizedBox.shrink();
        }

        final c = visible[contactIndex];
        final isOnline = presence[c.publicKey] == true;
        final unread = unreadCounts[c.publicKey] ?? 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ContactRow(
            contact: c,
            isOnline: isOnline,
            unreadCount: unread,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatScreen(contact: c)),
              );
              _refreshContacts();
            },
            onLongPress: () => _showContactActionsSheet(c),
          ),
        );
      },
    );
  }

  void _showAddContactDialog() {
    _showAddContactDialogWithKey(null);
  }

  void _showAddContactDialogWithKey(String? initialKey) {
    final nameController = TextEditingController();
    final keyController = TextEditingController(text: initialKey);

    showDialog(
      context: context,
      builder: (context) => _AddContactDialog(
        nameController: nameController,
        keyController: keyController,
        onAdd: () async {
          // Валидация (пустые поля / формат ключа) — в самом диалоге.
          HapticFeedback.selectionClick();
          final newContact = Contact(
            name: nameController.text.trim(),
            publicKey: keyController.text.trim(),
          );
          await DatabaseService.instance.addContact(newContact);
          if (!context.mounted) return;
          Navigator.pop(context);
          _refreshContacts();
        },
        onScanQR: () async {
          final scannedKey = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const QrScanScreen()),
          );
          if (scannedKey != null) {
            keyController.text = scannedKey;
          }
        },
      ),
    );
  }

  void _showContactActionsSheet(Contact contact) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ContactActionsSheet(
        contact: contact,
        onRename: () {
          Navigator.pop(context);
          _showRenameContactDialog(contact);
        },
        onDelete: () {
          Navigator.pop(context);
          _showDeleteContactDialog(contact);
        },
      ),
    );
  }

  void _showRenameContactDialog(Contact contact) async {
    final l10n = L10n.of(context);
    final newName = await AppInputDialog.show(
      context: context,
      icon: Icons.edit,
      title: l10n.renameContact,
      hintText: l10n.enterNewName,
      initialValue: contact.name,
      prefixIcon: Icons.person_outline,
      primaryLabel: l10n.save,
      secondaryLabel: l10n.cancel,
    );

    if (!mounted) return;
    if (newName != null && newName.isNotEmpty && newName != contact.name) {
      HapticFeedback.selectionClick();
      await DatabaseService.instance.updateContactName(contact.id!, newName);
      if (!mounted) return;
      _refreshContacts();
    }
  }

  void _showDeleteContactDialog(Contact contact) {
    showDialog(
      context: context,
      builder: (context) => _DeleteContactDialog(
        contactName: contact.name,
        onDelete: () async {
          HapticFeedback.lightImpact();
          await DatabaseService.instance
              .deleteContact(contact.id!, contact.publicKey);
          if (!context.mounted) return;
          Navigator.pop(context);
          _refreshContacts();
        },
      ),
    );
  }
}

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
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
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
                  color: Colors.white,
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
              color: Colors.black,
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

  /// Публичный ключ — base64 от 32 байт (X25519). Отсекаем мусор/опечатки,
  /// чтобы не создавать «битый» контакт, которому нельзя написать (аудит UI-7).
  bool _isValidPublicKey(String key) {
    try {
      return base64.decode(base64.normalize(key)).length == 32;
    } catch (_) {
      return false;
    }
  }

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
                            color: Colors.white,
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
                                    fontFamily: 'monospace',
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

class _OracleContactRowState extends State<_OracleContactRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: AppRadii.md,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                // Градиентный фон
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.action.withOpacity(0.08 + 0.04 * _glowAnimation.value),
                    AppColors.surface,
                    const Color(0xFF1A2530).withOpacity(0.95),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
                borderRadius: AppRadii.md,
                border: Border.all(
                  color: AppColors.action.withOpacity(0.25 + 0.15 * _glowAnimation.value),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.action.withOpacity(0.15 * _glowAnimation.value),
                    blurRadius: 20 * _glowAnimation.value,
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Анимированный AI аватар
                  _OracleAvatar(animation: _glowAnimation),
                  const SizedBox(width: 14),
                  // Информация
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Имя Оракула
                            Flexible(
                              child: Text(
                                l10n.aiAssistantName,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // AI Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.action.withOpacity(0.9),
                                    AppColors.actionDark,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.action.withOpacity(0.3 * _glowAnimation.value),
                                    blurRadius: 6,
                                    spreadRadius: -1,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 10,
                                    color: Colors.black.withOpacity(0.8),
                                  ),
                                  const SizedBox(width: 3),
                                  const Text(
                                    'AI',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
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
                            // Пульсирующая точка
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.success,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.success.withOpacity(0.5 * _glowAnimation.value),
                                    blurRadius: 6 * _glowAnimation.value,
                                    spreadRadius: 1 * _glowAnimation.value,
                                  ),
                                ],
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
                  // Стрелка с эффектом
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.action.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.action.withOpacity(0.6 + 0.4 * _glowAnimation.value),
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Анимированный аватар Оракула.
class _OracleAvatar extends StatelessWidget {
  const _OracleAvatar({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.action.withOpacity(0.7 + 0.3 * animation.value),
            AppColors.actionDark,
            const Color(0xFF2E7D4F),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.action.withOpacity(0.35 * animation.value),
            blurRadius: 14 * animation.value,
            spreadRadius: 1,
          ),
        ],
        border: Border.all(
          color: AppColors.actionLight.withOpacity(0.4 + 0.2 * animation.value),
          width: 1.5,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Иконка мозга/AI
          Icon(
            Icons.psychology,
            color: Colors.white.withOpacity(0.95),
            size: 28,
          ),
          // Искры сверху-справа
          Positioned(
            top: 4,
            right: 4,
            child: Icon(
              Icons.auto_awesome,
              color: Colors.white.withOpacity(0.6 + 0.4 * animation.value),
              size: 12,
            ),
          ),
        ],
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
