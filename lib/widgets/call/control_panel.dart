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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (isIncoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildActionBtn(Icons.call_end, AppColors.danger, l10n.decline.toUpperCase(), onEndCall),
            _buildActionBtn(Icons.call, AppColors.action, l10n.answerCall.toUpperCase(), onAcceptCall),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlBtn(
              icon: isMicMuted ? Icons.mic_off : Icons.mic,
              isActive: isMicMuted,
              label: l10n.microphone,
              onTap: onToggleMic,
            ),
            _buildControlBtn(
              icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              isActive: isSpeakerOn,
              label: l10n.speaker,
              onTap: onToggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildActionBtn(Icons.call_end, AppColors.danger, l10n.endCall.toUpperCase(), onEndCall),
      ],
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required bool isActive,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppColors.actionContainer : AppColors.surface2,
              border: Border.all(
                color: isActive
                    ? AppColors.action.withOpacity(0.45)
                    : AppColors.outline,
                width: 1,
              ),
              boxShadow: AppShadows.bevel(),
            ),
            child: Icon(
              icon,
              size: 28,
              color: isActive ? AppColors.action : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.action : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
              boxShadow: AppShadows.bevel(depth: 2),
            ),
            // Белая иконка допустима только на насыщенной заливке (danger);
            // на мятной кнопке — тёмная onAction.
            child: Icon(
              icon,
              size: 36,
              color: color == AppColors.action ? AppColors.onAction : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTypography.mono(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}