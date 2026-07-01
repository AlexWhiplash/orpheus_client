import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/help_screen.dart';

void main() {
  testWidgets('HelpScreen: рендерится и показывает ключевые секции',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: Locale('ru'),
      home: HelpScreen(),
    ));

    expect(find.text('Как пользоваться'), findsOneWidget);
    expect(find.text('Быстрый старт'), findsOneWidget);
    expect(find.text('PIN-код'), findsOneWidget);
    expect(find.text('Автоудаление (Auto-wipe)'), findsOneWidget);
  });
}
