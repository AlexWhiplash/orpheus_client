import 'dart:async';

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
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_shimmer.dart';
import 'package:orpheus_project/widgets/app_states.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

part 'contacts_screen_widgets.dart';

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
  StreamSubscription? _wsStatusSubscription;
  bool _authFailedNotified = false;
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

      // AuthFailed = сервер стабильно отвергает PoP. Самая вероятная причина —
      // устаревшая версия приложения: показываем баннер и проверяем обновления.
      _wsStatusSubscription = websocketService.status.listen((status) {
        if (!mounted) return;
        if (status == ConnectionStatus.AuthFailed && !_authFailedNotified) {
          _authFailedNotified = true;
          _showAuthFailedBanner();
        } else if (status == ConnectionStatus.Connected) {
          _authFailedNotified = false; // вылечилось — при рецидиве покажем снова
        }
      });
    }
  }

  void _showAuthFailedBanner() {
    final l10n = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.authFailedBanner),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: l10n.checkUpdates,
        onPressed: () {
          if (!mounted) return;
          UpdateService.checkForUpdate(context, showNoUpdateFeedback: true);
        },
      ),
    ));
    UpdateService.checkForUpdate(context);
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _refreshDebounce?.cancel();
    _updateSubscription?.cancel();
    _wsStatusSubscription?.cancel();
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

