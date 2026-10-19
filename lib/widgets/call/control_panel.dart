import 'package:flutter/material.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

class CallControlPanel extends StatelessWidget {
  final bool isIncoming;
  final bool isMicMuted;
  final bool isSpeakerOn;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;
  final VoidCallback onAcceptCall;

  const CallControlPanel({
    super.key,
    required this.isIncoming,
    this.isMicMuted = false,
    this.isSpeakerOn = false,
    required this.onToggleMic,
    required this.onToggleSpeaker,
    required this.onEndCall,
    required this.onAcceptCall, // Используется только если isIncoming
  });

  /// Размер круглой кнопки (визуальная система Orpheus v1: три равные кнопки в ряд).
  static const double _btnSize = 68;

  /// Тёмная иконка на красной заливке «завершить» — как в концепте, без белого блика.
  static const Color _onDanger = Color(0xFF2A0D0D);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (isIncoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildActionBtn(Icons.call_end, AppColors.danger, l10n.decline.toUpperCase(), onEndCall),
            _buildActionBtn(Icons.call, AppColors.action, l10n.answerCall.toUpperCase(), onAcceptCall),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildControlBtn(
              icon: isMicMuted ? Icons.mic_off : Icons.mic,
              isActive: isMicMuted,
              label: l10n.microphone,
              onTap: onToggleMic,
            ),
          ),
          Expanded(
            child: _buildActionBtn(Icons.call_end, AppColors.danger, l10n.endCall.toUpperCase(), onEndCall),
          ),
          Expanded(
            child: _buildControlBtn(
              icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              isActive: isSpeakerOn,
              label: l10n.speaker,
              onTap: onToggleSpeaker,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required bool isActive,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: _btnSize,
            height: _btnSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppColors.actionContainer : AppColors.surface2,
              border: Border.all(
                color: isActive
                    ? AppColors.action.withOpacity(0.35)
                    : AppColors.outline,
                width: 1,
              ),
              boxShadow: AppShadows.bevel(),
            ),
            child: Icon(
              icon,
              size: 26,
              color: isActive ? AppColors.action : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? AppColors.action : AppColors.textTertiary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: _btnSize,
            height: _btnSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: AppShadows.bevel(),
            ),
            // На мятной кнопке — тёмная onAction, на красной — тёмно-бордовая.
            child: Icon(
              icon,
              size: 30,
              color: color == AppColors.action ? AppColors.onAction : _onDanger,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.mono(
            color: AppColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
