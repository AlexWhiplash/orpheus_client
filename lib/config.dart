import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // Final Release 1.0.0
  static const String appVersion = "v1.1.8";

  // Тест-сборки: писать все логи в файл (переживает рестарт) + перехват print +
  // шаринг из экрана отладки. Перед РЕАЛЬНЫМ релизом ставить false — persist-логи
  // наружу не нужны (privacy).
  static const bool debugFileLogging = true;

  // === HOST ===
  // Production host (default) and the separate TEST backend used by QA. The active
  // host is switchable at runtime (test builds only, see LicenseScreen) so server
  // changes can be validated end-to-end without hitting prod. primaryApiHost stays
  // the built-in default and reset target; only these two hosts are ever allowed.
  static const String primaryApiHost = 'api.orpheus.click';
  static const String testApiHost = 'dev.orpheus.click';
  static const List<String> allowedHosts = [primaryApiHost, testApiHost];

  /// SharedPreferences key for the persisted active host. Written from the UI
  /// isolate and re-read in the push isolate (both isolates hydrate _activeHost).
  static const String kPrefActiveHost = 'runtime_api_host';

  // Runtime active host. Defaults to prod; overridden by loadActiveHost() at
  // startup and by setActiveHost() when a tester switches servers.
  static String _activeHost = primaryApiHost;

  /// Active host. Kept as `serverIp` (name unchanged) so every existing call site
  /// that builds a URL via httpUrl/webSocketUrl follows the runtime host with no edit.
  static String get serverIp => _activeHost;

  /// API host list (single active entry). Named `apiHosts` (unchanged) so WS/push
  /// host selection and the httpUrls/webSocketUrls fallback iterators follow the
  /// runtime host as well.
  static List<String> get apiHosts => [_activeHost];

  /// True when a non-production host is active (drives the "TEST SERVER" banner).
  static bool get isTestHost => _activeHost != primaryApiHost;

  /// Hydrate _activeHost from an already-loaded SharedPreferences. Only hosts on
  /// the allowlist are accepted; anything else falls back to prod. Returns the
  /// resolved host. Used at startup and inside the push isolate (after reload()).
  static Future<String> reloadActiveHostFromPrefs(SharedPreferences prefs) async {
    final h = prefs.getString(kPrefActiveHost);
    _activeHost = (h != null && allowedHosts.contains(h)) ? h : primaryApiHost;
    return _activeHost;
  }

  /// Load the persisted active host. Call in main() BEFORE any service connects.
  static Future<void> loadActiveHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await reloadActiveHostFromPrefs(prefs);
    } catch (_) {}
  }

  /// Switch the active host (in-memory + persisted). Hosts outside the allowlist
  /// are ignored. Callers must force a WebSocket reconnect for it to take effect.
  static Future<void> setActiveHost(String host) async {
    if (!allowedHosts.contains(host)) return;
    _activeHost = host;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefActiveHost, host);
    } catch (_) {}
  }

  /// Reset the active host back to production (used by panic-wipe / duress).
  static Future<void> resetHostToProd() => setActiveHost(primaryApiHost);

  // --- Ready URLs ---
  /// [service] — сокет push-изолята (`?role=svc`): сервер доставляет в него
  /// кадры, но НЕ учитывает его в презенсе, иначе «онлайн» значил бы «телефон
  /// включён» (постоянный сервис держит сокет и при убитом приложении).
  static String webSocketUrl(String publicKey, {String? host, bool service = false}) {
    final encodedPublicKey = Uri.encodeComponent(publicKey);
    final h = host ?? serverIp;
    return 'wss://$h/ws/$encodedPublicKey${service ? '?role=svc' : ''}';
  }

  static String httpUrl(String path, {String? host}) {
    final h = host ?? serverIp;
    return 'https://$h$path';
  }

  /// List of URLs (across all hosts) for safe fallback.
  static Iterable<String> httpUrls(String path) sync* {
    for (final h in apiHosts) {
      yield httpUrl(path, host: h);
    }
  }

  static Iterable<String> webSocketUrls(String publicKey) sync* {
    for (final h in apiHosts) {
      yield webSocketUrl(publicKey, host: h);
    }
  }

  // --- Update History (Changelog) ---
  //
  // IMPORTANT (project policy):
  // - User-facing "What's New" / changelog should NOT be maintained in the client.
  // - Single source of truth for release notes: admin panel ORPHEUS_ADMIN -> "Versions" section.
  // - Currently client loads release notes from public admin API:
  //   https://api.orpheus.click/api/public/releases (with fallback to legacy host)
  // - Offline-safe fallback ONLY: shown when the server is unreachable or returns
  //   an empty list. The full, current changelog (RU) comes from the API above.
  // - Keep this a single generic placeholder (auto-follows appVersion); do NOT
  //   maintain a per-version history here - the admin panel is the source of truth.
  static const List<Map<String, dynamic>> changelogData = [
    {
      'version': appVersion,
      'date': '—',
      'changes': [
        'Полная история обновлений появится онлайн при подключении к сети.',
      ]
    },
  ];
}