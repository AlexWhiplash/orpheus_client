// lib/screens/support_chat_screen.dart
// Экран чата с разработчиком

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart' show websocketService;
import 'package:orpheus_project/models/support_message.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/support_chat_service.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _service = SupportChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _wsSubscription;
  Timer? _autoRefreshTimer;
  bool _isSending = false;
  bool _isSendingLogs = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    
    _messagesSubscription = _service.messagesStream.listen((_) {
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    });
    
    // Слушаем WebSocket для мгновенного получения ответов
    _wsSubscription = websocketService.stream.listen((messageJson) {
      try {
        final data = json.decode(messageJson) as Map<String, dynamic>;
        if (data['type'] == 'support-reply') {
          _service.handleIncomingReply(data);
          DebugLogger.info('SUPPORT', 'Reply received via WebSocket');
        }
      } catch (_) {}
    });
    
    // Авто-обновление каждые 15 секунд как fallback
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _silentRefresh();
      }
    });
  }
  
  /// Тихое обновление без индикатора загрузки
  Future<void> _silentRefresh() async {
    final oldCount = _service.messages.length;
    await _service.loadMessages();
    
    // Если появились новые сообщения - скроллим вниз
    if (mounted && _service.messages.length > oldCount) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _wsSubscription?.cancel();
    _messagesSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    await _service.loadMessages();
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;
    
    setState(() => _isSending = true);
    _messageController.clear();
    
    final success = await _service.sendMessage(text);
    
    if (mounted) {
      setState(() => _isSending = false);
      
      if (!success) {
        final l10n = L10n.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.messageNotSent),
            backgroundColor: AppColors.danger,
          ),
        );
        // Восстанавливаем текст
        _messageController.text = text;
      }
    }
  }

  Future<void> _sendLogs() async {
    if (_isSendingLogs) return;
    
    final l10n = L10n.of(context);
    final logsCount = DebugLogger.logs.length;
    
    // Подтверждение
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(l10n.sendLogsQuestion, style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          l10n.logsWillBeSent(logsCount),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.send, style: const TextStyle(color: AppColors.action)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isSendingLogs = true);
    
    final success = await _service.sendLogs();
    
    if (mounted) {
      setState(() => _isSendingLogs = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? l10n.logsSent : l10n.logsError),
          backgroundColor: success ? AppColors.success : AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.developerChat,
              style: const TextStyle(fontSize: 16, letterSpacing: 1),
            ),
            Text(
              l10n.willReply,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
            tooltip: l10n.refreshTooltip,
          ),
        ],
      ),
      body: Column(
        children: [
          // Сообщения
          Expanded(
            child: _buildMessagesList(l10n),
          ),
          
          // Панель ввода
          _buildInputPanel(l10n),
        ],
      ),
    );
  }

  Widget _buildMessagesList(L10n l10n) {
    if (_service.isLoading && _service.messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    
    if (_service.error != null && _service.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
            const SizedBox(height: 16),
            Text(
              _service.error!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loadMessages,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    
    if (_service.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: AppColors.outline),
                  boxShadow: AppShadows.bevel(),
                ),
                child: const Icon(
                  Icons.support_agent,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.writeToUs,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.questionsProblemsIdeas,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _service.messages.length,
      itemBuilder: (context, index) {
        final message = _service.messages[index];
        return _buildMessageBubble(message, l10n);
      },
    );
  }

  Widget _buildMessageBubble(SupportMessage message, L10n l10n) {
    final isAdmin = message.direction == MessageDirection.admin;
    final isSystem = message.isSystemMessage;
    
    return Align(
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSystem
              ? AppColors.surface2
              : isAdmin 
                  ? AppColors.surfaceElevated
                  : AppColors.actionContainer,
          border: isSystem || isAdmin ? Border.all(color: AppColors.outline) : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isAdmin ? 4 : 16),
            bottomRight: Radius.circular(isAdmin ? 16 : 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              message.message,
              style: TextStyle(
                color: isSystem || isAdmin
                    ? AppColors.textPrimary
                    : AppColors.onActionContainer,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin) ...[
                  Text(
                    l10n.developer,
                    style: AppTypography.mono(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  _formatTime(message.createdAt, l10n),
                  style: AppTypography.mono(
                    color: isSystem || isAdmin
                        ? AppColors.textTertiary
                        : AppColors.onActionContainer.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputPanel(L10n l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Кнопка отправки логов
            IconButton(
              icon: _isSendingLogs
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : const Icon(Icons.attach_file, color: AppColors.textSecondary),
              onPressed: _isSendingLogs ? null : _sendLogs,
              tooltip: l10n.sendLogs,
            ),
            
            // Поле ввода
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.messagePlaceholder,
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surface2,
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
            
            // Кнопка отправки
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.action,
                      ),
                    )
                  : const Icon(Icons.send, color: AppColors.action),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime, L10n l10n) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) return l10n.now;
    if (diff.inHours < 1) return l10n.minAgo(diff.inMinutes);
    if (diff.inDays < 1) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return l10n.daysAgo(diff.inDays);
    
    return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
  }
}

