// Визуальное превью: экран звонка (этап 3). CallScreen завязан на WebRTC и
// сервисы, поэтому превью собрано из его частей в той же раскладке, что и build().
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/call/background_painters.dart';
import 'package:orpheus_project/widgets/call/call_identity.dart';
import 'package:orpheus_project/widgets/call/control_panel.dart';

import 'stage3_harness.dart';

class _CallPreview extends StatefulWidget {
  const _CallPreview({required this.incoming});
  final bool incoming;

  @override
  State<_CallPreview> createState() => _CallPreviewState();
}

class _CallPreviewState extends State<_CallPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = !widget.incoming;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CallBackground(controller: _c),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Text(
                  'Secure Call',
                  style: AppTypography.mono(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(flex: 2),
                CallAvatar(name: 'Александр', connected: connected),
                const SizedBox(height: 16),
                const Text(
                  'Александр',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  connected ? '00:42 · E2E' : 'Входящий звонок',
                  style: AppTypography.mono(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
                if (connected)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: CallVoiceBars(levels: [0.5, 0.6, 0.7, 0.5, 0.6]),
                  ),
                const Spacer(flex: 3),
                CallControlPanel(
                  isIncoming: widget.incoming,
                  isMicMuted: false,
                  isSpeakerOn: true,
                  onToggleMic: () {},
                  onToggleSpeaker: () {},
                  onEndCall: () {},
                  onAcceptCall: () {},
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(loadStage3Fonts);
  timeDilation = 1.0;

  testWidgets('call_connected', (tester) async {
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(const _CallPreview(incoming: false)));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/call_connected.png'));
  });

  testWidgets('call_incoming', (tester) async {
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(const _CallPreview(incoming: true)));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/call_incoming.png'));
  });
}
