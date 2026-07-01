// lib/screens/status_screen.dart
// Системный монитор Orpheus — полезные данные для пользователя

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/pending_actions_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_card.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StatusScreen extends StatefulWidget {
  const StatusScreen({
    super.key,
    this.httpClient,
    this.databaseService,
    this.messageUpdates,
    this.debugPublicKeyBase64,
    this.disableTimersForTesting = false,
  });

  final http.Client? httpClient;
  final DatabaseService? databaseService;
  final Stream<void>? messageUpdates;
  final String? debugPublicKeyBase64;
  final bool disableTimersForTesting;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  http.Client? _ownedHttpClient;
  Timer? _timer;
  StreamSubscription<void>? _updatesSub;

  // Соединение
  int _pendingCount = 0;
  DateTime? _sessionStart;
  int _reconnectCount = 0;

  // Регион
  String _country = '...';
  String _countryCode = '--';
  bool _isTrafficControlRegion = false;

  // Безопасность
  String _fingerprint = '...';
  DateTime? _keyCreatedAt;

  // Устройство
  String _appVersion = '...';
  String _deviceModel = '...';
  String _osVersion = '...';

  // Хранилище
  int _messagesCount = 0;
  int _contactsCount = 0;

  DatabaseService get _db =>
      widget.databaseService ?? DatabaseService.instance;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _ownedHttpClient = widget.httpClient == null ? http.Client() : null;
    _sessionStart = DateTime.now();

    _loadAll();

    if (!widget.disableTimersForTesting) {
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    }

    _updatesSub =
        (widget.messageUpdates ?? messageUpdateController.stream.map((_) {}))
            .listen((_) => _loadStorage());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _updatesSub?.cancel();
    _ownedHttpClient?.close();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait<void>([
      _loadRegion(),
      _loadPending(),
      _loadSecurity(),
      _loadDevice(),
      _loadStorage(),
    ]);
  }

  void _tick() {
    _loadPending();
    if (mounted) setState(() {});
  }

  Future<void> _loadRegion() async {
    final client = widget.httpClient ?? _ownedHttpClient ?? http.Client();
    try {
      final resp = await client
          .get(Uri.parse('http://ip-api.com/json/'))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) throw Exception();
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final country = (data['country'] as String?)?.trim() ?? 'Unknown';
      final code =
          ((data['countryCode'] as String?)?.trim() ?? '--').toUpperCase();

      if (!mounted) return;
      setState(() {
        _country = country;
        _countryCode = code;
        _isTrafficControlRegion = _trafficControlCountries.contains(code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _country = 'Unknown';
        _countryCode = '--';
      });
    }
  }

  Future<void> _loadPending() async {
    try {
      final pending = await PendingActionsService.getPendingMessages();
      if (!mounted) return;
      setState(() => _pendingCount = pending.length);
    } catch (_) {}
  }

  Future<void> _loadSecurity() async {
    try {
      final crypto = CryptoService.instance;
      await crypto.init();

      final pubKey = widget.debugPublicKeyBase64 ?? crypto.publicKeyBase64;
      final regDate = crypto.registrationDate;

      if (!mounted) return;
      setState(() {
        // Fingerprint — последние 8 символов публичного ключа
        if (pubKey != null && pubKey.length >= 8) {
          _fingerprint = pubKey.substring(pubKey.length - 8).toUpperCase();
        } else {
          _fingerprint = '--------';
        }
        _keyCreatedAt = regDate;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _fingerprint = '---');
    }
  }

  Future<void> _loadDevice() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = DeviceInfoPlugin();

      String model = '---';
      String os = '---';

      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        model = '${android.manufacturer} ${android.model}';
        os = 'Android ${android.version.release}';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        model = ios.utsname.machine;
        os = '${ios.systemName} ${ios.systemVersion}';
      }

      if (!mounted) return;
      setState(() {
        _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
        _deviceModel = model;
        _osVersion = os;
      });
    } catch (_) {}
  }

  Future<void> _loadStorage() async {
    try {
      final stats = await _db.getProfileStats();
      if (!mounted) return;
      setState(() {
        _messagesCount = stats['messages'] ?? 0;
        _contactsCount = stats['contacts'] ?? 0;
      });
    } catch (_) {}
  }

  String _formatUptime() {
    if (_sessionStart == null) return '--';
    final diff = DateTime.now().difference(_sessionStart!);
    if (diff.inHours > 0) {
      return '${diff.inHours}ч ${diff.inMinutes % 60}м';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}м';
    }
    return '${diff.inSeconds}с';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '---';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  void _copyFingerprint() {
    final l10n = L10n.of(context);
    Clipboard.setData(ClipboardData(text: _fingerprint));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.fingerprintCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(title: Text(l10n.system)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ═══════════════════════════════════════════════════════════
          // СОЕДИНЕНИЕ
          // ═══════════════════════════════════════════════════════════
          _ConnectionCard(
            pulse: _pulseController,
            pendingCount: _pendingCount,
            uptime: _formatUptime(),
            l10n: l10n,
          ),
          const SizedBox(height: 12),

          // ═══════════════════════════════════════════════════════════
          // РЕГИОН + РЕЖИМ (в строку)
          // ═══════════════════════════════════════════════════════════
          Row(
            children: [
              Expanded(
                child: _InfoCard(
                  title: l10n.region,
                  icon: Icons.public_rounded,
                  value: _countryCode,
                  subtitle: _country,
                  secondaryValue: l10n.regionLocalOnly,
                  valueColor: _isTrafficControlRegion
                      ? AppColors.warning
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoCard(
                  title: l10n.mode,
                  icon: _isTrafficControlRegion
                      ? Icons.shield_rounded
                      : Icons.verified_user_rounded,
                  value: _isTrafficControlRegion ? l10n.enhanced : l10n.standard,
                  subtitle: _isTrafficControlRegion
                      ? l10n.enhancedProtection
                      : l10n.stableConnection,
                  valueColor: _isTrafficControlRegion
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ═══════════════════════════════════════════════════════════
          // БЕЗОПАСНОСТЬ
          // ═══════════════════════════════════════════════════════════
          _SecurityCard(
            fingerprint: _fingerprint,
            createdAt: _formatDate(_keyCreatedAt),
            onCopy: _copyFingerprint,
            l10n: l10n,
          ),
          const SizedBox(height: 12),

          // ═══════════════════════════════════════════════════════════
          // ХРАНИЛИЩЕ + УСТРОЙСТВО (в строку)
          // ═══════════════════════════════════════════════════════════
          Row(
            children: [
              Expanded(
                child: _InfoCard(
                  title: l10n.storage,
                  icon: Icons.storage_rounded,
                  value: '$_messagesCount',
                  subtitle: l10n.messagesLabel,
                  secondaryValue: '$_contactsCount ${l10n.contactsLabel}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoCard(
                  title: l10n.application,
                  icon: Icons.info_outline_rounded,
                  value: 'v$_appVersion',
                  subtitle: _osVersion,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ═══════════════════════════════════════════════════════════
          // УСТРОЙСТВО (полное)
          // ═══════════════════════════════════════════════════════════
          _DeviceCard(
            model: _deviceModel,
            os: _osVersion,
            appVersion: _appVersion,
            l10n: l10n,
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ВИДЖЕТЫ КАРТОЧЕК
// ═══════════════════════════════════════════════════════════════════════════

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.pulse,
    required this.pendingCount,
    required this.uptime,
    required this.l10n,
  });

  final Animation<double> pulse;
  final int pendingCount;
  final String uptime;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return StreamBuilder<ConnectionStatus>(
      stream: websocketService.status,
      initialData: websocketService.currentStatus,
      builder: (context, snap) {
        final status = snap.data ?? ConnectionStatus.Disconnected;
        final (label, color, icon) = switch (status) {
          ConnectionStatus.Connected => (
              l10n.connected,
              AppColors.success,
              Icons.cloud_done_rounded
            ),
          ConnectionStatus.Connecting => (
              l10n.connecting,
              AppColors.warning,
              Icons.cloud_sync_rounded
            ),
          ConnectionStatus.Disconnected => (
              l10n.disconnected,
              AppColors.danger,
              Icons.cloud_off_rounded
            ),
        };

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: pulse,
                    builder: (context, _) {
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12 + 0.08 * pulse.value),
                          borderRadius: AppRadii.sm,
                        ),
                        child: Icon(icon, color: color, size: 22),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.connection,
                            style: t.labelMedium
                                ?.copyWith(color: AppColors.textTertiary)),
                        const SizedBox(height: 2),
                        Text(label,
                            style: t.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${l10n.session}: $uptime',
                          style: t.labelSmall
                              ?.copyWith(color: AppColors.textTertiary)),
                      const SizedBox(height: 2),
                      Text('${l10n.queue}: $pendingCount',
                          style: t.labelSmall
                              ?.copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: AppRadii.sm,
                ),
                child: Row(
                  children: [
                    Icon(Icons.dns_rounded,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        websocketService.currentHost,
                        style: t.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.value,
    required this.subtitle,
    this.valueColor,
    this.secondaryValue,
  });

  final String title;
  final IconData icon;
  final String value;
  final String subtitle;
  final Color? valueColor;
  final String? secondaryValue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(title,
                  style:
                      t.labelMedium?.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style: t.bodySmall?.copyWith(color: AppColors.textTertiary)),
          if (secondaryValue != null) ...[
            const SizedBox(height: 2),
            Text(secondaryValue!,
                style: t.labelSmall?.copyWith(color: AppColors.textTertiary)),
          ],
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({
    required this.fingerprint,
    required this.createdAt,
    required this.onCopy,
    required this.l10n,
  });

  final String fingerprint;
  final String createdAt;
  final VoidCallback onCopy;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: AppRadii.sm,
                ),
                child:
                    const Icon(Icons.key_rounded, color: AppColors.success, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.encryption,
                        style: t.labelMedium
                            ?.copyWith(color: AppColors.textTertiary)),
                    const SizedBox(height: 2),
                    Text('X25519 + ChaCha20-Poly1305',
                        style:
                            t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: l10n.copyFingerprint,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SecurityItem(
                  label: l10n.fingerprint,
                  value: fingerprint,
                  isMono: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SecurityItem(
                  label: l10n.keyCreated,
                  value: createdAt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: AppRadii.sm,
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.e2eActive,
                    style: t.labelSmall?.copyWith(color: AppColors.success),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityItem extends StatelessWidget {
  const _SecurityItem({
    required this.label,
    required this.value,
    this.isMono = false,
  });

  final String label;
  final String value;
  final bool isMono;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: t.labelSmall?.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: t.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontFamily: isMono ? 'monospace' : null,
            letterSpacing: isMono ? 1.5 : null,
          ),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.model,
    required this.os,
    required this.appVersion,
    required this.l10n,
  });

  final String model;
  final String os;
  final String appVersion;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smartphone_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(l10n.device,
                  style:
                      t.labelMedium?.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 12),
          _DeviceRow(label: l10n.model, value: model),
          const SizedBox(height: 8),
          _DeviceRow(label: l10n.osLabel, value: os),
          const SizedBox(height: 8),
          _DeviceRow(label: 'Orpheus', value: 'v$appVersion'),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: t.bodySmall?.copyWith(color: AppColors.textTertiary)),
        ),
        Expanded(
          child: Text(value,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

// Страны с ограничениями трафика
const Set<String> _trafficControlCountries = <String>{
  'RU', 'BY', 'CN', 'IR', 'KP', 'SY', 'TM', 'AF', 'CU', 'VE',
};
