// Общая обвязка визуальных превью этапа 3 (профиль, безопасность, PIN, звонок).
// Не тест (нет суффикса _test) — подключается из *_preview_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/theme/app_theme.dart';

bool _fontsLoaded = false;

/// Inter + IBM Plex Mono + Material Icons из ассетов, чтобы текст и иконки
/// рисовались настоящими шрифтами, а не Ahem-квадратами.
Future<void> loadStage3Fonts() async {
  if (_fontsLoaded) return;
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }

  await family('Inter', [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
    'assets/fonts/Inter-SemiBold.ttf',
    'assets/fonts/Inter-Bold.ttf',
  ]);
  await family('IBM Plex Mono', [
    'assets/fonts/IBMPlexMono-Regular.ttf',
    'assets/fonts/IBMPlexMono-Medium.ttf',
  ]);
  await family('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
  _fontsLoaded = true;
}

/// Экран 412 x [height] dp при DPR 2.
void setStage3Surface(WidgetTester tester, {double height = 915}) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(412 * 2, height * 2);
  addTearDown(tester.view.reset);
}

Widget stage3App(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: home,
    );

class MemSecureStorage implements AuthSecureStorage {
  final Map<String, String> _m = {};

  @override
  Future<void> delete({required String key}) async => _m.remove(key);

  @override
  Future<void> deleteAll() async => _m.clear();

  @override
  Future<String?> read({required String key}) async => _m[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      _m[key] = value;
}

Future<AuthService> stage3Auth() async {
  final auth = AuthService.createForTesting(
      secureStorage: MemSecureStorage(),
      fastHash: true,
      monotonicNow: () async => 0);
  await auth.init();
  return auth;
}

/// Подгрузить картинки-ассеты (знак) до снимка.
Future<void> precacheStage3Assets(WidgetTester tester) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(() async {
    await precacheImage(const AssetImage('assets/images/logo_mark.png'), ctx);
  });
  await tester.pump();
}
