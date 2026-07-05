class AppConfig {
  // Final Release 1.0.0
  static const String appVersion = "v1.1.7";

  // Тест-сборки: писать все логи в файл (переживает рестарт) + перехват print +
  // шаринг из экрана отладки. Перед РЕАЛЬНЫМ релизом ставить false — persist-логи
  // наружу не нужны (privacy).
  static const bool debugFileLogging = true;

  // === HOST ===
  static const String primaryApiHost = 'api.orpheus.click';

  /// API host list (single entry; legacy twc1 domain removed for privacy).
  static const List<String> apiHosts = [
    primaryApiHost,
  ];

  static const String serverIp = primaryApiHost;
  // static const String serverIp = '10.0.2.2:8000'; // For local tests

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