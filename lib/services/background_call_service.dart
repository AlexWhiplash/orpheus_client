// lib/services/background_call_service.dart
//
// Тонкий фасад над PushConnectionService.
//
// Раньше этот класс поднимал ОТДЕЛЬНЫЙ microphone foreground-сервис на время
// звонка (start при звонке / stop после). После отказа от Google/FCM единый
// ПОСТОЯННЫЙ foreground-сервис (PushConnectionService, тип specialUse) держит
// соединение и заодно обслуживает уведомление активного звонка —
// flutter_background_service поддерживает только один сервис-инстанс, поэтому
// «сервис на время звонка» сведён к смене текста постоянного уведомления.
// Фасад оставлен, чтобы не менять вызовы в call_screen.dart.

import 'package:orpheus_project/services/push_connection_service.dart';

class BackgroundCallService {
  static Future<void> initialize() => PushConnectionService.initialize();

  /// Звонок начался: гарантируем, что постоянный сервис поднят, и переводим его
  /// уведомление в режим «в звонке».
  static Future<void> startCallService({String contactName = 'Orpheus'}) async {
    await PushConnectionService.start();
    PushConnectionService.enterCallMode(contactName);
  }

  /// Звонок завершён: сервис НЕ останавливаем (он постоянный) — только возвращаем
  /// уведомление в спокойный режим.
  static Future<void> stopCallService() async {
    PushConnectionService.exitCallMode();
  }

  static void updateCallDuration(String duration, String contactName) {
    PushConnectionService.updateCallNotification(duration, contactName);
  }
}
