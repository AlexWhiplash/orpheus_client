// Визуальное превью: Профиль (этап 3). Собирается из частей SettingsScreen
// с фейковыми данными — без БД, crypto и BadgeService.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/settings_screen.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

import 'stage3_harness.dart';

const _fakeKey = 'MCowBQYDK2VwAyEAf3a91c20b4ed215Qm9ycGhldXNEZW1vS2V5PT0';

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(l10n.profile),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileIdentityCard(
              myKey: _fakeKey,
              l10n: l10n,
              isCopied: false,
              onCopy: () {},
              onShowQr: () {},
              showBadge: false,
            ),
            const SizedBox(height: 14),
            ProfileStatsGroup(
              stats: const {'contacts': 12, 'messages': 1840, 'sent': 913},
              l10n: l10n,
            ),
            const SizedBox(height: 14),
            ProfileMenuGroups(
              l10n: l10n,
              onShare: () {},
              onBuyPremium: () {},
              onSecurity: () {},
              onSupport: () {},
              onHelp: () {},
              onUpdates: () {},
              onExport: () {},
              onNotifications: () {},
              onLanguage: () {},
            ),
            const SizedBox(height: 14),
            ProfileVersionGroup(
              versionLabel: '1.1.8+53',
              l10n: l10n,
              registrationDate: DateTime(2026, 3, 14),
              onCheckUpdates: () {},
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadStage3Fonts);

  testWidgets('profile', (tester) async {
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(const _ProfilePreview()));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/profile.png'));
  });

  testWidgets('profile_full', (tester) async {
    setStage3Surface(tester, height: 1320);
    await tester.pumpWidget(stage3App(const _ProfilePreview()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/profile_full.png'));
  });

  testWidgets('profile_qr_sheet', (tester) async {
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(Builder(
      builder: (context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppColors.surface,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => MyQrSheet(myKey: _fakeKey, l10n: L10n.of(context)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/profile_qr_sheet.png'));
  });
}
