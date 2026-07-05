import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart' show cryptoService, websocketService;
import 'package:orpheus_project/models/room_message_model.dart';
import 'package:orpheus_project/models/room_model.dart';
import 'package:orpheus_project/models/note_model.dart';
import 'package:orpheus_project/services/badge_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/rooms_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';

class RoomChatScreen extends StatefulWidget {
  const RoomChatScreen({super.key, required this.room});

  final Room room;

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  static const String _orpheusRoomId = 'orpheus';
  static const String _orpheusRoomError = 'orpheus_unavailable';

  final RoomsService _service = RoomsService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<String>? _wsSub;
  final Set<String> _messageIds = <String>{};
  List<RoomMessage> _messages = <RoomMessage>[];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _isSending = false;
  String? _error;
  bool _canSendAsOrpheus = false;
  bool _sendAsOrpheus = false;
  bool _prefsLoaded = false;
  bool _warningDismissed = true;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadMyBadge();
    _loadRoomPrefs();
    _wsSub = websocketService.stream.listen(_handleWsMessage);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isOrpheusRoom => widget.room.id == _orpheusRoomId;

  Future<void> _loadMyBadge() async {
    final myKey = cryptoService.publicKeyBase64;
    if (myKey == null) return;
    final badge = await BadgeService.instance.getBadge(myKey);
    if (!mounted) return;
    final canSend = badge?.typeString == 'core' || badge?.typeString == 'owner';
    setState(() {
      _canSendAsOrpheus = canSend;
      if (!canSend) _sendAsOrpheus = false;
    });
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _service.loadMessages(widget.room.id);
      if (!mounted) return;
      _messages = result.messages;
      _hasMore = result.hasMore;
      _messageIds
        ..clear()
        ..addAll(result.messages.map((m) => m.id));
      _isLoading = false;
      _scrollToBottom();
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _isOrpheusRoom ? _orpheusRoomError : 'error';
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 100 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_messages.isEmpty || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final oldestId = int.tryParse(_messages.first.id);
      final result = await _service.loadMessages(
        widget.room.id,
        beforeId: oldestId,
      );
      if (!mounted) return;
      final newMessages =
          result.messages.where((m) => !_messageIds.contains(m.id)).toList();
      _messageIds.addAll(newMessages.map((m) => m.id));
      _messages = [...newMessages, ..._messages];
      _hasMore = result.hasMore;
      setState(() => _isLoadingMore = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadRoomPrefs() async {
    try {
      final prefs = await _service.loadRoomPrefs(widget.room.id);
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = prefs['notifications_enabled'] != false;
        _warningDismissed = prefs['warning_dismissed'] == true;
        _prefsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefsLoaded = true;
        _warningDismissed = true;
      });
    }
  }

  Future<void> _dismissWarning() async {
    setState(() => _warningDismissed = true);
    try {
      await _service.updateRoomPrefs(widget.room.id, warningDismissed: true);
    } catch (_) {
      // best-effort: не возвращаем баннер, чтобы не мешал
    }
  }

  Future<void> _toggleRoomNotifications() async {
    final l10n = L10n.of(context);
    final nextValue = !_notificationsEnabled;
    setState(() => _notificationsEnabled = nextValue);
    try {
      await _service.updateRoomPrefs(
        widget.room.id,
        notificationsEnabled: nextValue,
      );
      if (!mounted) return;
      final message =
          nextValue ? l10n.roomNotificationsOn : l10n.roomNotificationsOff;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _notificationsEnabled = !nextValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
    }
  }

  void _handleWsMessage(String messageJson) {
    Map<String, dynamic> data;
    try {
      final decoded = json.decode(messageJson);
      if (decoded is! Map<String, dynamic>) return;
      data = decoded;
    } catch (_) {
      return;
    }

    final type = data['type'] as String?;
    if (type != 'room-message' && type != 'room-system') return;

    final roomId = data['room_id']?.toString();
    if (roomId != widget.room.id) return;

    final msg = RoomMessage.fromJson(data);
    _appendMessage(msg);
  }

  void _appendMessage(RoomMessage message) {
    if (_messageIds.contains(message.id)) return;
    setState(() {
      _messageIds.add(message.id);
      _messages = [..._messages, message];
    });
    _scrollToBottom();
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateSeparator(BuildContext context, DateTime date) {
    final l10n = L10n.of(context);
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = l10n.today;
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = l10n.yesterday;
    } else {
      label = DateFormat.yMMMd(Localizations.localeOf(context).toString())
          .format(date.toLocal());
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.md,
          ),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final l10n = L10n.of(context);
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final response = await _service.sendMessage(
        widget.room.id,
        text,
        asOrpheus: _isOrpheusRoom && _canSendAsOrpheus && _sendAsOrpheus,
      );
      if (!mounted) return;

      final warningCode = response['moderation_warning_code'] as String?;
      final warningText = response['moderation_warning'] as String?;
      final warning = _mapModerationWarning(warningCode, warningText, l10n);
      if (warning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning)),
        );
      }

      final msgJson = response['message'];
      if (msgJson is Map<String, dynamic>) {
        _appendMessage(RoomMessage.fromJson(msgJson));
      } else {
        _appendMessage(
          RoomMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: text,
            senderKey: cryptoService.publicKeyBase64,
            senderName: _isOrpheusRoom && _sendAsOrpheus
                ? l10n.orpheusOfficialName
                : null,
            authorType: _isOrpheusRoom && _sendAsOrpheus ? 'orpheus' : null,
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
      _messageController.text = text;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _confirmRotateInvite() async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.vpn_key_outlined,
      title: l10n.rotateInviteTitle,
      content: l10n.rotateInviteDesc,
      primaryLabel: l10n.rotateConfirm,
      secondaryLabel: l10n.cancel,
    );
    if (!ok) return;

    try {
      final code = await _service.rotateInvite(widget.room.id);
      if (!mounted) return;
      _showInviteCodeDialog(code);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
    }
  }

  Future<void> _confirmPanicClear() async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.delete_forever,
      title: l10n.panicClearTitle,
      content: l10n.panicClearDesc,
      primaryLabel: l10n.panicClearConfirm,
      secondaryLabel: l10n.cancel,
      isDanger: true,
    );
    if (!ok) return;

    try {
      await _service.panicClear(widget.room.id);
      if (!mounted) return;
      setState(() {
        _messages = [];
        _messageIds.clear();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
    }
  }

  Future<void> _confirmLeaveRoom() async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.logout,
      title: l10n.leaveRoomTitle,
      content: l10n.leaveRoomDesc,
      primaryLabel: l10n.leaveConfirm,
      secondaryLabel: l10n.cancel,
      isDanger: true,
    );
    if (!ok) return;

    try {
      await _service.leaveRoom(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
    }
  }

  Future<void> _showInviteCodeDialog(String inviteCode) async {
    final l10n = L10n.of(context);
    final ok = await AppDialog.show(
      context: context,
      icon: Icons.vpn_key_outlined,
      title: l10n.inviteCodeTitle,
      content: inviteCode,
      primaryLabel: l10n.copy,
      secondaryLabel: l10n.close,
    );
    if (!ok) return;
    await Clipboard.setData(ClipboardData(text: inviteCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.inviteCodeCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        title: Text(widget.room.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'toggle_notifications':
                  _toggleRoomNotifications();
                  break;
                case 'rotate':
                  _confirmRotateInvite();
                  break;
                case 'panic':
                  _confirmPanicClear();
                  break;
                case 'leave':
                  _confirmLeaveRoom();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_notifications',
                child: Text(
                  _notificationsEnabled
                      ? l10n.disableRoomNotifications
                      : l10n.enableRoomNotifications,
                ),
              ),
              if (widget.room.isOwner && !_isOrpheusRoom)
                PopupMenuItem(
                  value: 'rotate',
                  child: Text(l10n.rotateInvite),
                ),
              PopupMenuItem(
                value: 'panic',
                child: Text(l10n.panicClear),
              ),
              if (!_isOrpheusRoom)
                PopupMenuItem(
                  value: 'leave',
                  child: Text(l10n.leaveRoom),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_prefsLoaded && !_warningDismissed)
            _WarningBanner(
              text: _isOrpheusRoom
                  ? l10n.orpheusRoomWarning
                  : l10n.roomWarningUnprotected,
              onDismiss: _dismissWarning,
            ),
          Expanded(child: _buildMessagesList(l10n)),
          _buildInputBar(l10n),
        ],
      ),
    );
  }

  Widget _buildMessagesList(L10n l10n) {
    if (_isLoading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _messages.isEmpty) {
      if (_error == _orpheusRoomError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off,
                    color: AppColors.textTertiary, size: 36),
                const SizedBox(height: 12),
                Text(
                  l10n.orpheusRoomUnavailable,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loadMessages,
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Text(
          l10n.connectionError,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Text(
          l10n.noMessagesDesc,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    final itemCount = _messages.length + (_isLoadingMore ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_isLoadingMore && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final msgIndex = _isLoadingMore ? index - 1 : index;
        final message = _messages[msgIndex];
        final showDateSep = msgIndex == 0 ||
            !_isSameDay(
                _messages[msgIndex - 1].createdAt, message.createdAt);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDateSep) _buildDateSeparator(context, message.createdAt),
            _RoomMessageBubble(
              message: message,
              onLongPress:
                  message.isSystem ? null : () => _saveNoteFromRoom(message),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputBar(L10n l10n) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isOrpheusRoom && _canSendAsOrpheus) ...[
              Row(
                children: [
                  const Icon(Icons.verified, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.writeAsOrpheus,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  Switch(
                    value: _sendAsOrpheus,
                    onChanged: (value) =>
                        setState(() => _sendAsOrpheus = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: l10n.messagePlaceholder,
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: AppColors.primary),
                  onPressed: _isSending ? null : _sendMessage,
                  tooltip: l10n.send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNoteFromRoom(RoomMessage message) async {
    final l10n = L10n.of(context);
    final text = message.text.trim();
    if (text.isEmpty) return;
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
    if (action != 'save') return;
    await DatabaseService.instance.addNote(
      text: text,
      sourceType: NoteSourceType.room.name,
      sourceId: widget.room.id,
      sourceLabel: widget.room.name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.notesAdded)),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.10),
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
              onPressed: onDismiss,
              tooltip: L10n.of(context).close,
            ),
        ],
      ),
    );
  }
}

class _RoomMessageBubble extends StatelessWidget {
  const _RoomMessageBubble({required this.message, this.onLongPress});

  final RoomMessage message;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final myKey = cryptoService.publicKeyBase64;
    final isOfficial = message.authorType == 'orpheus';
    final isMine = !message.isSystem &&
        !isOfficial &&
        message.senderKey != null &&
        message.senderKey == myKey;

    final l10n = L10n.of(context);
    final senderLabel = isOfficial
        ? l10n.orpheusOfficialName
        : (message.senderName ??
            (message.senderKey?.substring(0, 8) ?? '—'));

    if (message.isSystem) {
      final systemText = _mapSystemMessage(message, l10n);
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.outline.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            systemText,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final bubble = Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine
              ? AppColors.actionDark
              : isOfficial
                  ? AppColors.primary.withOpacity(0.12)
                  : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMine) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOfficial) ...[
                    const Icon(Icons.verified,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    senderLabel,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: isMine ? Colors.white : AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat.Hm().format(
                message.createdAt.toUtc().add(const Duration(hours: 3)),
              ),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(
                    color: isMine
                        ? Colors.white.withOpacity(0.7)
                        : AppColors.textTertiary,
                  ),
            ),
          ],
        ),
      ),
    );
    return GestureDetector(
      onLongPress: onLongPress,
      child: bubble,
    );
  }
}

String? _mapModerationWarning(String? code, String? fallback, L10n l10n) {
  if (code == "sensitive_data") {
    return l10n.moderationSensitiveWarning;
  }
  if (fallback != null && fallback.isNotEmpty) {
    return fallback;
  }
  return null;
}

String _mapSystemMessage(RoomMessage message, L10n l10n) {
  switch (message.systemCode) {
    case "invite_rotated":
      return l10n.roomSystemInviteRotated;
    case "history_cleared":
      return l10n.roomSystemHistoryCleared;
  }
  return message.text;
}
