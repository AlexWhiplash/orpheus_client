import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для работы с настройками устройства.
/// Особенно важен для китайских производителей (Xiaomi, Vivo, Oppo, Huawei),
/// которые агрессивно управляют батареей и убивают фоновые приложения.
class DeviceSettingsService {
  static const _batteryChannel =
      MethodChannel('com.example.orpheus_project/battery');
  static const _settingsChannel =
      MethodChannel('com.example.orpheus_project/settings');

  // Ключ для хранения настройки "не показывать диалог"
  static const String _setupDialogDismissedKey = 'setup_dialog_dismissed';

  // ===== Test hooks =====
  @visibleForTesting
  static bool? debugForceAndroid;

  @visibleForTesting
  static String? debugManufacturerOverride;

  @visibleForTesting
  static bool? debugBatteryOptimizationDisabledOverride;

  @visibleForTesting
  static void debugResetForTesting() {
    debugForceAndroid = null;
    debugManufacturerOverride = null;
    debugBatteryOptimizationDisabledOverride = null;
  }

  /// Проверить, был ли диалог скрыт пользователем
  static Future<bool> isSetupDialogDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupDialogDismissedKey) ?? false;
  }

  /// Сохранить настройку "не показывать диалог"
  static Future<void> setSetupDialogDismissed(bool dismissed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupDialogDismissedKey, dismissed);
  }

  /// Заблокирован ли экран устройства (keyguard).
  ///
  /// ВАЖНО: вызывается из показа входящего звонка, в т.ч. из ОТДЕЛЬНОГО изолята
  /// push-сервиса, где method-channel к MainActivity недоступен -> invokeMethod
  /// падает. В этом случае (и на не-Android нет — там lockscreen'а нет) НЕЛЬЗЯ
  /// вернуть false: это раскрыло бы имя звонящего на локскрине. Раз подтвердить
  /// «разблокировано» не можем — консервативно считаем «заблокировано» (true),
  /// т.е. прячем имя. Реально false вернём только когда канал ответил false.
  static Future<bool> isDeviceLocked() async {
    if (!Platform.isAndroid) return false;
    try {
      final locked =
          await _settingsChannel.invokeMethod<bool>('isDeviceLocked');
      // null (канал недоступен/не ответил) -> приватный дефолт «заблокировано».
      return locked ?? true;
    } catch (e) {
      // Канал недоступен (фоновый изолят) -> приватный дефолт «заблокировано».
      return true;
    }
  }

  static const String _showCallerNameWhenLockedKey =
      'show_caller_name_when_locked';

  /// Показывать ли имя звонящего на входящем, когда устройство заблокировано.
  /// По умолчанию НЕТ: на локскрине не светим, кто звонит (приватность).
  static Future<bool> showCallerNameWhenLocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showCallerNameWhenLockedKey) ?? false;
  }

  static Future<void> setShowCallerNameWhenLocked(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showCallerNameWhenLockedKey, value);
  }

  static const String _appInForegroundKey = 'app_in_foreground';

  /// Флаг «Orpheus на переднем плане». Пишется из main-изолята по lifecycle,
  /// читается в ЛЮБОМ изоляте (SharedPreferences), в т.ч. push-изолятом — в
  /// отличие от keyguard-проверки через method-channel (в push-изоляте недоступна).
  static Future<void> setAppInForeground(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appInForegroundKey, value);
  }

  /// Прятать ли имя звонящего на входящем (приватность). Прячем, когда Orpheus НЕ
  /// на переднем плане (заблокировано / свёрнуто / убито) И флаг «показывать имя
  /// на локскрине» выключен. Имя видно только когда ты реально в приложении.
  static Future<bool> hideCallerIdentityOnIncoming() async {
    final prefs = await SharedPreferences.getInstance();
    // reload: флаг foreground пишет main-изолят, а читаем часто из push-изолята —
    // SharedPreferences кешируются per-isolate, без reload увидим устаревшее.
    try {
      await prefs.reload();
    } catch (_) {}
    if (prefs.getBool(_showCallerNameWhenLockedKey) ?? false) return false;
    return !(prefs.getBool(_appInForegroundKey) ?? false);
  }

  /// Получить производителя устройства
  static Future<String> getDeviceManufacturer() async {
    final forced = debugForceAndroid;
    if (forced != true && !Platform.isAndroid) return 'other';

    final override = debugManufacturerOverride;
    if (override != null) return override.toLowerCase();

    try {
      final manufacturer =
          await _settingsChannel.invokeMethod<String>('getDeviceManufacturer');
      return manufacturer?.toLowerCase() ?? 'other';
    } catch (e) {
      return 'other';
    }
  }

  /// Проверить, отключена ли оптимизация батареи для приложения
  static Future<bool> isBatteryOptimizationDisabled() async {
    final forced = debugForceAndroid;
    if (forced != true && !Platform.isAndroid) return true;

    final override = debugBatteryOptimizationDisabledOverride;
    if (override != null) return override;

    try {
      return await _batteryChannel
              .invokeMethod<bool>('isBatteryOptimizationDisabled') ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// Запросить отключение оптимизации батареи
  static Future<void> requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;

    try {
      await _batteryChannel.invokeMethod('requestBatteryOptimization');
    } catch (e) {
      print("DeviceSettings: Battery optimization request error: $e");
    }
  }

  /// Открыть настройки батареи
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _batteryChannel.invokeMethod('openBatterySettings');
    } catch (e) {
      print("DeviceSettings: Open battery settings error: $e");
    }
  }

  /// Открыть настройки приложения
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _settingsChannel.invokeMethod('openAppSettings');
    } catch (e) {
      print("DeviceSettings: Open app settings error: $e");
    }
  }

  /// Открыть настройки уведомлений
  static Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _settingsChannel.invokeMethod('openNotificationSettings');
    } catch (e) {
      print("DeviceSettings: Open notification settings error: $e");
    }
  }

  /// Android 14+: открыть Special access → Full screen intents для приложения.
  /// Без этого ОС может не показывать "большой экран" по full-screen intent.
  static Future<void> openFullScreenIntentSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _settingsChannel.invokeMethod('openFullScreenIntentSettings');
    } catch (e) {
      print("DeviceSettings: Open full-screen intent settings error: $e");
    }
  }

  /// Открыть настройки автозапуска (для китайских OEM)
  static Future<void> openAutoStartSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _settingsChannel.invokeMethod('openAutoStartSettings');
    } catch (e) {
      print("DeviceSettings: Open autostart settings error: $e");
    }
  }

  /// Проверить, разрешено ли рисовать поверх других приложений
  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return true;

    try {
      return await _settingsChannel.invokeMethod<bool>('canDrawOverlays') ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// Запросить разрешение на overlay
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;

    try {
      await _settingsChannel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      print("DeviceSettings: Overlay permission request error: $e");
    }
  }

  /// Проверить, нужно ли показывать инструкции по настройке
  /// (для китайских устройств это критично)
  static Future<bool> needsManualSetup() async {
    final manufacturer = await getDeviceManufacturer();
    final batteryOptimized = !(await isBatteryOptimizationDisabled());

    // Для китайских OEM всегда нужна ручная настройка
    final isChineseOem = [
      'xiaomi',
      'redmi',
      'poco',
      'vivo',
      'oppo',
      'realme',
      'huawei',
      'honor',
      'oneplus'
    ].any((brand) => manufacturer.contains(brand));

    return isChineseOem || batteryOptimized;
  }

  /// Получить человекочитаемое название производителя
  static String getManufacturerDisplayName(String manufacturer) {
    if (manufacturer.contains('xiaomi') ||
        manufacturer.contains('redmi') ||
        manufacturer.contains('poco')) {
      return 'Xiaomi/MIUI';
    } else if (manufacturer.contains('vivo')) {
      return 'Vivo';
    } else if (manufacturer.contains('oppo') ||
        manufacturer.contains('realme')) {
      return 'OPPO/Realme';
    } else if (manufacturer.contains('huawei') ||
        manufacturer.contains('honor')) {
      return 'Huawei/Honor';
    } else if (manufacturer.contains('samsung')) {
      return 'Samsung';
    } else if (manufacturer.contains('oneplus')) {
      return 'OnePlus';
    }
    return manufacturer;
  }

  /// Показать диалог с инструкциями по настройке
  static Future<void> showSetupDialog(BuildContext context) async {
    final manufacturer = await getDeviceManufacturer();
    final displayName = getManufacturerDisplayName(manufacturer);
    final batteryDisabled = await isBatteryOptimizationDisabled();

    if (!context.mounted) return;

    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // Шире стандартного (меньше боковые отступы) — RU-текст меньше переносится,
        // шаги влезают без обрезки на границе скролла (баг на крупном шрифте Samsung).
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Row(
          children: [
            Icon(
              batteryDisabled
                  ? Icons.check_circle
                  : Icons.warning_amber_rounded,
              color: batteryDisabled ? const Color(0xFF6AD394) : Colors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isRu ? 'Настройка уведомлений' : 'Notification setup',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRu ? 'Устройство: $displayName' : 'Device: $displayName',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Text(
                isRu
                    ? 'Для стабильных уведомлений о звонках и сообщениях выполните следующие шаги:'
                    : 'For stable call and message notifications, please complete the following steps:',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Шаг 1: Батарея
              _buildSetupStep(
                number: 1,
                title: isRu
                    ? 'Отключите оптимизацию батареи'
                    : 'Disable battery optimization',
                description: batteryDisabled
                    ? (isRu ? 'Уже отключено ✓' : 'Already disabled ✓')
                    : (isRu
                        ? 'Разрешите Orpheus работать в фоне без ограничений'
                        : 'Allow Orpheus to run in background without restrictions'),
                isComplete: batteryDisabled,
                onTap: batteryDisabled
                    ? null
                    : () async {
                        // НЕ закрываем диалог: настройки Android откроются поверх,
                        // после возврата диалог остаётся — можно сделать и остальные
                        // шаги. Закрытие — только явной кнопкой Done/Later.
                        await requestBatteryOptimization();
                      },
              ),

              // Шаг 2: Автозапуск (для китайских OEM)
              if (_isChineseOem(manufacturer)) ...[
                const SizedBox(height: 12),
                _buildSetupStep(
                  number: 2,
                  title: isRu ? 'Включите автозапуск' : 'Enable autostart',
                  description: isRu
                      ? 'Разрешите приложению запускаться автоматически'
                      : 'Allow the app to start automatically',
                  onTap: () async {
                    await openAutoStartSettings();
                  },
                ),
              ],

              // Шаг 3: Уведомления
              const SizedBox(height: 12),
              _buildSetupStep(
                number: _isChineseOem(manufacturer) ? 3 : 2,
                title: isRu
                    ? 'Проверьте настройки уведомлений'
                    : 'Check notification settings',
                description: isRu
                    ? 'Убедитесь, что уведомления о звонках включены'
                    : 'Make sure call notifications are enabled',
                onTap: () async {
                  await openNotificationSettings();
                },
              ),

              // Дополнительные инструкции для Xiaomi
              if (manufacturer.contains('xiaomi') ||
                  manufacturer.contains('redmi') ||
                  manufacturer.contains('poco')) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRu
                            ? '⚠️ Для Xiaomi/MIUI также:'
                            : '⚠️ For Xiaomi/MIUI also:',
                        style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRu
                            ? '• Настройки → Приложения → Orpheus → Экономия батареи → «Без ограничений»\n'
                                '• Безопасность → Автозапуск → включить Orpheus\n'
                                '• Настройки → Приложения → Orpheus → Уведомления → включить все'
                            : '• Settings → Apps → Orpheus → Battery saver → "No restrictions"\n'
                                '• Security → Autostart → enable Orpheus\n'
                                '• Settings → Apps → Orpheus → Notifications → enable all',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],

              // Для Vivo
              if (manufacturer.contains('vivo')) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRu ? '⚠️ Для Vivo также:' : '⚠️ For Vivo also:',
                        style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRu
                            ? '• i Manager → Менеджер приложений → Orpheus → Высокое энергопотребление\n'
                                '• Настройки → Приложения → Orpheus → Автозапуск → включить'
                            : '• i Manager → App manager → Orpheus → High power consumption\n'
                                '• Settings → Apps → Orpheus → Autostart → enable',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await setSetupDialogDismissed(true);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(isRu ? 'Больше не показывать' : "Don't show again",
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isRu ? 'Позже' : 'Later',
                style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6AD394),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(isRu ? 'Готово' : 'Done'),
          ),
        ],
      ),
    );
  }

  static bool _isChineseOem(String manufacturer) {
    return [
      'xiaomi',
      'redmi',
      'poco',
      'vivo',
      'oppo',
      'realme',
      'huawei',
      'honor',
      'oneplus'
    ].any((brand) => manufacturer.contains(brand));
  }

  static Widget _buildSetupStep({
    required int number,
    required String title,
    required String description,
    bool isComplete = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isComplete
              ? const Color(0xFF6AD394).withOpacity(0.1)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isComplete
                ? const Color(0xFF6AD394).withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete
                    ? const Color(0xFF6AD394)
                    : Colors.white.withOpacity(0.2),
              ),
              child: Center(
                child: isComplete
                    ? const Icon(Icons.check, size: 16, color: Colors.black)
                    : Text(
                        '$number',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color:
                          isComplete ? const Color(0xFF6AD394) : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      color: isComplete
                          ? const Color(0xFF6AD394).withOpacity(0.7)
                          : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.withOpacity(0.5),
              ),
          ],
        ),
      ),
    );
  }
}
