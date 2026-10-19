// lib/widgets/badge_widget.dart
// STEEL TABLET BADGE SYSTEM (Orpheus visual system v1)
// Одна стальная табличка для всех статусов; статус различается металлом
// точки и гравированной надписи (AppBadgeMetals). Без свечения и анимаций.

import 'package:flutter/material.dart';
import 'package:orpheus_project/services/badge_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Legacy palette of the former glass badges. Not painted anymore; kept only
/// so that existing references (tests) keep compiling.
class GlassColors {
  static const Color coreGlass = Color(0xFFFF1744);
  static const Color coreGlow = Color(0xFFFF5252);
  static const Color ownerGlass = Color(0xFFD32F2F);
  static const Color ownerGlow = Color(0xFFEF5350);
  static const Color patronGlass = Color(0xFF9C27B0);
  static const Color patronGlow = Color(0xFFBA68C8);
  static const Color benefactorGlass = Color(0xFFFFB300);
  static const Color benefactorGlow = Color(0xFFFFD54F);
  static const Color earlyGlass = Color(0xFF546E7A);
  static const Color earlyGlow = Color(0xFF78909C);
}

/// Гравированная стальная табличка статуса.
///
/// [enableAnimations] сохранён ради совместимости API: табличка статична.
class LuxuryBadgeWidget extends StatelessWidget {
  final BadgeInfo badge;
  final bool compact;
  final bool enableAnimations;

  const LuxuryBadgeWidget({
    super.key,
    required this.badge,
    this.compact = false,
    this.enableAnimations = true,
  });

  static Color metalFor(BadgeInfo badge) {
    switch (badge.type) {
      case BadgeType.core:
        return AppBadgeMetals.core;
      case BadgeType.owner:
        return AppBadgeMetals.owner;
      case BadgeType.patron:
        return AppBadgeMetals.patron;
      case BadgeType.benefactor:
        return AppBadgeMetals.benefactor;
      case BadgeType.early:
        return AppBadgeMetals.early;
    }
  }

  @override
  Widget build(BuildContext context) {
    final metal = metalFor(badge);

    final hPad = compact ? 7.0 : 10.0;
    final vPad = compact ? 3.0 : 5.0;
    final fontSize = compact ? 9.0 : 10.5;
    final dot = compact ? 5.0 : 6.0;
    final gap = compact ? 5.0 : 7.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.outline, width: 1),
        boxShadow: AppShadows.bevel(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(color: metal, shape: BoxShape.circle),
          ),
          SizedBox(width: gap),
          Text(
            badge.label.toUpperCase(),
            style: AppTypography.mono(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: metal,
              letterSpacing: fontSize * 0.18,
            ).copyWith(height: 1.1),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// СОВМЕСТИМЫЕ ВИДЖЕТЫ
// ============================================================================

class BadgeWidget extends StatelessWidget {
  final BadgeInfo badge;
  final bool compact;

  const BadgeWidget({
    super.key,
    required this.badge,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return LuxuryBadgeWidget(badge: badge, compact: compact);
  }
}

class UserBadge extends StatefulWidget {
  final String pubkey;
  final bool compact;

  const UserBadge({super.key, required this.pubkey, this.compact = false});

  @override
  State<UserBadge> createState() => _UserBadgeState();
}

class _UserBadgeState extends State<UserBadge> {
  BadgeInfo? _badge;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBadge();
  }

  @override
  void didUpdateWidget(UserBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pubkey != widget.pubkey) _loadBadge();
  }

  Future<void> _loadBadge() async {
    final cached = BadgeService.instance.getBadgeCached(widget.pubkey);
    if (cached != null) {
      if (mounted)
        setState(() {
          _badge = cached;
          _loading = false;
        });
      return;
    }
    setState(() => _loading = true);
    final badge = await BadgeService.instance.getBadge(widget.pubkey);
    if (mounted)
      setState(() {
        _badge = badge;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _badge == null) return const SizedBox.shrink();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return LuxuryBadgeWidget(
      badge: _badge!,
      compact: widget.compact,
      enableAnimations: !disableAnimations && !widget.compact,
    );
  }
}

class AnimatedUserBadge extends StatefulWidget {
  final String pubkey;
  final bool compact;

  const AnimatedUserBadge(
      {super.key, required this.pubkey, this.compact = false});

  @override
  State<AnimatedUserBadge> createState() => _AnimatedUserBadgeState();
}

class _AnimatedUserBadgeState extends State<AnimatedUserBadge>
    with SingleTickerProviderStateMixin {
  BadgeInfo? _badge;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _loadBadge();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AnimatedUserBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pubkey != widget.pubkey) {
      _controller.reset();
      _loadBadge();
    }
  }

  Future<void> _loadBadge() async {
    final badge = await BadgeService.instance.getBadge(widget.pubkey);
    if (mounted && badge != null) {
      setState(() => _badge = badge);
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_badge == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final curve =
            Curves.easeOutCubic.transform(_controller.value.clamp(0.0, 1.0));
        final fade =
            Curves.easeOut.transform((_controller.value * 2).clamp(0.0, 1.0));

        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: 0.92 + 0.08 * curve,
            child: LuxuryBadgeWidget(badge: _badge!, compact: widget.compact),
          ),
        );
      },
    );
  }
}

class BadgeShowcase extends StatelessWidget {
  const BadgeShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: AppRadii.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'GLASS COLLECTION',
            style: AppTypography.mono(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              BadgeInfo.badges[BadgeType.core]!,
              BadgeInfo.badges[BadgeType.owner]!,
              BadgeInfo.badges[BadgeType.patron]!,
              BadgeInfo.badges[BadgeType.benefactor]!,
              BadgeInfo.badges[BadgeType.early]!,
            ].map((b) => LuxuryBadgeWidget(badge: b)).toList(),
          ),
        ],
      ),
    );
  }
}
