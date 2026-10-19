// lib/updates_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/services/release_notes_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({
    super.key,
    ReleaseNotesService? releaseNotesService,
    Future<List<Map<String, dynamic>>>? debugEntriesFutureOverride,
  })  : _releaseNotesService = releaseNotesService,
        _debugEntriesFutureOverride = debugEntriesFutureOverride;

  final ReleaseNotesService? _releaseNotesService;
  final Future<List<Map<String, dynamic>>>? _debugEntriesFutureOverride;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late AnimationController _revealController;
  late Future<List<Map<String, dynamic>>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    ); // Визуальная система v1: без пульсаций и свечения.
    
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _entriesFuture = widget._debugEntriesFutureOverride ?? _loadEntries();
  }

  Future<List<Map<String, dynamic>>> _loadEntries() async {
    try {
      final service = widget._releaseNotesService ?? ReleaseNotesService();
      final releases = await service.fetchPublicReleases(limit: 50);
      if (releases.isEmpty) {
        return AppConfig.changelogData;
      }

      // Приводим к формату legacy, чтобы не переписывать UI целиком.
      // Ожидается: {version, date, changes: List<String>}
      final df = DateFormat('dd.MM.yyyy');
      return releases.map((r) {
        final date = r.createdAt != null ? df.format(r.createdAt!.toLocal()) : '';
        final changes = r.publicChangelog
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => s.startsWith('-') ? s.substring(1).trim() : s)
            .toList();

        return <String, dynamic>{
          'version': r.versionName.isNotEmpty ? r.versionName : 'build ${r.versionCode}',
          'date': date.isNotEmpty ? date : '—',
          'changes': changes,
        };
      }).toList();
    } catch (_) {
      // Fallback: встроенный legacy список (offline-safe)
      return AppConfig.changelogData;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Row(
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.outline),
                    boxShadow: AppShadows.bevel(),
                  ),
                  child: const Icon(
                    Icons.update,
                    color: AppColors.primary,
                    size: 18,
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Text(L10n.of(context).updateHistory.toUpperCase()),
          ],
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final entries = snapshot.data ?? AppConfig.changelogData;

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final item = entries[index];
              final version = item['version'] as String;
              final date = item['date'] as String;
              final changes = (item['changes'] as List).cast<String>();
              final isLatest = index == 0;

              return _buildAnimatedUpdateCard(
                index: index,
                version: version,
                date: date,
                changes: changes,
                isLatest: isLatest,
                isLast: index == entries.length - 1,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAnimatedUpdateCard({
    required int index,
    required String version,
    required String date,
    required List<String> changes,
    required bool isLatest,
    required bool isLast,
  }) {
    final delay = index * 0.1;
    
    return AnimatedBuilder(
      animation: Listenable.merge([_revealController, _glowController, _pulseController]),
      builder: (context, child) {
        final progress = ((_revealController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        
        return Transform.translate(
          offset: Offset(0, 30 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline
                SizedBox(
                  width: 40,
                  child: Column(
                    children: [
                      // Точка на таймлайне
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: isLatest ? 16 : 12,
                            height: isLatest ? 16 : 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isLatest ? AppColors.primary : AppColors.surface2,
                              border: Border.all(
                                color: isLatest ? AppColors.primaryLight : AppColors.outline,
                                width: isLatest ? 2 : 1,
                              ),
                              boxShadow: AppShadows.bevel(),
                            ),
                          );
                        },
                      ),
                      // Линия
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 120 + changes.length * 24.0,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                isLatest
                                    ? AppColors.primaryDark.withOpacity(0.5)
                                    : AppColors.outline,
                                AppColors.divider,
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Карточка
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: isLatest ? AppColors.surfaceElevated : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isLatest ? AppColors.outline : AppColors.divider,
                        width: 1,
                      ),
                      boxShadow: isLatest ? AppShadows.bevel() : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Заголовок
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  if (isLatest) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      margin: const EdgeInsets.only(right: 10),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface2,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.outline),
                                      ),
                                      child: Text(
                                        "LATEST",
                                        style: AppTypography.mono(
                                          color: AppColors.primary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 1.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                  Text(
                                    version,
                                    style: AppTypography.mono(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      color: isLatest ? AppColors.textPrimary : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.surface2,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  date,
                                  style: AppTypography.mono(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Разделитель
                          Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  AppColors.outline,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Список изменений
                          ...changes.asMap().entries.map((entry) {
                            final changeIndex = entry.key;
                            final change = entry.value;
                            
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: Duration(milliseconds: 300 + changeIndex * 80),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(10 * (1 - value), 0),
                                  child: Opacity(
                                    opacity: value,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.only(top: 6, right: 10),
                                            decoration: BoxDecoration(
                                              color: isLatest
                                                  ? AppColors.accent
                                                  : AppColors.textTertiary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              change,
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1.4,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
