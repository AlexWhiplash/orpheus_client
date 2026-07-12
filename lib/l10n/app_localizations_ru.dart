// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class L10nRu extends L10n {
  L10nRu([String locale = 'ru']) : super(locale);

  @override
  String get appName => 'Orpheus';

  @override
  String get welcomeSubtitle => 'Защищённая связь без лишнего шума';

  @override
  String get createAccount => 'Создать аккаунт';

  @override
  String get restoreFromKey => 'Восстановить из ключа';

  @override
  String get e2eEncryption => 'End-to-end шифрование';

  @override
  String get recovery => 'Восстановление';

  @override
  String get recoveryWarning =>
      'Приватный ключ даёт полный доступ к аккаунту. Никому его не показывайте.';

  @override
  String get pastePrivateKey => 'Вставьте приватный ключ…';

  @override
  String get cancel => 'Отмена';

  @override
  String get import => 'Импорт';

  @override
  String get error => 'Ошибка';

  @override
  String get profile => 'Профиль';

  @override
  String get qrCode => 'QR-код';

  @override
  String get yourId => 'Ваш ID';

  @override
  String get idCopied => 'ID скопирован';

  @override
  String get share => 'Поделиться';

  @override
  String shareMessage(String key) {
    return 'Привет! Добавь меня в Orpheus.\nМой ключ:\n$key';
  }

  @override
  String contactsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'контактов',
      many: 'контактов',
      few: 'контакта',
      one: 'контакт',
      zero: 'контактов',
    );
    return '$_temp0';
  }

  @override
  String messagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'сообщений',
      many: 'сообщений',
      few: 'сообщения',
      one: 'сообщение',
      zero: 'сообщений',
    );
    return '$_temp0';
  }

  @override
  String get sentCount => 'отправлено';

  @override
  String get security => 'Безопасность';

  @override
  String get securityDesc => 'PIN, duress, wipe';

  @override
  String get support => 'Поддержка';

  @override
  String get supportDesc => 'Написать разработчику';

  @override
  String get howToUse => 'Как пользоваться';

  @override
  String get howToUseDesc => 'Краткая инструкция';

  @override
  String get updateHistory => 'История обновлений';

  @override
  String get updateAvailable => 'Доступно обновление';

  @override
  String updateMessageRequired(String version) {
    return 'Доступна новая версия $version.\nЭто критическое обновление безопасности.';
  }

  @override
  String updateMessageOptional(String version) {
    return 'Доступна новая версия $version.\nМы рекомендуем обновиться для стабильной работы.';
  }

  @override
  String get updateLater => 'Позже';

  @override
  String get updateDownload => 'Скачать';

  @override
  String get updateDownloading => 'Скачивание обновления';

  @override
  String get updateUpToDate => 'У вас последняя версия';

  @override
  String get updateInstallError => 'Ошибка установки';

  @override
  String get updateInstallErrorMessage =>
      'Не удалось установить обновление автоматически. Можно скачать через браузер.';

  @override
  String get updateOpenBrowser => 'Открыть в браузере';

  @override
  String get exportAccount => 'Экспорт аккаунта';

  @override
  String get exportAccountDesc => 'Показать приватный ключ';

  @override
  String get notificationSettings => 'Настройка уведомлений';

  @override
  String get notificationSettingsDesc => 'Для Android (Vivo, Xiaomi и др.)';

  @override
  String get orpheusNotificationsDesc =>
      'Оповещения о сообщениях в общем чате Орфея.';

  @override
  String get orpheusOfficialNotifications => 'Официальные ответы Орфея';

  @override
  String get systemNotificationSettings => 'Системные настройки уведомлений';

  @override
  String get language => 'Язык';

  @override
  String get languageDesc => 'English, Русский';

  @override
  String accountCreated(String date) {
    return 'Аккаунт создан $date';
  }

  @override
  String get checkUpdates => 'Проверить';

  @override
  String get deleteAccount => 'Удалить аккаунт';

  @override
  String get deleteAccountTitle => 'Удалить аккаунт?';

  @override
  String get deleteAccountWarning =>
      'Это действие удалит ключи, контакты и историю сообщений без возможности восстановления.';

  @override
  String get deleteAccountConfirm => 'Я понимаю, что это необратимо';

  @override
  String get delete => 'Удалить';

  @override
  String get deleteForBoth => 'Удалить у обоих';

  @override
  String get deleteForBothConfirm =>
      'Удалить у обоих? Сообщение будет также удалено на устройстве собеседника.';

  @override
  String nSelected(int count) {
    return '$count выбрано';
  }

  @override
  String deleteSelectedConfirm(int count) {
    return 'Удалить $count сообщений?';
  }

  @override
  String get selectMessages => 'Выбрать';

  @override
  String get privateKey => 'Приватный ключ';

  @override
  String get privateKeyWarning =>
      'Никому не показывайте этот ключ. Владение им даёт полный доступ к вашему аккаунту.';

  @override
  String get close => 'Закрыть';

  @override
  String get copy => 'Копировать';

  @override
  String get copied => 'Скопировано';

  @override
  String get keyCopied => 'Ключ скопирован';

  @override
  String get biometryUnavailable =>
      'Биометрия недоступна. Настройте безопасность устройства.';

  @override
  String get confirmIdentity => 'Подтвердите личность для экспорта ключей';

  @override
  String get authError => 'Ошибка аутентификации';

  @override
  String get accountDeleted => 'Аккаунт удалён. Перезапустите приложение.';

  @override
  String get online => 'В сети';

  @override
  String get offline => 'Не в сети';

  @override
  String get call => 'Позвонить';

  @override
  String get menu => 'Меню';

  @override
  String get clearHistory => 'Очистить историю?';

  @override
  String get clearHistoryWarning =>
      'Все сообщения с этим контактом будут удалены безвозвратно.';

  @override
  String get startConversation => 'Начните диалог';

  @override
  String get messagesEncrypted => 'Сообщения шифруются и сохраняются локально.';

  @override
  String get messagePlaceholder => 'Сообщение…';

  @override
  String get writeAsOrpheus => 'Писать от лица Орфея';

  @override
  String get today => 'Сегодня';

  @override
  String get yesterday => 'Вчера';

  @override
  String get incomingCall => 'Входящий звонок';

  @override
  String get incomingEncryptedCall => 'Закрытая связь';

  @override
  String get outgoingCall => 'Исходящий звонок';

  @override
  String get missedCall => 'Пропущенный звонок';

  @override
  String get callLabel => 'Звонок';

  @override
  String get incoming => 'Входящий';

  @override
  String get outgoing => 'Исходящий';

  @override
  String get chats => 'Чаты';

  @override
  String get contacts => 'Контакты';

  @override
  String get settings => 'Настройки';

  @override
  String get orpheusRoomName => 'Орфей';

  @override
  String get orpheusOfficialBadge => 'OFFICIAL';

  @override
  String get orpheusOfficialName => 'Орфей';

  @override
  String get orpheusRoomWarning =>
      'Публичный чат. Не публикуйте личные данные.';

  @override
  String get orpheusRoomUnavailable =>
      'Общий чат Орфея пока недоступен. Проверьте сервер или попробуйте позже.';

  @override
  String get noChats => 'Нет чатов';

  @override
  String get noChatsDesc => 'Добавьте контакт, чтобы начать общение';

  @override
  String get addContact => 'Добавить контакт';

  @override
  String get noContacts => 'Нет контактов';

  @override
  String get noContactsDesc => 'Отсканируйте QR-код или вставьте ID контакта';

  @override
  String get scanQr => 'Сканировать QR';

  @override
  String get addById => 'Добавить по ID';

  @override
  String get newContact => 'Новый контакт';

  @override
  String get contactName => 'Имя';

  @override
  String get contactId => 'ID контакта';

  @override
  String get add => 'Добавить';

  @override
  String get fillAllFields => 'Заполните оба поля';

  @override
  String get invalidPublicKey => 'Неверный формат ключа';

  @override
  String get contactAdded => 'Контакт добавлен';

  @override
  String get contactExists => 'Контакт уже существует';

  @override
  String get invalidId => 'Неверный формат ID';

  @override
  String get cannotAddSelf => 'Нельзя добавить себя';

  @override
  String get deleteContact => 'Удалить контакт?';

  @override
  String get deleteContactWarning => 'Контакт и история чата будут удалены.';

  @override
  String get contactDeleted => 'Контакт удалён';

  @override
  String get renameContact => 'Переименовать контакт';

  @override
  String get save => 'Сохранить';

  @override
  String get pinCode => 'PIN-код';

  @override
  String get enterPin => 'Введите PIN';

  @override
  String get confirmPin => 'Подтвердите PIN';

  @override
  String get pinMismatch => 'PIN-коды не совпадают';

  @override
  String get pinSet => 'PIN установлен';

  @override
  String get pinDisabled => 'PIN отключён';

  @override
  String get wrongPin => 'Неверный PIN';

  @override
  String attemptsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Осталось $count попыток',
      many: 'Осталось $count попыток',
      few: 'Осталось $count попытки',
      one: 'Осталась 1 попытка',
    );
    return '$_temp0';
  }

  @override
  String get unlock => 'Разблокировать';

  @override
  String get useBiometry => 'Использовать биометрию';

  @override
  String get duressCode => 'Код принуждения';

  @override
  String get duressCodeDesc => 'Показывает пустой профиль при вводе';

  @override
  String get wipeCode => 'Код удаления';

  @override
  String get wipeCodeDesc => 'Удаляет все данные при вводе';

  @override
  String get autoWipe => 'Автоудаление';

  @override
  String autoWipeDesc(int count) {
    return 'Удаление после $count неверных попыток';
  }

  @override
  String get panicGesture => 'Жест panic wipe';

  @override
  String get panicGestureDesc => '3 быстрых сворачивания = wipe';

  @override
  String get enabled => 'Включено';

  @override
  String get disabled => 'Отключено';

  @override
  String get setupPin => 'Установить PIN';

  @override
  String get changePin => 'Изменить PIN';

  @override
  String get removePin => 'Отключить PIN';

  @override
  String get setupDuress => 'Установить код принуждения';

  @override
  String get setupWipe => 'Установить код удаления';

  @override
  String get messageRetention => 'Хранение сообщений';

  @override
  String get retentionForever => 'Всегда';

  @override
  String get retentionWeek => '1 неделя';

  @override
  String get retentionMonth => '1 месяц';

  @override
  String get retentionYear => '1 год';

  @override
  String get license => 'Лицензия';

  @override
  String get licenseRequired =>
      'Для использования приложения требуется лицензия';

  @override
  String get activate => 'Активировать';

  @override
  String get system => 'Система';

  @override
  String get connectionStatus => 'Статус подключения';

  @override
  String get connected => 'Подключено';

  @override
  String get disconnected => 'Отключено';

  @override
  String get reconnecting => 'Переподключение...';

  @override
  String get securityMode => 'Режим безопасности';

  @override
  String get standardMode => 'Стандартный';

  @override
  String get enhancedMode => 'Усиленная защита';

  @override
  String get debugLogs => 'Логи отладки';

  @override
  String get clearLogs => 'Очистить логи';

  @override
  String get exportLogs => 'Экспорт логов';

  @override
  String get logsCleared => 'Логи очищены';

  @override
  String get calling => 'Вызов...';

  @override
  String get ringing => 'Звонок...';

  @override
  String get connecting => 'Соединение...';

  @override
  String get callEnded => 'Звонок завершён';

  @override
  String get callDeclined => 'Звонок отклонён';

  @override
  String get noAnswer => 'Нет ответа';

  @override
  String get endCall => 'Завершить';

  @override
  String get mute => 'Выкл. микрофон';

  @override
  String get unmute => 'Вкл. микрофон';

  @override
  String get speaker => 'Динамик';

  @override
  String get accept => 'Принять';

  @override
  String get decline => 'Отклонить';

  @override
  String get answerCall => 'Ответить';

  @override
  String get microphone => 'Микрофон';

  @override
  String get newMessage => 'Новое сообщение';

  @override
  String get unknownCaller => 'Неизвестный';

  @override
  String get callBack => 'Перезвонить';

  @override
  String get newMessageInChat => 'Новое сообщение в чате';

  @override
  String get officialOrpheusReply => 'Официальный ответ Orpheus';

  @override
  String get testNotificationWorks => 'Тестовое уведомление работает! 🔔';

  @override
  String fromCaller(String name) {
    return 'От: $name';
  }

  @override
  String get supportChat => 'Чат поддержки';

  @override
  String get supportWelcome => 'Чем можем помочь?';

  @override
  String get scanQrTitle => 'Сканировать QR-код';

  @override
  String get cameraPermissionRequired => 'Требуется разрешение камеры';

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get helpQuickStart => 'Быстрый старт';

  @override
  String get helpQuickStartBullet1 =>
      'Ваш ID — это публичный ключ. Им делятся, чтобы вас добавили.';

  @override
  String get helpQuickStartBullet2 =>
      'Контакт работает «в обе стороны»: вы добавляете человека по его ID/QR, и он добавляет вас по вашему ID/QR.';

  @override
  String get helpQuickStartBullet3 =>
      'Чат и звонки идут по защищённому каналу, сообщения шифруются.';

  @override
  String get helpExportTitle => 'Экспорт аккаунта (важно)';

  @override
  String get helpExportBullet1 =>
      'Профиль → Экспорт аккаунта показывает приватный ключ.';

  @override
  String get helpExportBullet2 =>
      'Приватный ключ — это полный доступ к аккаунту. Не показывайте его никому.';

  @override
  String get helpExportBullet3 =>
      'Потеряли приватный ключ и удалили приложение — восстановление невозможно.';

  @override
  String get helpPinTitle => 'PIN-код';

  @override
  String get helpPinBullet1 =>
      'Профиль → Безопасность → PIN. Если PIN не задан — вход открыт.';

  @override
  String get helpPinBullet2 =>
      'Если PIN включён — приложение блокируется после неактивности.';

  @override
  String get helpDuressTitle => 'Код принуждения (Duress)';

  @override
  String get helpDuressBullet1 =>
      'Это второй PIN. При вводе показывается «пустой профиль» (0 контактов/сообщений).';

  @override
  String get helpDuressBullet2 =>
      'Реальные данные не удаляются — они скрыты, пока вы в duress-режиме.';

  @override
  String get helpWipeCodeTitle => 'Код удаления (Panic wipe)';

  @override
  String get helpWipeCodeBullet1 =>
      'Это отдельный код для полного удаления данных.';

  @override
  String get helpWipeCodeBullet2 =>
      'После ввода кода появится подтверждение: удерживайте кнопку 2 секунды.';

  @override
  String get helpWipeCodeBullet3 =>
      'Сделано так, чтобы нельзя было стереть всё случайно.';

  @override
  String get helpAutoWipeTitle => 'Автоудаление (Auto-wipe)';

  @override
  String get helpAutoWipeBullet1 =>
      'Опция: удалить данные после N неверных попыток введения PIN.';

  @override
  String get helpAutoWipeBullet2 =>
      'Включайте только если понимаете риск необратимой потери данных.';

  @override
  String get helpPanicGestureTitle => 'Жест panic wipe';

  @override
  String get helpPanicGestureBullet1 =>
      'Опция (по умолчанию выключена): 3 быстрых ухода приложения в фон → wipe.';

  @override
  String get helpPanicGestureBullet2 =>
      'Жест основан на событиях ухода приложения в фон и может срабатывать менее предсказуемо, чем код удаления.';

  @override
  String get helpRegionsTitle => 'Регионы и контроль трафика';

  @override
  String get helpRegionsBullet1 =>
      'Ваш регион определяется локально на устройстве и никогда не отправляется на серверы Orpheus или третьим лицам.';

  @override
  String get helpRegionsBullet2 =>
      'Если обнаружен регион с контролем трафика, приложение автоматически включает режим «Усиленная защита».';

  @override
  String get helpRegionsBullet3 =>
      'Проблемы со связью? Откройте экран «Система» и проверьте статус сети и режима.';

  @override
  String get selectLanguage => 'Выберите язык';

  @override
  String get systemDefault => 'Системный';

  @override
  String get english => 'English';

  @override
  String get russian => 'Русский';

  @override
  String get languageChanged => 'Язык изменён';

  @override
  String get contactsTitle => 'Контакты';

  @override
  String get scanQrTooltip => 'Сканировать QR';

  @override
  String get refreshTooltip => 'Обновить';

  @override
  String get loadingError => 'Ошибка загрузки';

  @override
  String get addFirstContact =>
      'Добавьте первого собеседника, чтобы начать защищённое общение';

  @override
  String get enterName => 'Введите имя';

  @override
  String get unitHourShort => 'ч';

  @override
  String get unitMinuteShort => 'м';

  @override
  String get unitSecondShort => 'с';

  @override
  String get publicKey => 'Публичный ключ';

  @override
  String get pasteOrScanKey => 'Ключ или QR';

  @override
  String get rename => 'Переименовать';

  @override
  String get enterNewName => 'Введите новое имя';

  @override
  String deleteContactFull(String name) {
    return 'Удалить $name?';
  }

  @override
  String get deleteContactFullWarning =>
      'Контакт и вся история переписки будут удалены безвозвратно.';

  @override
  String get connection => 'Соединение';

  @override
  String get session => 'Сессия';

  @override
  String get queue => 'Очередь';

  @override
  String get region => 'Регион';

  @override
  String get regionLocalOnly => 'Только локально • не передаётся';

  @override
  String get mode => 'Режим';

  @override
  String get enhanced => 'Усиленный';

  @override
  String get standard => 'Стандарт';

  @override
  String get enhancedProtection => 'Повышенная защита';

  @override
  String get stableConnection => 'Стабильное соединение';

  @override
  String get encryption => 'Шифрование';

  @override
  String get copyFingerprint => 'Копировать fingerprint';

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String get keyCreated => 'Ключ создан';

  @override
  String get e2eActive => 'Сквозное шифрование активно';

  @override
  String get fingerprintCopied => 'Fingerprint скопирован';

  @override
  String get storage => 'Хранилище';

  @override
  String get messagesLabel => 'сообщений';

  @override
  String get contactsLabel => 'контактов';

  @override
  String get application => 'Приложение';

  @override
  String get device => 'Устройство';

  @override
  String get model => 'Модель';

  @override
  String get osLabel => 'Система';

  @override
  String get notDetermined => 'Не определено';

  @override
  String get unknown => 'Неизвестно';

  @override
  String get securityTitle => 'БЕЗОПАСНОСТЬ';

  @override
  String get pinCodeSection => 'PIN-КОД';

  @override
  String get inactivityLockTitle => 'Таймер автоблокировки';

  @override
  String get inactivityLockDesc => 'Блокировка при отсутствии активности';

  @override
  String get callerNameOnLockTitle => 'Имя звонящего на локскрине';

  @override
  String get callerNameOnLockDesc =>
      'Показывать имя контакта на входящем звонке, когда телефон заблокирован. По умолчанию выключено для приватности.';

  @override
  String get inactivity30s => '30 секунд';

  @override
  String get inactivity1m => '1 минута';

  @override
  String get inactivity5m => '5 минут';

  @override
  String get inactivity10m => '10 минут';

  @override
  String get pinNotSet =>
      'PIN-код не установлен. Приложение открывается без защиты.';

  @override
  String get setPinCode => 'Установить PIN-код';

  @override
  String get setPinCodeDesc => '4 или 6-значный код для защиты входа';

  @override
  String get pinCodeSet => 'PIN-код установлен';

  @override
  String get changePinCode => 'Изменить PIN-код';

  @override
  String digitCode(int count) {
    return '$count-значный код';
  }

  @override
  String get disablePinCode => 'Отключить PIN-код';

  @override
  String get biometrySection => 'БИОМЕТРИЯ';

  @override
  String get unlockWithBiometry => 'Разблокировка по отпечатку/лицу';

  @override
  String get quickEntryWithoutPin => 'Быстрый вход без ввода PIN';

  @override
  String get duressCodeSection => 'КОД ПРИНУЖДЕНИЯ';

  @override
  String get duressCodeInfo =>
      'Код принуждения — второй PIN, который показывает пустой профиль. Используйте, если вынуждены разблокировать приложение под давлением.';

  @override
  String get setDuressCode => 'Установить код принуждения';

  @override
  String setDuressCodeDesc(int count) {
    return '$count-значный код для экстренных ситуаций';
  }

  @override
  String duressCodeSet(int count) {
    return 'Код принуждения установлен ($count цифр).';
  }

  @override
  String get disableDuressCode => 'Отключить код принуждения';

  @override
  String get wipeCodeSection => 'КОД УДАЛЕНИЯ';

  @override
  String get wipeCodeInfo =>
      'Код удаления — отдельный PIN, который запускает полное удаление данных. После ввода потребуется подтверждение удержанием (защита от случайного запуска).';

  @override
  String get setWipeCode => 'Установить код удаления';

  @override
  String setWipeCodeDesc(int count) {
    return '$count-значный panic wipe код';
  }

  @override
  String wipeCodeSet(int count) {
    return 'Код удаления установлен ($count цифр).';
  }

  @override
  String get disableWipeCode => 'Отключить код удаления';

  @override
  String get bruteForceProtection => 'ЗАЩИТА ОТ ПОДБОРА';

  @override
  String get deleteAfterAttempts => 'Удалить данные после 10 попыток';

  @override
  String get autoWipeOnWrongPin => 'Автоматический wipe при неверном PIN';

  @override
  String get autoWipeWarning =>
      'После 10 неверных попыток все данные будут удалены безвозвратно!';

  @override
  String get emergencyWipe => 'ЭКСТРЕННОЕ УДАЛЕНИЕ';

  @override
  String get enablePanicGesture => 'Включить жест panic wipe';

  @override
  String get panicGestureFullDesc =>
      '3 быстрых ухода приложения в фон → wipe (по умолчанию выключено)';

  @override
  String get panicGestureWarning =>
      'Важно: этот жест основан на быстрых уходах приложения в фон (например, блокировка/разблокировка экрана или быстрое переключение приложений) и может быть менее предсказуем, чем код удаления.';

  @override
  String get autoDeleteMessages => 'АВТОУДАЛЕНИЕ СООБЩЕНИЙ';

  @override
  String get autoDeleteInfo =>
      'Автоматическое удаление старых сообщений повышает приватность. Сообщения старше выбранного периода будут удалены безвозвратно.';

  @override
  String get confirmation => 'Подтверждение';

  @override
  String willDeleteMessages(int count) {
    return 'При включении этой политики будет удалено $count сообщений.\n\nЭто действие необратимо. Продолжить?';
  }

  @override
  String deleted(int count) {
    return 'Удалено $count сообщений';
  }

  @override
  String policyApplied(String name) {
    return 'Политика применена: $name';
  }

  @override
  String get biometryEnabled => 'Биометрия включена';

  @override
  String get biometryFailed => 'Не удалось включить биометрию';

  @override
  String get confirmForBiometry => 'Подтвердите для включения биометрии';

  @override
  String get fastEntry => 'Быстрый ввод';

  @override
  String get combinations => 'комбинаций';

  @override
  String get enhancedSecurity => 'Повышенная защита';

  @override
  String get newPin => 'НОВЫЙ PIN';

  @override
  String get confirmPinTitle => 'ПОДТВЕРДИТЕ PIN';

  @override
  String get currentPin => 'ТЕКУЩИЙ PIN';

  @override
  String get mainPin => 'ОСНОВНОЙ PIN';

  @override
  String get duressCodeTitle => 'КОД ПРИНУЖДЕНИЯ';

  @override
  String get confirmCodeTitle => 'ПОДТВЕРДИТЕ КОД';

  @override
  String get wipeCodeTitle => 'КОД УДАЛЕНИЯ';

  @override
  String enterDigitPin(int count) {
    return 'Введите $count-значный PIN-код';
  }

  @override
  String get repeatPinToConfirm => 'Повторите PIN-код для подтверждения';

  @override
  String get enterCurrentPin => 'Введите текущий PIN-код';

  @override
  String enterNewDigitPin(int count) {
    return 'Введите новый $count-значный PIN-код';
  }

  @override
  String get repeatNewPin => 'Повторите новый PIN-код';

  @override
  String get enterPinToDisable => 'Для отключения введите текущий PIN';

  @override
  String get confirmMainPin => 'Подтвердите основной PIN';

  @override
  String get enterDuressCode =>
      'Введите код принуждения (отличный от основного)';

  @override
  String get repeatDuressCode => 'Повторите код принуждения';

  @override
  String get enterMainPinToDisable => 'Введите основной PIN для отключения';

  @override
  String get enterWipeCode =>
      'Введите код удаления (отличный от основного PIN)';

  @override
  String get repeatWipeCode => 'Повторите код удаления';

  @override
  String get enterMainPinToDisableWipe =>
      'Введите основной PIN для отключения кода удаления';

  @override
  String get pinSetupTitle => 'Установка PIN';

  @override
  String get changePinTitle => 'Изменение PIN';

  @override
  String get disablePinTitle => 'Отключение PIN';

  @override
  String get duressCodeSetupTitle => 'Код принуждения';

  @override
  String get disableCodeTitle => 'Отключение кода';

  @override
  String get wipeCodeSetupTitle => 'Код удаления';

  @override
  String get disableWipeCodeTitle => 'Отключение кода удаления';

  @override
  String get pinCodeSetSuccess => 'PIN-код установлен';

  @override
  String get pinCodeChangedSuccess => 'PIN-код изменён';

  @override
  String get pinCodeDisabledSuccess => 'PIN-код отключён';

  @override
  String get duressCodeSetSuccess => 'Код принуждения установлен';

  @override
  String get duressCodeDisabledSuccess => 'Код принуждения отключён';

  @override
  String get wipeCodeSetSuccess => 'Код удаления установлен';

  @override
  String get wipeCodeDisabledSuccess => 'Код удаления отключён';

  @override
  String get pinsDoNotMatch => 'PIN-коды не совпадают';

  @override
  String get invalidPinCode => 'Неверный PIN-код';

  @override
  String get pinChangeError => 'Ошибка изменения PIN';

  @override
  String get codeMustBeDifferent => 'Код должен отличаться от основного PIN';

  @override
  String get codeSetupError => 'Ошибка установки кода';

  @override
  String get codesDoNotMatch => 'Коды не совпадают';

  @override
  String get selectPinLength => 'ВЫБЕРИТЕ ДЛИНУ PIN';

  @override
  String get shorterPinFaster =>
      'Короткий PIN быстрее вводить,\nдлинный — безопаснее';

  @override
  String get sixDigits => '6 цифр';

  @override
  String get fourDigits => '4 цифры';

  @override
  String get recommended => 'рекомендуется';

  @override
  String get securityLevel => 'Уровень защиты';

  @override
  String get fourDigitCombinations => '4-значный PIN: ~10 000 комбинаций';

  @override
  String get sixDigitCombinations => '6-значный PIN: ~1 000 000 комбинаций';

  @override
  String get developerChat => 'ЧАТ С РАЗРАБОТЧИКОМ';

  @override
  String get willReply => 'Ответим в ближайшее время';

  @override
  String get sendLogsQuestion => 'Отправить логи?';

  @override
  String logsWillBeSent(int count) {
    return 'Будет отправлено $count записей.\n\nЛоги помогут разработчику разобраться в проблеме.';
  }

  @override
  String get send => 'Отправить';

  @override
  String get logsSent => 'Логи отправлены';

  @override
  String get logsError => 'Ошибка отправки логов';

  @override
  String get messageNotSent => 'Не удалось отправить сообщение';

  @override
  String get writeToUs => 'Напишите нам!';

  @override
  String get questionsProblemsIdeas =>
      'Вопросы, проблемы, предложения — мы читаем всё и отвечаем.';

  @override
  String get developer => 'Разработчик';

  @override
  String get now => 'сейчас';

  @override
  String minAgo(int count) {
    return '$count мин';
  }

  @override
  String daysAgo(int count) {
    return '$count дн';
  }

  @override
  String get retry => 'Повторить';

  @override
  String get sendLogs => 'Отправить логи';

  @override
  String get pointCameraAtQr => 'Наведите камеру на QR-код';

  @override
  String get cameraAccessDenied =>
      'Нет доступа к камере. Разрешите доступ к камере, чтобы отсканировать QR-код.';

  @override
  String get publicKeyAutoRecognized =>
      'Публичный ключ контакта будет распознан автоматически';

  @override
  String get retentionAll => 'Хранить всегда';

  @override
  String get retentionDay => 'Хранить 24 часа';

  @override
  String get retentionWeekOption => 'Хранить 7 дней';

  @override
  String get retentionMonthOption => 'Хранить 30 дней';

  @override
  String get retentionAllSubtitle => 'Сообщения не удаляются автоматически';

  @override
  String get retentionDaySubtitle => 'Сообщения старше суток удаляются';

  @override
  String get retentionWeekSubtitle => 'Сообщения старше недели удаляются';

  @override
  String get retentionMonthSubtitle => 'Сообщения старше месяца удаляются';

  @override
  String get autoScroll => 'Автопрокрутка';

  @override
  String get clearLogsQuestion => 'Очистить логи?';

  @override
  String get logsCopied => 'Логи скопированы';

  @override
  String get entryCopied => 'Запись скопирована';

  @override
  String get noLogs => 'Нет логов';

  @override
  String get entries => 'Записей';

  @override
  String get all => 'ВСЕ';

  @override
  String get done => 'Готово';

  @override
  String get activation => 'Активация';

  @override
  String get enterCode => 'Введите код';

  @override
  String get activationCodeHint =>
      'Код активации выдаётся при покупке лицензии.';

  @override
  String get activationCode => 'Код активации';

  @override
  String get activateButton => 'Активировать';

  @override
  String get checking => 'Проверка…';

  @override
  String get licenseActivated => 'Лицензия успешно активирована.';

  @override
  String get enterCodeError => 'Введите код';

  @override
  String get invalidCode => 'Неверный код';

  @override
  String get connectionError => 'Ошибка соединения. Проверьте интернет.';

  @override
  String get format => 'Формат';

  @override
  String get codeFormat => 'Буквы, цифры, а также символы _ и -';

  @override
  String get codeNotAccepted =>
      'Если код не принимается — проверьте интернет и правильность ввода.';

  @override
  String get keysNotInitialized => 'Ключи не инициализированы';

  @override
  String get rooms => 'Комнаты';

  @override
  String get noRooms => 'Нет комнат';

  @override
  String get noRoomsDesc =>
      'Создайте или подключитесь к комнате, чтобы начать.';

  @override
  String get createRoom => 'Создать комнату';

  @override
  String get joinRoom => 'Подключить комнату';

  @override
  String get roomNameHint => 'Название комнаты';

  @override
  String get inviteCodeHint => 'Пригласительный код';

  @override
  String get inviteCodeTitle => 'Пригласительный код';

  @override
  String get inviteCodeCopied => 'Код скопирован';

  @override
  String get roomCreated => 'Комната создана';

  @override
  String get roomJoined => 'Подключение выполнено';

  @override
  String get roomWarningUnprotected =>
      'Этот чат не защищён сквозным шифрованием. Не передавайте конфиденциальную информацию.';

  @override
  String get enableRoomNotifications => 'Включить уведомления чата';

  @override
  String get disableRoomNotifications => 'Отключить уведомления чата';

  @override
  String get roomNotificationsOn => 'Уведомления чата включены';

  @override
  String get roomNotificationsOff => 'Уведомления чата отключены';

  @override
  String get rotateInvite => 'Ротация пригласительного кода';

  @override
  String get rotateInviteTitle => 'Ротировать пригласительный код?';

  @override
  String get rotateInviteDesc => 'Ранее выданный код перестанет работать.';

  @override
  String get panicClear => 'Очистить историю для всех';

  @override
  String get panicClearTitle => 'Очистить историю комнаты?';

  @override
  String get panicClearDesc =>
      'Все сообщения этой комнаты будут удалены у всех участников.';

  @override
  String get leaveRoom => 'Выйти из комнаты';

  @override
  String get leaveRoomTitle => 'Выйти из комнаты?';

  @override
  String get leaveRoomDesc =>
      'Вы перестанете получать сообщения из этой комнаты.';

  @override
  String get deleteRoom => 'Удалить комнату';

  @override
  String get deleteRoomTitle => 'Удалить комнату?';

  @override
  String get deleteRoomDesc =>
      'Комната и все её сообщения будут безвозвратно удалены у всех участников. Это действие необратимо.';

  @override
  String get create => 'Создать';

  @override
  String get join => 'Подключить';

  @override
  String get noMessagesDesc => 'Сообщений пока нет';

  @override
  String get moderationSensitiveWarning =>
      'Внимание: сообщение может содержать чувствительные данные. Будьте осторожны.';

  @override
  String get roomSystemInviteRotated =>
      'Ротация пригласительного кода. Ранее выданный код больше недействителен.';

  @override
  String get roomSystemHistoryCleared => 'История комнаты очищена.';

  @override
  String get ok => 'Ок';

  @override
  String get aiAssistantName => 'Оракул Орфея';

  @override
  String get aiAssistantShortName => 'AI Помощник';

  @override
  String get aiAssistantOnline => 'Всегда онлайн';

  @override
  String get aiAssistantDesc => 'Умный помощник по Orpheus';

  @override
  String get aiAssistantWelcome =>
      'Привет! Я ваш персональный AI-консультант Orpheus. Задайте любой вопрос о функциях приложения, безопасности или настройках.';

  @override
  String get aiThinking => 'Думаю...';

  @override
  String get aiMessageHint => 'Задайте вопрос...';

  @override
  String get aiClearChat => 'Очистить чат';

  @override
  String get aiClearChatTitle => 'Очистить историю?';

  @override
  String get aiClearChatDesc => 'История диалога с AI будет удалена.';

  @override
  String get aiClearMemory => 'Очистить память';

  @override
  String get aiClearMemoryTitle => 'Очистить память?';

  @override
  String get aiClearMemoryDesc =>
      'Память и история диалога с AI будут удалены.';

  @override
  String aiMemoryIndicator(int count) {
    return 'Память: $count ответов ИИ';
  }

  @override
  String get aiSuggestion1 => 'Что нового в этой версии?';

  @override
  String get aiSuggestion2 => 'Как работает шифрование?';

  @override
  String get aiSuggestion3 => 'Что такое код принуждения?';

  @override
  String get aiSuggestion4 => 'Что такое Оракул Орфея?';

  @override
  String get notesVaultTitle => 'Сейф';

  @override
  String get notesVaultDesc => 'Личные заметки и важные сообщения';

  @override
  String get notesEmptyTitle => 'Сейф пуст';

  @override
  String get notesEmptyDesc => 'Сохраняйте мысли и важные сообщения здесь';

  @override
  String get notesPlaceholder => 'Новая заметка...';

  @override
  String get notesAdd => 'Сохранить';

  @override
  String get notesAddFromChat => 'Добавить в заметки';

  @override
  String get notesAdded => 'Добавлено в заметки';

  @override
  String get notesDeleteTitle => 'Удалить заметку?';

  @override
  String get notesDeleteDesc => 'Заметка будет удалена безвозвратно.';

  @override
  String notesFromContact(String name) {
    return 'Из чата с $name';
  }

  @override
  String notesFromRoom(String name) {
    return 'Из комнаты $name';
  }

  @override
  String get notesFromOracle => 'Из чата с Оракулом';

  @override
  String get searchContactsHint => 'Поиск контактов';

  @override
  String get noContactsFound => 'Контакты не найдены';

  @override
  String get contactInfo => 'Информация о контакте';

  @override
  String get verifyKeyHint =>
      'Сверьте этот ключ с контактом по доверенному каналу, чтобы убедиться, что переписку никто не перехватывает.';

  @override
  String get buyLicense => 'Купить лицензию';

  @override
  String get premiumPurchaseTitle => 'Покупка Premium';

  @override
  String get choosePlan => 'Выберите тариф';

  @override
  String get choosePlanHint =>
      'Оплата в USDT (TRC-20). Лицензия активируется автоматически после оплаты.';

  @override
  String get plansLoadError =>
      'Не удалось загрузить тарифы. Проверьте соединение и попробуйте снова.';

  @override
  String get createInvoiceError =>
      'Не удалось создать счёт. Попробуйте ещё раз.';

  @override
  String get paymentNetworkWarning =>
      'Отправляйте ТОЛЬКО USDT в сети TRON (TRC-20). Средства в любой другой сети будут потеряны.';

  @override
  String get walletAddress => 'Адрес кошелька';

  @override
  String get amountToPay => 'Сумма';

  @override
  String get scanQrHint =>
      'Отсканируйте QR-код своим USDT (TRC-20) кошельком или скопируйте адрес ниже.';

  @override
  String get awaitingPayment => 'Ожидаем оплату…';

  @override
  String get awaitingPaymentHint =>
      'Экран разблокируется автоматически, как только оплата подтвердится (около минуты).';

  @override
  String get iPaid => 'Я оплатил(а)';

  @override
  String get invoiceExpired => 'Время на оплату истекло.';

  @override
  String get newInvoice => 'Новый счёт';

  @override
  String get paymentConfirmedTitle => 'Оплата подтверждена';

  @override
  String get paymentConfirmedBody =>
      'Лицензия активна. Добро пожаловать в Orpheus.';

  @override
  String get editNote => 'Редактировать';

  @override
  String get rotateConfirm => 'Ротировать';

  @override
  String get panicClearConfirm => 'Очистить';

  @override
  String get leaveConfirm => 'Выйти';

  @override
  String get deleteConfirm => 'Удалить';

  @override
  String get serverSwitchTitle => 'Сервер';

  @override
  String get serverProduction => 'Прод';

  @override
  String get serverTest => 'Тестовый сервер';

  @override
  String serverCurrent(String host) {
    return 'Текущий: $host';
  }

  @override
  String get serverTestConnection => 'Проверить связь';

  @override
  String serverConnectionOk(int ms) {
    return 'Доступен ($ms мс)';
  }

  @override
  String get serverConnectionFailed => 'Сервер недоступен';

  @override
  String get serverApply => 'Применить и переподключить';

  @override
  String get serverResetProd => 'Сбросить на прод';

  @override
  String get serverTestBanner => 'ТЕСТОВЫЙ СЕРВЕР';

  @override
  String serverSwitched(String host) {
    return 'Переключено на $host';
  }
}
