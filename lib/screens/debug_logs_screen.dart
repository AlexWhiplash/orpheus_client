// lib/screens/debug_logs_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/telemetry_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _subscription;
  
  // Фильтр по тегам
  String? _selectedTag;
  bool _autoScroll = true;
  
  // Доступные теги
  final Set<String> _availableTags = {};

  @override
  void initState() {
    super.initState();
    _updateTags();
    
    // Подписка на обновления логов
    _subscription = DebugLogger.onUpdate.listen((_) {
      if (mounted) {
        setState(() {
          _updateTags();
        });
        
        if (_autoScroll && _scrollController.hasClients) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }
    });
  }

  void _updateTags() {
    _availableTags.clear();
    for (final log in DebugLogger.logs) {
      _availableTags.add(log.tag);
    }
  }

  List<LogEntry> get _filteredLogs {
    if (_selectedTag == null) {
      return DebugLogger.logs;
    }
    return DebugLogger.logs.where((e) => e.tag == _selectedTag).toList();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return AppColors.info;
      case LogLevel.warning:
        return AppColors.warning;
      case LogLevel.error:
        return AppColors.danger;
      case LogLevel.success:
        return AppColors.success;
    }
  }

  Color _getTagColor(String tag) {
    final hash = tag.hashCode;
    // Стальная гамма вместо радуги: теги различаются оттенком серебра.
    const colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.primaryDark,
      AppColors.textSecondary,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final logs = _filteredLogs;
    
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          'DEBUG LOGS',
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
            color: AppColors.danger,
          ),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // Тумблер отправки телеметрии на сервер (opt-in, только для отладки).
          // Даже включённая, телеметрия НЕ шлёт личности контактов и отпечаток
          // устройства (см. AUDIT_REPORT SEC-2).
          IconButton(
            icon: Icon(
              TelemetryService.instance.isEnabled ? Icons.cloud_upload : Icons.cloud_off,
              color: TelemetryService.instance.isEnabled ? AppColors.warning : AppColors.textTertiary,
            ),
            tooltip: 'Отправка телеметрии на сервер (для отладки)',
            onPressed: () async {
              final newValue = !TelemetryService.instance.isEnabled;
              await TelemetryService.instance.setEnabled(newValue);
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(newValue
                      ? 'Телеметрия включена (без данных контактов и устройства)'
                      : 'Телеметрия выключена'),
                  backgroundColor: newValue ? AppColors.warning : AppColors.surfaceElevated,
                ),
              );
            },
          ),
          // Кнопка автоскролла
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: _autoScroll ? AppColors.action : AppColors.textTertiary,
            ),
            tooltip: l10n.autoScroll,
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
            },
          ),
          // Копировать логи
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.copy,
            onPressed: () {
              final text = DebugLogger.exportToText();
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.logsCopied),
                  backgroundColor: AppColors.success,
                ),
              );
            },
          ),
          // Поделиться логами
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: l10n.share,
            onPressed: () async {
              // Шарим ФАЙЛ логов (полная история, переживает рестарт), если файловое
              // логирование включено; иначе — текущий RAM-буфер текстом.
              final path = await DebugLogger.flushAndGetLogFilePath();
              if (path != null) {
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(path)],
                    subject: 'Orpheus Debug Logs',
                  ),
                );
              } else {
                await SharePlus.instance.share(
                  ShareParams(
                    text: DebugLogger.exportToText(),
                    subject: 'Orpheus Debug Logs',
                  ),
                );
              }
            },
          ),
          // Очистить логи
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.clearLogs,
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surfaceElevated,
                  title: Text(l10n.clearLogsQuestion, style: const TextStyle(color: AppColors.textPrimary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () {
                        DebugLogger.clear();
                        Navigator.pop(ctx);
                      },
                      child: Text(l10n.clearLogs, style: const TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Панель фильтров
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: AppColors.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Кнопка "Все"
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FilterChip(
                      label: Text('${l10n.all} (${DebugLogger.logs.length})'),
                      selected: _selectedTag == null,
                      selectedColor: AppColors.surfaceElevated,
                      checkmarkColor: AppColors.textPrimary,
                      labelStyle: AppTypography.mono(
                        color: _selectedTag == null ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedTag = null);
                      },
                    ),
                  ),
                  // Теги
                  ..._availableTags.map((tag) {
                    final count = DebugLogger.logs.where((e) => e.tag == tag).length;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FilterChip(
                        label: Text('$tag ($count)'),
                        selected: _selectedTag == tag,
                        selectedColor: AppColors.surfaceElevated,
                        checkmarkColor: _getTagColor(tag),
                        labelStyle: AppTypography.mono(
                          color: _selectedTag == tag ? _getTagColor(tag) : AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        onSelected: (_) {
                          setState(() => _selectedTag = _selectedTag == tag ? null : tag);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          
          // Статус-бар
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: AppColors.surface2,
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.success),
                const SizedBox(width: 6),
                Text(
                  '${l10n.entries}: ${logs.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontFamily: AppTypography.monoFamily,
                  ),
                ),
                const Spacer(),
                Text(
                  'Real-time logging',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontFamily: AppTypography.monoFamily,
                  ),
                ),
              ],
            ),
          ),
          
          // Список логов
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      l10n.noLogs,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final entry = logs[index];
                      return _buildLogEntry(entry, index, l10n);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(LogEntry entry, int index, L10n l10n) {
    final levelColor = _getLevelColor(entry.level);
    final tagColor = _getTagColor(entry.tag);
    
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.entryCopied),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: index % 2 == 0 ? Colors.transparent : AppColors.surface,
          border: Border(
            left: BorderSide(
              color: levelColor.withOpacity(0.5),
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Время
            SizedBox(
              width: 85,
              child: Text(
                entry.timeString,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontFamily: AppTypography.monoFamily,
                ),
              ),
            ),
            // Тег
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.outline),
              ),
              child: Text(
                entry.tag,
                style: TextStyle(
                  color: tagColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  fontFamily: AppTypography.monoFamily,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Сообщение
            Expanded(
              child: Text(
                entry.message,
                style: TextStyle(
                  color: levelColor == AppColors.danger ? AppColors.danger : AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: AppTypography.monoFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

