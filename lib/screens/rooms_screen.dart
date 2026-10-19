import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/models/room_model.dart';
import 'package:orpheus_project/screens/notes_vault_screen.dart';
import 'package:orpheus_project/screens/room_chat_screen.dart';
import 'package:orpheus_project/services/room_unread_service.dart';
import 'package:orpheus_project/services/rooms_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/app_states.dart';
import 'package:orpheus_project/widgets/messenger_ui.dart';

/// Превью последнего сообщения в списке комнат. Системные сообщения приходят как
/// сырой код `SYS:HISTORY_CLEARED` — маппим их в локализованный текст (как чат),
/// иначе в списке торчит служебный код.
String _roomPreview(String? raw, L10n l10n) {
  final text = raw ?? '';
  if (text.startsWith('SYS:')) {
    switch (text.substring(4).toUpperCase()) {
      case 'HISTORY_CLEARED':
        return l10n.roomSystemHistoryCleared;
      case 'INVITE_ROTATED':
        return l10n.roomSystemInviteRotated;
    }
    return ''; // неизвестный код — лучше пусто, чем сырой SYS:
  }
  return text;
}

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  /// ID официальной комнаты Orpheus.
  /// TODO(future): Официальная комната Orpheus — функционал на будущее.
  /// Сейчас комната скрыта от пользователей (фильтруется в списке).
  /// Когда будет готова — убрать фильтрацию в методе build().
  static const String _orpheusRoomId = 'orpheus';

  final RoomsService _service = RoomsService();
  late Future<List<Room>> _roomsFuture;

  @override
  void initState() {
    super.initState();
    _roomsFuture = _loadAndSyncUnread();
  }

  /// Load rooms and recompute the Rooms-tab unread dot from the fresh list
  /// (excludes the hidden official room).
  Future<List<Room>> _loadAndSyncUnread() async {
    final rooms = await _service.loadRooms();
    await RoomUnreadService.instance.syncWithRooms(
      rooms.where((r) => r.id != _orpheusRoomId).toList(),
    );
    return rooms;
  }

  void _refreshRooms() {
    // Called from `await Navigator.push(...)` continuations. A duress unlock drops
    // pushed routes, which completes those futures while this State is already
    // disposed (the tabs go away with home under the lock).
    if (!mounted) return;
    setState(() {
      _roomsFuture = _loadAndSyncUnread();
    });
  }

  Future<void> _showCreateRoomDialog() async {
    final l10n = L10n.of(context);
    final name = await AppInputDialog.show(
      context: context,
      icon: Icons.forum_outlined,
      title: l10n.createRoom,
      hintText: l10n.roomNameHint,
      primaryLabel: l10n.create,
      secondaryLabel: l10n.cancel,
    );

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;

    try {
      final result = await _service.createRoom(trimmed);
      if (!mounted) return;
      _showInviteCodeDialog(result.inviteCode);
      _refreshRooms();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.roomCreated)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionError)),
      );
    }
  }

  Future<void> _showJoinRoomDialog() async {
    final l10n = L10n.of(context);
    final code = await AppInputDialog.show(
      context: context,
      icon: Icons.vpn_key_outlined,
      title: l10n.joinRoom,
      hintText: l10n.inviteCodeHint,
      primaryLabel: l10n.join,
      secondaryLabel: l10n.cancel,
    );

    final trimmed = code?.trim() ?? '';
    if (trimmed.isEmpty) return;

    try {
      await _service.joinRoom(trimmed);
      if (!mounted) return;
      _refreshRooms();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.roomJoined)),
      );
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

  void _showRoomActionsSheet() {
    final l10n = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(l10n.createRoom),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateRoomDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(l10n.joinRoom),
                onTap: () {
                  Navigator.pop(context);
                  _showJoinRoomDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: AppSpacing.md,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.1,
        ),
        title: Text(l10n.rooms),
        actions: [
          HeaderIconButton(
            icon: Icons.refresh,
            tooltip: l10n.refreshTooltip,
            onPressed: _refreshRooms,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showRoomActionsSheet,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Room>>(
        future: _roomsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ErrorState(
              title: l10n.loadingError,
              message: l10n.connectionError,
              onRetry: _refreshRooms,
              retryLabel: l10n.retry,
            );
          }

          final rawRooms = snapshot.data ?? const <Room>[];
          final rooms = rawRooms
              .where((room) => room.id != _orpheusRoomId)
              .toList(growable: false);
          final itemCount = rooms.isEmpty ? 2 : rooms.length + 1;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, 100),
            itemCount: itemCount,
            separatorBuilder: (_, __) => rooms.isEmpty
                ? const SizedBox(height: AppSpacing.md)
                : const ListRowDivider(),
            itemBuilder: (context, index) {
              if (index == 0) {
                return NotesVaultRow(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotesVaultScreen()),
                    );
                  },
                );
              }
              if (rooms.isEmpty) {
                return EmptyState(
                  title: l10n.noRooms,
                  subtitle: l10n.noRoomsDesc,
                  icon: Icons.forum_outlined,
                  actionLabel: l10n.createRoom,
                  onAction: _showRoomActionsSheet,
                );
              }
              final room = rooms[index - 1];
              return RoomListRow(
                room: room,
                isOrpheus: room.id == _orpheusRoomId,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => RoomChatScreen(room: room)),
                  );
                  _refreshRooms();
                },
              );
            },
          );
        },
      ),
    );
  }

}

/// Строка «Хранилище заметок» над списком комнат: стальная плитка с замком.
class NotesVaultRow extends StatelessWidget {
  const NotesVaultRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: AppColors.surfaceElevated,
                  boxShadow: AppShadows.bevel(),
                ),
                child: const Icon(Icons.lock, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.notesVaultTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.notesVaultDesc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка комнаты: аватар-квадрат, имя, превью последнего сообщения.
class RoomListRow extends StatelessWidget {
  const RoomListRow({
    super.key,
    required this.room,
    required this.onTap,
    required this.isOrpheus,
  });

  final Room room;
  final VoidCallback onTap;
  final bool isOrpheus;

  /// Время последнего сообщения: сегодня — 14:32, иначе — 12 июн.
  static String _formatLastTime(DateTime? at, String locale) {
    if (at == null) return '';
    final dt = at.toLocal();
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) return DateFormat.Hm(locale).format(dt);
    if (dt.year == now.year) return DateFormat.MMMd(locale).format(dt);
    return DateFormat('dd.MM.yyyy', locale).format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _roomPreview(room.lastMessagePreview, L10n.of(context));
    final timeLabel = _formatLastTime(
        room.lastMessageAt, Localizations.localeOf(context).languageCode);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 11),
          child: Row(
            children: [
              if (isOrpheus)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/images/logo_mark.png',
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                MessengerAvatar(name: room.name, size: 48, radius: 15),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (isOrpheus) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: AppShadows.bevel(),
                            ),
                            child: Text(
                              L10n.of(context).orpheusOfficialBadge,
                              style: AppTypography.mono(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                        if (room.isOwner) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.shield,
                              size: 15, color: AppColors.warning),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (timeLabel.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  timeLabel,
                  style: AppTypography.mono(
                      fontSize: 11.5, color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
