import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/services/apk_download_service.dart';

class UpdateService {
  static bool _isUpdateDialogShown = false;

  static const Duration _networkTimeout = Duration(seconds: 5);

  // ===== Test hooks (DI/overrides) =====
  @visibleForTesting
  static int? debugCurrentBuildNumberOverride;

  /// Override для HTTP GET (например, чтобы симулировать timeout первого хоста и success второго).
  @visibleForTesting
  static Future<http.Response> Function(Uri uri)? debugHttpGet;

  /// Override для launchUrl (чтобы не дергать платформенный плагин в тестах).
  @visibleForTesting
  static Future<bool> Function(Uri url, {LaunchMode mode})? debugLaunchUrl;

  /// Сбросить флаги/override’ы между тестами.
  @visibleForTesting
  static void debugResetForTesting() {
    _isUpdateDialogShown = false;
    debugCurrentBuildNumberOverride = null;
    debugHttpGet = null;
    debugLaunchUrl = null;
  }

  @visibleForTesting
  static Future<http.Response?> debugGetWithFallbackForTesting(String path) {
    return _getWithFallback(path);
  }

  static Future<int> _getCurrentBuildNumber() async {
    final override = debugCurrentBuildNumberOverride;
    if (override != null) return override;

    // 1. Узнаем свою версию (из pubspec.yaml, цифра после +)
    final packageInfo = await PackageInfo.fromPlatform();
    return int.tryParse(packageInfo.buildNumber) ?? 0;
  }

  // Главный метод проверки
  static Future<void> checkForUpdate(BuildContext context, {bool showNoUpdateFeedback = false}) async {
    if (_isUpdateDialogShown) return; // Не спамить окнами

    try {
      final currentBuildNumber = await _getCurrentBuildNumber();

      print("UPDATE: Текущая сборка: $currentBuildNumber");

      // 2. Спрашиваем сервер
      // Запрос идет к API, которое читает версию из БД
      final response = await _getWithFallback('/api/check-update');

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);

        // Стараемся быть устойчивыми к типам (int vs string).
        final serverBuildNumberRaw = data['version_code'];
        final serverBuildNumber = switch (serverBuildNumberRaw) {
          int v => v,
          String v => int.tryParse(v) ?? 0,
          _ => 0,
        };
        final downloadUrl = (data['download_url'] ?? '').toString();
        final versionName = (data['version_name'] ?? '').toString();
        final isRequired = (data['required'] == true);

        print("UPDATE: Версия на сервере: $serverBuildNumber");

        // 3. Если на сервере версия больше -> предлагаем обновить
        if (serverBuildNumber > currentBuildNumber) {
          if (context.mounted) {
            _showUpdateDialog(context, versionName, downloadUrl, isRequired, serverBuildNumber);
          }
        } else if (showNoUpdateFeedback && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.of(context).updateUpToDate),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print("UPDATE ERROR: $e");
    }
  }

  /// Запрос с fallback по списку `AppConfig.apiHosts`.
  /// Возвращает первый успешный ответ (HTTP 200..499/500 тоже как ответ),
  /// либо null если не удалось достучаться ни до одного хоста.
  static Future<http.Response?> _getWithFallback(String path) async {
    final httpGet = debugHttpGet ?? http.get;
    for (final urlStr in AppConfig.httpUrls(path)) {
      try {
        final uri = Uri.parse(urlStr);
        final resp = await httpGet(uri).timeout(_networkTimeout);
        return resp;
      } catch (_) {
        // пробуем следующий хост
        continue;
      }
    }
    return null;
  }

  static String resolveDownloadUrl(String urlPath) {
    // HTTPS обязателен: cleartext заблокирован дефолтом и небезопасен для APK.
    // Абсолютный https:// берём как есть; http:// апгрейдим до https:// (тот же хост),
    // а не принимаем молча.
    if (urlPath.startsWith("https://")) {
      return urlPath;
    }
    if (urlPath.startsWith("http://")) {
      return urlPath.replaceFirst("http://", "https://");
    }
    // Относительные ссылки резолвим через текущий serverIp (httpUrl уже даёт https).
    return AppConfig.httpUrl(urlPath);
  }

  static void _showUpdateDialog(BuildContext context, String version, String urlPath, bool required, int targetBuild) {
    _isUpdateDialogShown = true;

    // Формируем полную ссылку
    String fullUrl = resolveDownloadUrl(urlPath);

    // Получаем локализацию
    final l10n = L10n.of(context);

    showDialog(
      context: context,
      barrierDismissible: !required, // Блокируем закрытие, если обновление обязательно
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.grey)),
        title: Text(l10n.updateAvailable, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Text(
          required ? l10n.updateMessageRequired(version) : l10n.updateMessageOptional(version),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          if (!required)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _isUpdateDialogShown = false;
              },
              child: Text(l10n.updateLater, style: const TextStyle(color: Colors.grey)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB0BEC5)),
            onPressed: () async {
              // Try to download and install APK in-app first
              // If it fails, fallback to browser
              await _downloadAndInstallApk(context, fullUrl, required, targetBuild);
            },
            child: Text(l10n.updateDownload, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Download and install APK in-app with fallback to browser
  static Future<void> _downloadAndInstallApk(BuildContext context, String url, bool required, int targetBuild) async {
    print('UPDATE: Attempting in-app APK download from $url');

    // Второй барьер против даунгрейда/переустановки: ставим только если целевая сборка
    // строго новее текущей. checkForUpdate уже это гарантирует, но URL не привязан к
    // версии — защита переживает будущие рефакторинги и серверный баг выбора версии.
    final currentBuild = await _getCurrentBuildNumber();
    if (targetBuild <= currentBuild) {
      print('UPDATE: Refusing downgrade/reinstall: target=$targetBuild current=$currentBuild');
      return;
    }

    try {
      // Check if we can install APK in-app (checks permission too).
      // This may open system settings and send app to background,
      // so we wait for app to stabilize after permission grant.
      final canInstallInApp = await ApkDownloadService.canInstallApkInApp();

      if (!canInstallInApp) {
        print('UPDATE: Cannot install in-app (permission denied or unsupported)');
        if (context.mounted) {
          _showFallbackDialog(context, url, required);
        }
        return;
      }

      // Wait for app to return from permission screen and stabilize
      await Future.delayed(const Duration(milliseconds: 800));

      // Show progress dialog
      if (!context.mounted) return;

      final progressNotifier = ValueNotifier<double>(0.0);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.grey),
              ),
              title: Text(
                L10n.of(context).updateDownloading,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB0BEC5)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // Download APK
      final result = await ApkDownloadService.downloadApk(
        url,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
      );

      // Dispose notifier
      progressNotifier.dispose();

      // Close progress dialog
      if (context.mounted) {
        Navigator.pop(context); // Close progress dialog
      }

      if (!result.success) {
        print('UPDATE: Download failed: ${result.error}');
        if (context.mounted) {
          _showFallbackDialog(context, url, required);
        }
        return;
      }

      print('UPDATE: Download successful, attempting to install');

      // Install APK
      final installed = await ApkDownloadService.installApk(result.filePath!);

      if (!installed) {
        print('UPDATE: Installation failed, retrying with intent');
        // Retry once with a small delay (system might need time after permission grant)
        await Future.delayed(const Duration(milliseconds: 500));
        final retryInstall = await ApkDownloadService.installApk(result.filePath!);
        if (!retryInstall) {
          print('UPDATE: Retry also failed');
          if (context.mounted) {
            _showFallbackDialog(context, url, required);
          }
          return;
        }
      }

      print('UPDATE: APK installation initiated successfully');

      // Системное окно "Установить?" сейчас поднято (его показывает InstallStatusReceiver).
      // Сообщаем честно, а не делаем вид, что обновление уже применено.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).updateConfirmInstall),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Close update dialog after successful installation start
      if (!required && context.mounted) {
        Navigator.pop(context);
        _isUpdateDialogShown = false;
      }

      // Do NOT clean up APKs here — the system installer is still reading the file.
      // Cleanup happens at the start of the next download in ApkDownloadService.downloadApk().

    } catch (e, stackTrace) {
      print('UPDATE: Unexpected error during download: $e');
      print('UPDATE: Stack trace: $stackTrace');

      if (context.mounted) {
        _showFallbackDialog(context, url, required);
      }
    }
  }

  /// Show dialog when in-app install fails, offering browser as explicit choice
  static void _showFallbackDialog(BuildContext context, String url, bool required) {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.grey),
        ),
        title: Text(l10n.updateInstallError, style: const TextStyle(color: Colors.white)),
        content: Text(l10n.updateInstallErrorMessage, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!required) {
                Navigator.pop(context); // Close update dialog too
                _isUpdateDialogShown = false;
              }
            },
            child: Text(l10n.updateLater, style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB0BEC5)),
            onPressed: () async {
              Navigator.pop(ctx);
              await _launchBrowser(url);
              if (!required && context.mounted) {
                Navigator.pop(context);
                _isUpdateDialogShown = false;
              }
            },
            child: Text(l10n.updateOpenBrowser, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Future<void> _launchBrowser(String urlString) async {
    final Uri url = Uri.parse(urlString);
    // Открываем во внешнем браузере, чтобы скачивание прошло надежно
    final launcher = debugLaunchUrl ?? launchUrl;
    if (!await launcher(url, mode: LaunchMode.externalApplication)) {
      print('Could not launch $url');
    }
  }
}