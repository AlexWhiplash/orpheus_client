import 'package:flutter/material.dart';

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
    if (isIncoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildActionBtn(Icons.call_end, Colors.red, "ОТКЛОНИТЬ", onEndCall),
            _buildActionBtn(Icons.call, Colors.green, "ОТВЕТИТЬ", onAcceptCall),
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
              label: "Микрофон",
              onTap: onToggleMic,
            ),
            _buildControlBtn(
              icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              isActive: isSpeakerOn,
              label: "Динамик",
              onTap: onToggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 40),
        _buildActionBtn(Icons.call_end, Colors.redAccent, "ЗАВЕРШИТЬ", onEndCall),
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
              color: isActive ? Colors.white : Colors.white.withOpacity(0.1),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF6AD394).withOpacity(0.5)
                    : Colors.white.withOpacity(0.2),
                width: 2,
              ),
              boxShadow: isActive
                  ? [BoxShadow(color: const Color(0xFF6AD394).withOpacity(0.4), blurRadius: 20, spreadRadius: 2)]
                  : [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 1)],
            ),
            child: Icon(icon, size: 28, color: isActive ? Colors.black : Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? const Color(0xFF6AD394) : Colors.grey,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
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
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.5), blurRadius: 25, spreadRadius: 3)
              ],
            ),
            child: Icon(icon, size: 36, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}