import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // Final Release 1.0.0
  static const String appVersion = "v1.1.7";

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
  static String webSocketUrl(String publicKey, {String? host}) {
    final encodedPublicKey = Uri.encodeComponent(publicKey);
    final h = host ?? serverIp;
    return 'wss://$h/ws/$encodedPublicKey';
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
  // - This list is kept as fallback (offline-safe) and may be removed later.
  // - DO NOT add new entries here.
  static const List<Map<String, dynamic>> changelogData = [
    {
      'version': '1.1.4',
      'date': '25.02.2026',
      'changes': [
        'SECURITY: Hardened network configuration, removed redundant endpoints.',
        'FIX: Account export now falls back to app PIN when biometrics unavailable.',
        'NEW: Multi-select messages for batch delete (long-press or menu).',
        'FIX: Call messages can now be selected and deleted.',
        'FIX: Single tap on call pill no longer auto-redials.',
        'FIX: Call status messages no longer duplicate.',
        'UI: Compact inline call status pills.',
        'PRIVACY: Region data is local-only, never transmitted to servers.',
        'CORE: Centralized wipe handler for all wipe paths.',
        'L10N: Improved interface localization (EN + RU).',
      ]
    },
    {
      'version': '1.1.0',
      'date': '12.12.2025',
      'changes': [
        'SECURITY: PIN code (6 digits) - optional entry protection.',
        'SECURITY: Duress code - second PIN that shows empty profile.',
        'SECURITY: Wipe code - hold confirmation, protection from accidental deletion.',
        'SECURITY: Auto-wipe after N failed attempts (optional).',
        'UI: "How to Use" screen - simple guide on features and risks.',
        'FIX: Call behavior stabilization: lock screen does not interfere with answering/talking.',
      ]
    },
    {
      'version': '1.0.0',
      'date': '09.12.2025',
      'changes': [
        'RELEASE: Orpheus 1.0.0 Final Release!',
        'NETWORK: Full call support in sleep mode. Incoming calls work even if phone is locked or app is terminated.',
        'NEW: "System Monitor" screen. Network stability graphs, ping and encryption status in real-time.',
        'NEW: New navigation: Contacts, System, Profile.',
        'CORE: ICE Buffering system. Fixed connection issue when answering call from Push notification.',
        'UI: Updated profile and QR card design.',
        'UI: Custom app icon and splash screen with logo.',
        'UI: Message input field now supports multiline text.',
        'UI: Encryption animation when sending messages.',
        'FIX: Fixed call duplication errors.',
        'FIX: Improved WebSocket connection stability.',
      ]
    },
    {
      'version': '0.9.0-Beta',
      'date': '01.12.2025',
      'changes': [
        'CALLS: Improved signaling system for WebRTC calls via WebSocket.',
        'CALLS: Implemented ICE candidate buffering for incoming calls.',
        'CALLS: Added system messages about calls to chat history.',
        'UI: Completely redesigned call screen with animations and audio wave visualization.',
        'UI: Real-time call duration display.',
        'DEBUG: Added debug mode with WebRTC and signaling logs in UI.',
      ]
    },
    {
      'version': '0.8-Beta',
      'date': '25.11.2025',
      'changes': [
        'CALLS: Full call stabilization (TURN 2.0).',
        'CALLS: Now shows contact name during call, not the key.',
        'NEW: Built-in app update system.',
        'NEW: QR code scanner for quick contact exchange.',
        'FIX: Fixed crashes on Android 11+.',
      ]
    },
    {
      'version': '0.7-Alpha',
      'date': '21.11.2025',
      'changes': [
        'DESIGN: New "Dark Premium" style (Black/Silver).',
        'SECURITY: Screenshot and screen recording prevention.',
        'SECURITY: Biometric protection (fingerprint/face) for key export.',
        'NEW: License activation with promo code.',
        'UX: Convenient ID card with "Share" button.',
      ]
    },
    {
      'version': '0.6-Alpha',
      'date': '19.11.2025',
      'changes': [
        'NEW: Push notifications! Now you will know about messages even if the app is closed.',
        'UI: Unread message counters in contact list.',
        'UI: Delivery status checkmarks in chat.',
        'FIX: Improved connection stability (auto-reconnect).',
      ]
    },
    {
      'version': '0.5-Alpha',
      'date': 'Initial Release',
      'changes': [
        'Base version release.',
        'Anonymous calls (WebRTC) and chats.',
        'X25519/ChaCha20 encryption.',
      ]
    },
  ];
}