import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/purchase_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';
import 'package:orpheus_project/widgets/app_card.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum _Phase { loadingPlans, choose, creatingInvoice, payment, loadError }

/// In-app license purchase via self-hosted USDT-TRC20 (TRON).
/// No messengers, no third parties — the user pays from their own crypto wallet
/// and the server activates the license from on-chain data. See docs/USDT_TRON_SPEC.md.
class PurchaseScreen extends StatefulWidget {
  /// Called once the payment is confirmed and the license is active.
  final VoidCallback onConfirmed;

  const PurchaseScreen({super.key, required this.onConfirmed});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  _Phase _phase = _Phase.loadingPlans;
  List<Tariff> _tariffs = const [];
  Invoice? _invoice;

  Timer? _pollTimer;
  Timer? _tick;
  StreamSubscription? _wsSub;

  bool _confirmed = false;
  bool _expired = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadTariffs();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tick?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadTariffs() async {
    setState(() => _phase = _Phase.loadingPlans);
    try {
      final tariffs = await PurchaseService.instance.fetchTariffs();
      if (!mounted) return;
      setState(() {
        _tariffs = tariffs;
        _phase = _Phase.choose;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.loadError);
    }
  }

  Future<void> _selectTariff(Tariff t) async {
    final pubkey = cryptoService.publicKeyBase64;
    if (pubkey == null) return;
    setState(() => _phase = _Phase.creatingInvoice);
    try {
      final invoice = await PurchaseService.instance
          .createInvoice(tariffId: t.id, pubkey: pubkey);
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _expired = false;
        _phase = _Phase.payment;
      });
      _startWatching(invoice.orderId);
    } catch (_) {
      if (!mounted) return;
      final l10n = L10n.of(context);
      setState(() => _phase = _Phase.choose);
      _snack(l10n.createInvoiceError);
    }
  }

  void _startWatching(String orderId) {
    _pollTimer?.cancel();
    _tick?.cancel();
    _wsSub?.cancel();

    // Primary confirmation path: poll the server (works even if the WS is down).
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final status = await PurchaseService.instance.getStatus(orderId);
      if (!mounted) return;
      if (status == PurchaseStatus.confirmed) {
        _onConfirmed();
      } else if (status == PurchaseStatus.expired) {
        setState(() => _expired = true);
      }
    });

    // Secondary: react instantly to a server WS push if it arrives.
    _wsSub = websocketService.stream.listen((message) {
      try {
        final data = json.decode(message);
        if (data['type'] == 'payment-confirmed' ||
            (data['type'] == 'license-status' && data['status'] == 'active')) {
          _onConfirmed();
        }
      } catch (_) {}
    });

    // Refresh the countdown once per second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _onConfirmed() async {
    if (_confirmed) return;
    _confirmed = true;
    _pollTimer?.cancel();
    _tick?.cancel();
    _wsSub?.cancel();
    if (!mounted) return;
    final l10n = L10n.of(context);
    await AppDialog.show(
      context: context,
      icon: Icons.verified,
      iconColor: AppColors.success,
      title: l10n.paymentConfirmedTitle,
      content: l10n.paymentConfirmedBody,
      primaryLabel: l10n.ok,
    );
    widget.onConfirmed();
  }

  Future<void> _forceCheck() async {
    final invoice = _invoice;
    if (invoice == null || _checking) return;
    setState(() => _checking = true);
    final status = await PurchaseService.instance.getStatus(invoice.orderId);
    if (!mounted) return;
    setState(() => _checking = false);
    if (status == PurchaseStatus.confirmed) {
      _onConfirmed();
    } else if (status == PurchaseStatus.expired) {
      setState(() => _expired = true);
    } else {
      _snack(L10n.of(context).awaitingPayment);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    _snack(L10n.of(context).copied);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String? _remaining() {
    final exp = _invoice?.expiresAt;
    if (exp == null) return null;
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return '00:00';
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${diff.inHours > 0 ? '${diff.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      appBar: AppBar(title: Text(l10n.premiumPurchaseTitle)),
      body: switch (_phase) {
        _Phase.loadingPlans ||
        _Phase.creatingInvoice =>
          const Center(child: CircularProgressIndicator()),
        _Phase.loadError => _buildLoadError(l10n),
        _Phase.choose => _buildChoose(l10n),
        _Phase.payment => _buildPayment(l10n),
      },
    );
  }

  Widget _buildLoadError(L10n l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 44, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(l10n.plansLoadError,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            AppButton(
              label: l10n.retry,
              icon: Icons.refresh,
              fullWidth: false,
              onPressed: _loadTariffs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoose(L10n l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.choosePlan,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(l10n.choosePlanHint,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (final t in _tariffs) ...[
            _TariffCard(tariff: t, onTap: () => _selectTariff(t)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildPayment(L10n l10n) {
    final invoice = _invoice!;
    final remaining = _remaining();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Amount
          Center(
            child: Column(
              children: [
                Text('${invoice.amountUsdt} USDT',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.action, fontSize: 28)),
                const SizedBox(height: 2),
                Text('USDT · TRC-20 (TRON)',
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Network warning — losing funds on the wrong network is the main footgun.
          AppCard(
            backgroundColor: AppColors.danger.withOpacity(0.10),
            borderColor: AppColors.danger.withOpacity(0.4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.danger, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.paymentNetworkWarning,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // QR of the address
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: AppRadii.md),
              child: QrImageView(
                data: invoice.address,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(l10n.scanQrHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 16),

          // Address + copy
          _CopyRow(
            label: l10n.walletAddress,
            value: invoice.address,
            onCopy: () => _copy(invoice.address),
          ),
          const SizedBox(height: 8),
          _CopyRow(
            label: l10n.amountToPay,
            value: '${invoice.amountUsdt} USDT',
            onCopy: () => _copy(invoice.amountUsdt),
          ),
          const SizedBox(height: 18),

          if (_expired) ...[
            Text(l10n.invoiceExpired,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.danger)),
            const SizedBox(height: 12),
            AppButton(
              label: l10n.newInvoice,
              icon: Icons.refresh,
              onPressed: () => setState(() => _phase = _Phase.choose),
            ),
          ] else ...[
            // Awaiting payment
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(
                  remaining == null
                      ? l10n.awaitingPayment
                      : '${l10n.awaitingPayment}  ·  $remaining',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(l10n.awaitingPaymentHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: l10n.iPaid,
              icon: Icons.check_circle_outline,
              isLoading: _checking,
              onPressed: _forceCheck,
            ),
            const SizedBox(height: 6),
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.tertiary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TariffCard extends StatelessWidget {
  final Tariff tariff;
  final VoidCallback onTap;
  const _TariffCard({required this.tariff, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.lg,
      child: AppCard(
        radius: AppRadii.lg,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.action.withOpacity(0.12),
                borderRadius: AppRadii.sm,
              ),
              child: const Icon(Icons.workspace_premium,
                  color: AppColors.action),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tariff.title,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            Text('${tariff.priceUsdt} USDT',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.action)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  const _CopyRow(
      {required this.label, required this.value, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          AppIconButton(icon: Icons.copy, onPressed: onCopy),
        ],
      ),
    );
  }
}
