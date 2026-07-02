// lib/screens/ai_assistant_chat_screen.dart
// Экран чата с AI помощником Orpheus — "Оракул Орфея"

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/models/ai_message_model.dart';
import 'package:orpheus_project/models/note_model.dart';
import 'package:orpheus_project/services/ai_assistant_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

class AiAssistantChatScreen extends StatefulWidget {
  const AiAssistantChatScreen({super.key});

  @override
  State<AiAssistantChatScreen> createState() => _AiAssistantChatScreenState();
}

class _AiAssistantChatScreenState extends State<AiAssistantChatScreen>
    with TickerProviderStateMixin {
  final AiAssistantService _service = AiAssistantService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<List<AiMessage>>? _messagesSub;
  StreamSubscription<bool>? _loadingSub;

  bool _isLoading = false;

  // Анимация для аватара AI
  late AnimationController _avatarPulseController;
  late Animation<double> _avatarPulseAnimation;

  @override
  void initState() {
    super.initState();

    // Подписка на сообщения
    _messagesSub = _service.messagesStream.listen((_) {
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    });

    // Подписка на статус загрузки
    _loadingSub = _service.loadingStream.listen((loading) {
      if (mounted) {
        setState(() => _isLoading = loading);
      }
    });

    // Анимация пульсации аватара
    _avatarPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _avatarPulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _avatarPulseController,
        curve: Curves.easeInOut,
      ),
    );

    _service.init();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _loadingSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _avatarPulseController.dispose();
    _service.dispose();
    super.dispose();
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
    if (text.isEmpty || _isLoading) return;

    HapticFeedback.lightImpact();
    _messageController.clear();
    await _service.sendMessage(text);
  }

  void _clearChat() {
    HapticFeedback.mediumImpact();
    _service.clearChat();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final memoryLimit = AiAssistantService.assistantMemoryLimit;
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        title: Row(
          children: [
            _AiAvatarSmall(animation: _avatarPulseAnimation),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiAssistantName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.aiAssistantOnline,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.success,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.aiMemoryIndicator(memoryLimit),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_service.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _showClearConfirmation(l10n),
              tooltip: l10n.aiClearMemory,
            ),
        ],
      ),
      body: Column(
        children: [
          // Область сообщений
          Expanded(child: _buildMessagesList(l10n)),
          
          // Поле ввода
          _buildInputBar(l10n),
        ],
      ),
    );
  }

  Widget _buildMessagesList(L10n l10n) {
    final messages = _service.messages;

    if (messages.isEmpty && !_isLoading) {
      return _buildWelcomeScreen(l10n);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        // Индикатор "AI думает" в конце списка
        if (index == messages.length && _isLoading) {
          return const _ThinkingIndicator();
        }
        return _MessageBubble(
          message: messages[index],
          onLongPress: () => _saveNoteFromOracle(messages[index]),
        );
      },
    );
  }

  Widget _buildWelcomeScreen(L10n l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          
          // Большой аватар AI с анимацией
          _AiAvatarLarge(animation: _avatarPulseAnimation),
          
          const SizedBox(height: 24),
          
          Text(
            l10n.aiAssistantName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            l10n.aiAssistantWelcome,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          
          const SizedBox(height: 32),
          
          // Примеры вопросов
          _buildSuggestionChips(l10n),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips(L10n l10n) {
    final suggestions = [
      l10n.aiSuggestion1,
      l10n.aiSuggestion2,
      l10n.aiSuggestion3,
      l10n.aiSuggestion4,
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: suggestions.map((text) {
        return ActionChip(
          label: Text(
            text,
            style: const TextStyle(fontSize: 13),
          ),
          backgroundColor: AppColors.surface2,
          side: BorderSide(color: AppColors.outline),
          onPressed: () {
            _messageController.text = text;
            _sendMessage();
          },
        );
      }).toList(),
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
        child: Row(
          children: [
            // Поле ввода
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.aiMessageHint,
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                enabled: !_isLoading,
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Кнопка отправки
            _SendButton(
              isLoading: _isLoading,
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  void _showClearConfirmation(L10n l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(l10n.aiClearMemoryTitle),
        content: Text(l10n.aiClearMemoryDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearChat();
            },
            child: Text(
              l10n.delete,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNoteFromOracle(AiMessage message) async {
    final l10n = L10n.of(context);
    final text = message.content.trim();
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
                leading: const Icon(Icons.bookmark_add, color: AppColors.action),
                title: Text(l10n.notesAddFromChat),
                onTap: () => Navigator.pop(context, 'save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action != 'save') return;
    await DatabaseService.instance.addNote(
      text: text,
      sourceType: NoteSourceType.oracle.name,
      sourceId: 'oracle',
      sourceLabel: l10n.aiAssistantName,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.notesAdded)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ВИДЖЕТЫ
// ══════════════════════════════════════════════════════════════════════════════

/// Маленький аватар AI для AppBar.
class _AiAvatarSmall extends StatelessWidget {
  const _AiAvatarSmall({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.action.withOpacity(0.8 * animation.value),
                AppColors.primary.withOpacity(0.6 * animation.value),
                AppColors.action.withOpacity(0.9 * animation.value),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.action.withOpacity(0.3 * animation.value),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome,
            color: Colors.white,
            size: 20,
          ),
        );
      },
    );
  }
}

/// Большой аватар AI для welcome screen.
class _AiAvatarLarge extends StatelessWidget {
  const _AiAvatarLarge({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                AppColors.action,
                AppColors.primary,
                AppColors.action.withOpacity(0.7),
                AppColors.actionLight,
                AppColors.action,
              ],
              transform: GradientRotation(animation.value * math.pi * 2),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.action.withOpacity(0.4 * animation.value),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
            ),
            child: const Icon(
              Icons.psychology,
              color: AppColors.action,
              size: 48,
            ),
          ),
        );
      },
    );
  }
}

/// Индикатор "AI думает" с анимированными точками.
class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator();

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    // Запуск с задержкой для эффекта волны
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.action.withOpacity(0.12),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < 3; i++) ...[
              AnimatedBuilder(
                animation: _animations[i],
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -4 * _animations[i].value),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.action.withOpacity(
                          0.5 + 0.5 * _animations[i].value,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
              if (i < 2) const SizedBox(width: 4),
            ],
            const SizedBox(width: 8),
            Text(
              L10n.of(context).aiThinking,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.action,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пузырь сообщения в чате.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onLongPress});

  final AiMessage message;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiMessageRole.user;
    final isError = message.isError;

    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.actionDark
              : isError
                  ? AppColors.danger.withOpacity(0.15)
                  : AppColors.action.withOpacity(0.12),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isError
              ? Border.all(color: AppColors.danger.withOpacity(0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Контент сообщения
            if (isUser)
              Text(
                message.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
              )
            else
              // Markdown для ответов AI
              MarkdownBody(
                data: message.content,
                styleSheet: _buildMarkdownStyle(context, isError),
                onTapLink: (text, href, title) {
                  if (href != null) {
                    launchUrl(Uri.parse(href));
                  }
                },
                selectable: true,
              ),

            const SizedBox(height: 4),

            // Время
            Text(
              DateFormat.Hm().format(message.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isUser
                        ? Colors.white.withOpacity(0.7)
                        : isError
                            ? AppColors.danger
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

  MarkdownStyleSheet _buildMarkdownStyle(BuildContext context, bool isError) {
    final textColor = isError ? AppColors.danger : AppColors.textPrimary;
    final secondaryColor =
        isError ? AppColors.danger.withOpacity(0.8) : AppColors.textSecondary;
    final accentColor = isError ? AppColors.danger : AppColors.action;

    return MarkdownStyleSheet(
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      h1: Theme.of(context).textTheme.titleMedium?.copyWith(color: accentColor),
      h2: Theme.of(context).textTheme.titleSmall?.copyWith(color: accentColor),
      h3: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w600,
          ),
      strong:
          Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
      em: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: secondaryColor,
            fontStyle: FontStyle.italic,
          ),
      code: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: accentColor,
            fontFamily: 'monospace',
            backgroundColor: AppColors.surface2,
          ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accentColor.withOpacity(0.5), width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      listBullet:
          Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      a: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: accentColor,
            decoration: TextDecoration.underline,
          ),
    );
  }
}

/// Кнопка отправки с анимацией загрузки.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLoading
              ? [AppColors.surface2, AppColors.surface2]
              : [AppColors.action, AppColors.actionDark],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: isLoading
            ? null
            : [
                BoxShadow(
                  color: AppColors.action.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(22),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.action,
                    ),
                  )
                : const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }
}
