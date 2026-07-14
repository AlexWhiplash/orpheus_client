import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/models/note_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/identity_directory_service.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_text_field.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  List<ChatMessage> _chatHistory = const <ChatMessage>[];
  StreamSubscription<String>? _messageUpdateSubscription;

  // Пагинация истории (аудит PERF-1): грузим только последнюю страницу, старые
  // сообщения подгружаем по скроллу вверх. Список reverse=true, поэтому "верх"
  // (старое) соответствует maxScrollExtent.
  static const int _pageSize = 50;
  bool _hasMoreOlder = false;
  bool _isLoadingOlder = false;

  late final AnimationController _encryptionController;
  bool _isEncrypting = false;

  // Для отслеживания уже показанных сообщений (анимация появления только один раз)
  final Set<int> _animatedMessageIds = <int>{};

  // Multi-select mode
  final Set<int> _selectedTimestamps = <int>{};
  bool get _isSelectionMode => _selectedTimestamps.isNotEmpty;

  @override
  void initState() {
    super.initState();

    // Presence: гарантируем, что собеседник находится в watched-наборе.
    presenceService.addWatchedPubkeys([widget.contact.publicKey]);

    _encryptionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _loadChatHistory();
    _markAsRead();
    _scrollController.addListener(_onScroll);

    _messageUpdateSubscription =
        messageUpdateController.stream.listen((senderKey) {
      if (senderKey == widget.contact.publicKey) {
        // Дописываем только НОВЫЕ сообщения, а не перечитываем всю историю
        // на каждое входящее (аудит PERF-1).
        _appendNewMessages();
        _markAsRead();
      }
    });
  }

  /// Инкрементально дописывает сообщения новее последнего известного, без
  /// перезапроса всей переписки. Дедуп по messageId на случай пересечений.
  Future<void> _appendNewMessages() async {
    final lastMs = _chatHistory.isEmpty
        ? 0
        : _chatHistory.last.timestamp.millisecondsSinceEpoch;
    final newer = await DatabaseService.instance
        .getMessagesForContactAfter(widget.contact.publicKey, lastMs);
    if (!mounted || newer.isEmpty) return;
    final existingIds =
        _chatHistory.map((m) => m.messageId).whereType<String>().toSet();
    final toAdd = newer
        .where((m) => m.messageId == null || !existingIds.contains(m.messageId))
        .toList();
    if (toAdd.isEmpty) return;
    setState(() => _chatHistory = [..._chatHistory, ...toAdd]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0.0);
    });
  }

  @override
  void dispose() {
    _messageUpdateSubscription?.cancel();
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _encryptionController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    // Грузим последнюю страницу, а не всю историю (аудит PERF-1).
    final history = await DatabaseService.instance
        .getMessagesForContactLatest(widget.contact.publicKey, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _chatHistory = history;
      _hasMoreOlder = history.length >= _pageSize;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // reverse=true: старые сообщения — у maxScrollExtent (визуально сверху).
    if (pos.pixels >= pos.maxScrollExtent - 300 &&
        _hasMoreOlder &&
        !_isLoadingOlder) {
      _loadOlder();
    }
  }

  /// Подгружает предыдущую страницу истории (старые сообщения). При reverse=true
  /// prepend скролл-стабилен — контент добавляется у дальнего края, вид не прыгает.
  Future<void> _loadOlder() async {
    if (_isLoadingOlder || !_hasMoreOlder || _chatHistory.isEmpty) return;
    _isLoadingOlder = true;
    final oldestMs = _chatHistory.first.timestamp.millisecondsSinceEpoch;
    final older = await DatabaseService.instance.getMessagesForContactBefore(
        widget.contact.publicKey, oldestMs,
        limit: _pageSize);
    if (!mounted) {
      _isLoadingOlder = false;
      return;
    }
    final existingIds =
        _chatHistory.map((m) => m.messageId).whereType<String>().toSet();
    final toPrepend = older
        .where((m) => m.messageId == null || !existingIds.contains(m.messageId))
        .toList();
    setState(() {
      if (toPrepend.isNotEmpty) {
        _chatHistory = [...toPrepend, ..._chatHistory];
      }
      _hasMoreOlder = older.length >= _pageSize;
      _isLoadingOlder = false;
    });
  }

  Future<void> _markAsRead() async {
    await DatabaseService.instance.markMessagesAsRead(widget.contact.publicKey);
    // Nudge the home tab badge to recompute (a separate signal from
    // messageUpdateController so this listener doesn't re-trigger itself).
    badgeRefreshController.add(null);
  }

  /// Иконка статуса исходящего сообщения. Раньше всегда показывалась двойная
  /// галка «доставлено», даже для неотправленных/упавших сообщений (аудит
  /// LOGIC-3). Теперь отражает реальный статус. Двойная галка (delivered/read)
  /// пока не используется — сервер это релей без квитанций о доставке.
  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.schedule, size: 14, color: AppColors.textTertiary);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: AppColors.danger);
      case MessageStatus.delivered:
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 14, color: AppColors.info.withOpacity(0.85));
      case MessageStatus.sent:
        return Icon(Icons.done, size: 14, color: AppColors.info.withOpacity(0.85));
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    HapticFeedback.selectionClick();
    setState(() => _isEncrypting = true);
    _encryptionController.reset();
    _encryptionController.forward();

    // Стабильный id: одинаков у нашей копии и у копии получателя →
    // корректный дедуп и «удалить у обоих» (аудит LOGIC-1/LOGIC-2).
    final messageId = const Uuid().v4();
    final sentMessage = ChatMessage(
      messageId: messageId,
      text: messageText,
      isSentByMe: true,
      status: MessageStatus.sending, // пока не зашифровано и не передано в сеть
      isRead: true,
    );

    await DatabaseService.instance
        .addMessage(sentMessage, widget.contact.publicKey);
    try {
      // Шифруем на X25519 enc-ключ контакта (роутинг — по адресу publicKey).
      final encKey = widget.contact.encryptionKey ??
          await IdentityDirectoryService.instance.resolveEncKey(widget.contact.publicKey);
      if (encKey == null || encKey.isEmpty) {
        throw Exception('Ключ шифрования контакта недоступен');
      }
      final payload = await cryptoService.encrypt(encKey, messageText);
      websocketService.sendChatMessage(widget.contact.publicKey, payload,
          messageId: messageId);
      // Успех: сообщение передано в сеть или поставлено в offline-очередь.
      await DatabaseService.instance.updateMessageStatusByMessageId(
          widget.contact.publicKey, messageId, MessageStatus.sent);
    } catch (e) {
      // Раньше ошибка молча проглатывалась, и сообщение выглядело отправленным
      // (аудит LOGIC-4). Теперь помечаем как failed, чтобы показать это пользователю.
      DebugLogger.error('CHAT', 'Ошибка отправки сообщения: $e');
      await DatabaseService.instance.updateMessageStatusByMessageId(
          widget.contact.publicKey, messageId, MessageStatus.failed);
    }

    _messageController.clear();
    _inputFocusNode.requestFocus();
    await _loadChatHistory();

    if (!mounted) return;
    // Короткая "шифрую" анимация, затем сброс.
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _isEncrypting = false);
  }

  // --- Selection mode ---

  void _toggleSelection(int timestamp) {
    setState(() {
      if (_selectedTimestamps.contains(timestamp)) {
        _selectedTimestamps.remove(timestamp);
      } else {
        _selectedTimestamps.add(timestamp);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() => _selectedTimestamps.clear());
  }

  AppBar _buildSelectionAppBar(L10n l10n) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text(l10n.nSelected(_selectedTimestamps.length)),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.delete,
          onPressed: _deleteSelectedMessages,
        ),
      ],
    );
  }

  Future<void> _deleteSelectedMessages() async {
    final l10n = L10n.of(context);
    final count = _selectedTimestamps.length;
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.delete_outline,
      title: l10n.deleteSelectedConfirm(count),
      primaryLabel: l10n.delete,
      secondaryLabel: l10n.cancel,
      isDanger: true,
    );
    if (!ok) return;

    await DatabaseService.instance.deleteMessagesByTimestamps(
      widget.contact.publicKey,
      _selectedTimestamps.toList(),
    );
    _selectedTimestamps.clear();
    await _loadChatHistory();
  }

  Future<void> _deleteSingleMessage(ChatMessage message) async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.delete_outline,
      title: l10n.deleteSelectedConfirm(1),
      primaryLabel: l10n.delete,
      secondaryLabel: l10n.cancel,
      isDanger: true,
    );
    if (!ok) return;

    final id = message.messageId;
    if (id != null) {
      await DatabaseService.instance
          .deleteMessagesByMessageIds(widget.contact.publicKey, [id]);
    } else {
      await DatabaseService.instance.deleteMessagesByTimestamps(
        widget.contact.publicKey,
        [message.timestamp.millisecondsSinceEpoch],
      );
    }
    await _loadChatHistory();
  }

  Future<void> _deleteForBoth(ChatMessage message) async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.delete_sweep,
      title: l10n.deleteForBothConfirm,
      primaryLabel: l10n.deleteForBoth,
      secondaryLabel: l10n.cancel,
      isDanger: true,
    );
    if (!ok) return;

    final tsMs = message.timestamp.millisecondsSinceEpoch;
    final id = message.messageId;
    websocketService.sendDeleteForBoth(
      widget.contact.publicKey,
      timestampsMs: [tsMs],
      messageIds: id != null ? [id] : const [],
    );
    if (id != null) {
      await DatabaseService.instance
          .deleteMessagesByMessageIds(widget.contact.publicKey, [id]);
    } else {
      await DatabaseService.instance
          .deleteMessagesByTimestamps(widget.contact.publicKey, [tsMs]);
    }
    await _loadChatHistory();
  }

  /// Меню чата («…»). Раньше кнопка сразу открывала подтверждение очистки истории
  /// (вводило в заблуждение — иконка меню без меню). Теперь это настоящее меню
  /// с информацией о контакте (в т.ч. сверкой ключа против MITM) и очисткой (PROD-5).
  void _showChatMenu() {
    final l10n = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.info_outline, color: AppColors.primary),
              title: Text(l10n.contactInfo),
              onTap: () {
                Navigator.pop(sheetContext);
                _showContactInfo();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_forever, color: AppColors.danger),
              title: Text(l10n.clearHistory,
                  style: const TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmClearHistory();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Информация о контакте: имя + полный публичный ключ (для сверки против MITM)
  /// с возможностью копирования.
  void _showContactInfo() {
    final l10n = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.contact.name,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.publicKey,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                widget.contact.publicKey,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.verifyKeyHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: l10n.copy,
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: widget.contact.publicKey));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.keyCopied)),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.delete_forever,
      title: l10n.clearHistory,
      content: l10n.clearHistoryWarning,
      primaryLabel: l10n.delete,
      secondaryLabel: l10n.cancel,
      isDanger: true,
    );

    if (!ok) return;
    await DatabaseService.instance.clearChatHistory(widget.contact.publicKey);
    await _loadChatHistory();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelectionMode();
      },
      child: AppScaffold(
      safeArea: false,
      appBar: _isSelectionMode ? _buildSelectionAppBar(l10n) : AppBar(
        titleSpacing: 0,
        title: StreamBuilder<Map<String, bool>>(
          stream: presenceService.stream,
          initialData: const <String, bool>{},
          builder: (context, snapshot) {
            final isOnline = presenceService.isOnline(widget.contact.publicKey);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.contact.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: UserBadge(
                          pubkey: widget.contact.publicKey, compact: true),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? AppColors.success
                            : AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? l10n.online : l10n.offline,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          AppIconButton(
            icon: Icons.call,
            tooltip: l10n.call,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CallScreen(contactPublicKey: widget.contact.publicKey),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.more_horiz,
            tooltip: l10n.menu,
            onPressed: _showChatMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _chatHistory.isEmpty ? _EmptyChat() : _buildMessagesList(),
          ),
          if (!_isSelectionMode) _buildInputBar(),
        ],
      ),
    ),
    );
  }

  Widget _buildMessagesList() {
    // UI: reverse=true, поэтому "низ" = offset 0.
    final reversedMessages = _chatHistory.reversed.toList(growable: false);
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      itemCount: reversedMessages.length,
      itemBuilder: (context, index) {
        final message = reversedMessages[index];
        final prevMessage = index > 0 ? reversedMessages[index - 1] : null;
        final nextMessage = index < reversedMessages.length - 1
            ? reversedMessages[index + 1]
            : null;

        final showDateDivider = nextMessage == null ||
            !_isSameDay(message.timestamp, nextMessage.timestamp);
        final hideTime = prevMessage != null &&
            _isSameMinute(message.timestamp, prevMessage.timestamp) &&
            message.isSentByMe == prevMessage.isSentByMe;

        return Column(
          children: [
            if (showDateDivider) _DateDivider(date: message.timestamp),
            _buildMessageItem(message, hideTime: hideTime),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  Widget _buildMessageItem(ChatMessage message, {required bool hideTime}) {
    final l10n = L10n.of(context);
    final isMyMessage = message.isSentByMe;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);
    final messageId = message.timestamp.millisecondsSinceEpoch;

    final shouldAnimate = !_animatedMessageIds.contains(messageId);
    if (shouldAnimate) _animatedMessageIds.add(messageId);

    final callUi = _callStatusUiFor(message, l10n);
    if (callUi != null) {
      final isSelected = _selectedTimestamps.contains(messageId);
      final callWidget = _CallStatusPill(
        ui: callUi,
        timeStr: timeStr,
        isSelected: _isSelectionMode ? isSelected : null,
        onTap: _isSelectionMode
            ? () => _toggleSelection(messageId)
            : null,
        onLongPress: _isSelectionMode
            ? () => _toggleSelection(messageId)
            : () => _showMessageActions(message),
      );

      if (!shouldAnimate) return callWidget;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: callWidget,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
      );
    }

    final bubble = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: Column(
            crossAxisAlignment:
                isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMyMessage
                      ? AppColors.info.withOpacity(0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMyMessage ? 18 : 8),
                    bottomRight: Radius.circular(isMyMessage ? 8 : 18),
                  ),
                  border: ContainerBorder(isMyMessage: isMyMessage).border,
                ),
                child: Text(
                  message.text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              if (!hideTime)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 6, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                      if (isMyMessage) ...[
                        const SizedBox(width: 6),
                        _buildStatusIcon(message.status),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final isSelected = _selectedTimestamps.contains(messageId);

    final bubbleWithActions = GestureDetector(
      onTap: _isSelectionMode ? () => _toggleSelection(messageId) : null,
      onLongPress: _isSelectionMode
          ? () => _toggleSelection(messageId)
          : () => _showMessageActions(message),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.action.withOpacity(0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: isSelected
                      ? AppColors.action
                      : AppColors.textTertiary,
                ),
              ),
            Expanded(child: bubble),
          ],
        ),
      ),
    );

    if (!shouldAnimate) return bubbleWithActions;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final dx = isMyMessage ? 12.0 * (1 - v) : -12.0 * (1 - v);
        return Transform.translate(
          offset: Offset(dx, 6 * (1 - v)),
          child: Opacity(opacity: v, child: bubbleWithActions),
        );
      },
    );
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final l10n = L10n.of(context);
    final text = message.text;
    if (text.trim().isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.action),
                title: Text(l10n.copy),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add, color: AppColors.action),
                title: Text(l10n.notesAddFromChat),
                onTap: () => Navigator.pop(context, 'save'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text(l10n.delete),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              if (message.isSentByMe)
                ListTile(
                  leading: const Icon(Icons.delete_sweep, color: AppColors.danger),
                  title: Text(l10n.deleteForBoth),
                  onTap: () => Navigator.pop(context, 'delete_both'),
                ),
              ListTile(
                leading: const Icon(Icons.checklist, color: AppColors.action),
                title: Text(l10n.selectMessages),
                onTap: () => Navigator.pop(context, 'select'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.copied)),
      );
      return;
    }
    if (action == 'save') {
      await DatabaseService.instance.addNote(
        text: text,
        sourceType: NoteSourceType.contact.name,
        sourceId: widget.contact.publicKey,
        sourceLabel: widget.contact.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.notesAdded)),
      );
      return;
    }
    if (action == 'delete') {
      await _deleteSingleMessage(message);
      return;
    }
    if (action == 'delete_both') {
      await _deleteForBoth(message);
      return;
    }
    if (action == 'select') {
      _toggleSelection(message.timestamp.millisecondsSinceEpoch);
      return;
    }
  }

  Widget _buildInputBar() {
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AppTextField(
                controller: _messageController,
                hintText: l10n.messagePlaceholder,
                prefixIcon: Icons.lock_outline,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              isEncrypting: _isEncrypting,
              encryptionController: _encryptionController,
              onTap: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSameMinute(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  String _formatDateDivider(DateTime date) {
    final l10n = L10n.of(context);
    final locale = LocaleService.instance.effectiveLocale.languageCode;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return l10n.today;
    if (messageDate == yesterday) return l10n.yesterday;
    if (date.year == now.year) return DateFormat('d MMMM', locale).format(date);
    return DateFormat('d MMMM y', locale).format(date);
  }

  _CallStatusUi? _callStatusUiFor(ChatMessage message, L10n l10n) {
    final text = message.text.trim();
    // Совместимость: проверяем и русские и английские варианты
    if (text == 'Входящий звонок' || text == 'Incoming call') {
      return _CallStatusUi(
          icon: Icons.call_received,
          accent: AppColors.success,
          title: l10n.callLabel,
          subtitle: l10n.incoming);
    }
    if (text == 'Исходящий звонок' || text == 'Outgoing call') {
      return _CallStatusUi(
          icon: Icons.call_made,
          accent: AppColors.info,
          title: l10n.callLabel,
          subtitle: l10n.outgoing);
    }
    if (text == 'Пропущен звонок' || text == 'Missed call') {
      final isOutgoing = message.isSentByMe;
      return _CallStatusUi(
        icon: isOutgoing ? Icons.call_made : Icons.call_missed,
        accent: AppColors.danger,
        title: l10n.missedCall,
        subtitle: isOutgoing ? l10n.outgoing : l10n.incoming,
      );
    }
    return null;
  }
}

class ContainerBorder {
  const ContainerBorder({required this.isMyMessage});
  final bool isMyMessage;

  Border get border => Border.all(
        color:
            isMyMessage ? AppColors.info.withOpacity(0.20) : AppColors.outline,
        width: 1,
      );
}

class _EmptyChat extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 44, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(l10n.startConversation,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n.messagesEncrypted,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = (context.findAncestorStateOfType<_ChatScreenState>())
            ?._formatDateDivider(date) ??
        '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.divider)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: Border.all(color: AppColors.outline),
            ),
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: AppColors.divider)),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isEncrypting,
    required this.encryptionController,
    required this.onTap,
  });

  final bool isEncrypting;
  final AnimationController encryptionController;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: encryptionController,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(encryptionController.value);
        return SizedBox(
          width: 46,
          height: 46,
          child: Material(
            color: AppColors.accent,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: InkWell(
              onTap: isEncrypting ? null : onTap,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              child: Center(
                child: isEncrypting
                    ? Transform.rotate(
                        angle: t * 6.0,
                        child: const Icon(Icons.lock,
                            color: Colors.black, size: 20),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.black, size: 20),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CallStatusUi {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  const _CallStatusUi({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });
}

class _CallStatusPill extends StatelessWidget {
  const _CallStatusPill({
    required this.ui,
    required this.timeStr,
    this.isSelected,
    this.onTap,
    this.onLongPress,
  });

  final _CallStatusUi ui;
  final String timeStr;
  final bool? isSelected; // null = not in selection mode
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            // \u041E\u0433\u0440\u0430\u043D\u0438\u0447\u0438\u0432\u0430\u0435\u043C \u0448\u0438\u0440\u0438\u043D\u0443 \u043F\u0443\u0437\u044B\u0440\u044F \u0448\u0438\u0440\u0438\u043D\u043E\u0439 \u044D\u043A\u0440\u0430\u043D\u0430: \u043F\u0440\u0438 \u043A\u0440\u0443\u043F\u043D\u043E\u043C \u0441\u0438\u0441\u0442\u0435\u043C\u043D\u043E\u043C
            // \u0448\u0440\u0438\u0444\u0442\u0435 (Samsung) \u0434\u043B\u0438\u043D\u043D\u0430\u044F \u043D\u0430\u0434\u043F\u0438\u0441\u044C \u00AB\u041F\u0440\u043E\u043F\u0443\u0449\u0435\u043D\u043D\u044B\u0439 \u0437\u0432\u043E\u043D\u043E\u043A \u00B7 \u0412\u0445\u043E\u0434\u044F\u0449\u0438\u0439\u00BB
            // \u0438\u043D\u0430\u0447\u0435 \u0440\u0430\u0441\u0442\u044F\u0433\u0438\u0432\u0430\u043B\u0430 Row \u0437\u0430 \u043A\u0440\u0430\u0439 \u044D\u043A\u0440\u0430\u043D\u0430 (\u0432\u0440\u0435\u043C\u044F \u043E\u0431\u0440\u0435\u0437\u0430\u043B\u043E\u0441\u044C).
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: isSelected == true
                  ? AppColors.action.withOpacity(0.10)
                  : AppColors.surface,
              borderRadius: AppRadii.md,
              border: Border.all(color: ui.accent.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      isSelected!
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: isSelected!
                          ? AppColors.action
                          : AppColors.textTertiary,
                    ),
                  ),
                Icon(ui.icon, color: ui.accent, size: 16),
                const SizedBox(width: 8),
                // Flexible: \u043F\u0440\u0438 \u043D\u0435\u0445\u0432\u0430\u0442\u043A\u0435 \u043C\u0435\u0441\u0442\u0430 \u043D\u0430\u0434\u043F\u0438\u0441\u044C \u043F\u0435\u0440\u0435\u043D\u043E\u0441\u0438\u0442\u0441\u044F \u043D\u0430 2 \u0441\u0442\u0440\u043E\u043A\u0438
                // \u0432\u043C\u0435\u0441\u0442\u043E \u0432\u044B\u0445\u043E\u0434\u0430 \u0437\u0430 \u044D\u043A\u0440\u0430\u043D.
                Flexible(
                  child: Text(
                    '${ui.title} \u00B7 ${ui.subtitle}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(timeStr,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
