import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/widgets/call/control_panel.dart';

void main() {
  group('CallControlPanel widget tests', () {
    testWidgets('Incoming: показывает ОТКЛОНИТЬ/ОТВЕТИТЬ и вызывает callbacks', (tester) async {
      var ended = 0;
      var accepted = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: CallControlPanel(
              isIncoming: true,
              onToggleMic: () {},
              onToggleSpeaker: () {},
              onEndCall: () => ended++,
              onAcceptCall: () => accepted++,
            ),
          ),
        ),
      );

      expect(find.text('ОТКЛОНИТЬ'), findsOneWidget);
      expect(find.text('ОТВЕТИТЬ'), findsOneWidget);
      expect(find.text('ЗАВЕРШИТЬ'), findsNothing);

      // Реальный UX: пользователь жмёт на круглую кнопку (иконку), а не на подпись.
      await tester.tap(find.byIcon(Icons.call_end));
      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();

      expect(ended, 1);
      expect(accepted, 1);
    });

    testWidgets('Outgoing: показывает Микрофон/Динамик/ЗАВЕРШИТЬ и вызывает callbacks', (tester) async {
      var mic = 0;
      var speaker = 0;
      var end = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: CallControlPanel(
              isIncoming: false,
              isMicMuted: false,
              isSpeakerOn: false,
              onToggleMic: () => mic++,
              onToggleSpeaker: () => speaker++,
              onEndCall: () => end++,
              onAcceptCall: () {},
            ),
          ),
        ),
      );

      expect(find.text('Микрофон'), findsOneWidget);
      expect(find.text('Динамик'), findsOneWidget);
      expect(find.text('ЗАВЕРШИТЬ'), findsOneWidget);
      expect(find.text('ОТВЕТИТЬ'), findsNothing);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.tap(find.byIcon(Icons.volume_down));
      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pump();

      expect(mic, 1);
      expect(speaker, 1);
      expect(end, 1);
    });
  });
}


