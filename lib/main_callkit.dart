part of 'main.dart';

void _initCallKit() {
  // Слушаем события от CallKit (принять/отклонить звонок)
  // flutter_callkit_incoming 3.x: CallEvent — sealed class с подклассами вместо
  // event.event/event.body. Событие несёт CallKitParams; наш прежний body-контракт
  // реконструируем через _callKitParamsToBody, чтобы не переписывать хендлеры.
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;

    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        // Пользователь принял звонок через нативный UI
        await _handleCallKitAccept(_callKitParamsToBody(callKitParams));
        break;

      case CallEventActionCallDecline(:final callKitParams):
        // Пользователь отклонил звонок через нативный UI
        await _handleCallKitDecline(_callKitParamsToBody(callKitParams));
        break;

      case CallEventActionCallEnded():
        DebugLogger.info('CALLKIT', 'Звонок завершён');
        break;

      case CallEventActionCallTimeout():
        // Таймаут — никто не ответил (событие несёт только id)
        DebugLogger.info('CALLKIT', 'Таймаут звонка');
        await _handleCallKitDecline(null);
        break;

      default:
        break;
    }
  });
  
  // Проверяем, есть ли активный звонок при запуске приложения
  // (если приложение было запущено из нативного UI)
  _checkActiveCallOnStart();
}

/// Реконструирует прежнюю форму body (как её ждут _handleCallKit*/_extractExtraFromBody)
/// из CallKitParams (flutter_callkit_incoming 3.x). `extra` — тот же map, что мы клали.
Map<String, dynamic> _callKitParamsToBody(CallKitParams cp) => {
      'id': cp.id,
      'nameCaller': cp.nameCaller,
      'handle': cp.handle,
      'extra': cp.extra,
    };

/// Рекурсивно конвертирует Map<Object?, Object?> → Map<String, dynamic>
Map<String, dynamic> _convertToStringDynamicMap(dynamic input) {
  if (input is Map<String, dynamic>) return input;
  if (input is Map) {
    return input.map((key, value) {
      final stringKey = key?.toString() ?? '';
      if (value is Map) {
        return MapEntry(stringKey, _convertToStringDynamicMap(value));
      }
      return MapEntry(stringKey, value);
    });
  }
  return {};
}

/// Извлекает extra из CallKit body (обрабатывает разные типы)
Map<String, dynamic>? _extractExtraFromBody(Map<String, dynamic>? body) {
  if (body == null) return null;
  
  final rawExtra = body['extra'];
  DebugLogger.info('CALLKIT', 'rawExtra type: ${rawExtra?.runtimeType}');
  
  if (rawExtra == null) return null;
  
  // Случай 1: уже Map<String, dynamic>
  if (rawExtra is Map<String, dynamic>) {
    DebugLogger.info('CALLKIT', 'extra is Map<String, dynamic>');
    return rawExtra;
  }
  
  // Случай 2: Map<Object?, Object?> или LinkedHashMap
  if (rawExtra is Map) {
    DebugLogger.info('CALLKIT', 'extra is Map (converting...)');
    return _convertToStringDynamicMap(rawExtra);
  }
  
  // Случай 3: JSON строка
  if (rawExtra is String) {
    DebugLogger.info('CALLKIT', 'extra is String (parsing JSON...)');
    try {
      final decoded = json.decode(rawExtra);
      if (decoded is Map) {
        return _convertToStringDynamicMap(decoded);
      }
    } catch (e) {
      DebugLogger.error('CALLKIT', 'Ошибка парсинга extra JSON: $e');
    }
  }
  
  return null;
}

/// Проверка активного звонка при запуске приложения
Future<void> _checkActiveCallOnStart() async {
  // Ждём пока Navigator будет готов (первый кадр отрисован)
  await Future.delayed(const Duration(milliseconds: 300));
  
  // КРИТИЧНО: Сначала проверяем PERSISTENT storage!
  // Когда приложение перезапускается при accept звонка из background,
  // RAM данные (_pendingCall) теряются, но storage сохраняется.
  final storedPending = await PendingCallStorage.instance.loadAndClear();
  if (storedPending != null && storedPending.isValid) {
    DebugLogger.info('CALLKIT', '📞 Найден pending call в STORAGE, открываю CallScreen');
    _isProcessingCallKitAnswer = true;
    _navigateToCallScreen(
      storedPending.callerKey,
      storedPending.offerData,
      autoAnswer: storedPending.autoAnswer,
      callId: storedPending.callId,
    );
    return;
  }
  
  // Fallback: проверяем pending call в RAM (для случаев без перезапуска)
  if (_pendingCall != null && _pendingCall!.isValid) {
    DebugLogger.info('CALLKIT', '📞 Найден pending call в RAM, открываю CallScreen');
    final pending = _pendingCall!;
    _pendingCall = null;
    _navigateToCallScreen(
      pending.callerKey,
      pending.offerData,
      autoAnswer: pending.autoAnswer,
      callId: pending.callId,
    );
    return;
  }
  
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    DebugLogger.info('CALLKIT', 'Проверка активных звонков: ${calls.length}');
    
    if (calls.isNotEmpty) {
      DebugLogger.info('CALLKIT', 'Найден активный звонок при запуске');
      
      // КРИТИЧНО: блокируем дубли из WebSocket
      _isProcessingCallKitAnswer = true;
      
      // activeCalls() теперь возвращает List<CallKitParams> (callkit 3.x).
      final call = _callKitParamsToBody(calls.first);

      DebugLogger.info('CALLKIT', 'Active call keys: ${call.keys.toList()}');
      
      // Парсим extra
      final extra = _extractExtraFromBody(call);
      String? callerKey = extra?['callerKey'] as String?;
      
      // Fallback на буфер
      if (callerKey == null) {
        callerKey = incomingCallBuffer.lastCallerKey;
        DebugLogger.info('CALLKIT', 'callerKey from buffer: $callerKey');
      }
      
      if (callerKey != null) {
        DebugLogger.info('CALLKIT', 'Открываю CallScreen для активного звонка: $callerKey');
        final callId = call['id'] as String?;
        
        // Формируем extra
        Map<String, dynamic> callExtra = extra ?? {};
        if (callExtra['offerData'] == null) {
          final bufferOffer = incomingCallBuffer.lastOfferData;
          if (bufferOffer != null) {
            callExtra['offerData'] = json.encode(bufferOffer);
          }
        }
        callExtra['callerKey'] = callerKey;
        
        _openCallScreenFromCallKit(callerKey, callExtra, callId: callId);
      } else {
        DebugLogger.warn('CALLKIT', 'callerKey is null, не могу открыть CallScreen');
        _isProcessingCallKitAnswer = false;
      }
    }
  } catch (e) {
    DebugLogger.error('CALLKIT', 'Ошибка проверки активного звонка: $e');
    _isProcessingCallKitAnswer = false;
  }
}

/// Обработка принятия звонка через CallKit
Future<void> _handleCallKitAccept(Map<String, dynamic>? body) async {
  DebugLogger.info('CALLKIT', '📥 ACCEPT body: $body');
  
  // КРИТИЧНО: блокируем открытие CallScreen из WebSocket пока обрабатываем CallKit
  _isProcessingCallKitAnswer = true;
  
  final callId = body?['id'] as String?;
  
  // Используем надёжный парсинг extra
  final extra = _extractExtraFromBody(body);
  DebugLogger.info('CALLKIT', '📥 extra parsed: ${extra?.keys.toList()}');
  
  String? callerKey = extra?['callerKey'] as String?;
  DebugLogger.info('CALLKIT', '📥 callerKey from extra: $callerKey');
  
  // ВАЖНО: НЕ вызываем endAllCalls() здесь!
  // При перезапуске приложения из killed state, _checkActiveCallOnStart() 
  // должен найти активный звонок. CallScreen сам вызовет endAllCalls() при инициализации.
  
  // Если callerKey из extra null, пробуем буфер
  if (callerKey == null) {
    DebugLogger.warn('CALLKIT', '⚠️ callerKey null, проверяю буфер...');
    callerKey = incomingCallBuffer.lastCallerKey;
    DebugLogger.info('CALLKIT', '📥 callerKey from buffer: $callerKey');
  }
  
  DebugLogger.info(
    'CALLKIT',
    '✅ Звонок принят: callId=$callId, callerKey=$callerKey',
    context: {'call_id': callId, 'peer_pubkey': callerKey},
  );
  
  // Открываем CallScreen
  if (callerKey != null) {
    // Формируем extra для CallScreen
    Map<String, dynamic> callExtra = extra ?? {};
    
    // Если offerData не в extra, берём из буфера
    if (callExtra['offerData'] == null) {
      final bufferOffer = incomingCallBuffer.lastOfferData;
      if (bufferOffer != null) {
        callExtra['offerData'] = json.encode(bufferOffer);
        DebugLogger.info('CALLKIT', '📥 offerData взят из буфера');
      }
    }
    
    callExtra['callerKey'] = callerKey;
    
    // КРИТИЧНО: Сохраняем в persistent storage СРАЗУ!
    // Если Android перезапустит Flutter Engine, RAM данные потеряются,
    // но storage сохранится и _checkActiveCallOnStart найдёт pending call.
    final offerDataStr = callExtra['offerData'] as String?;
    Map<String, dynamic>? offerData;
    if (offerDataStr != null) {
      try {
        offerData = json.decode(offerDataStr) as Map<String, dynamic>;
      } catch (e) {
        DebugLogger.warn('CALLKIT', 'Error parsing offerData for storage: $e');
      }
    }
    await PendingCallStorage.instance.save(
      callerKey: callerKey,
      offerData: offerData,
      autoAnswer: true,
      callId: callId,
    );
    
    _openCallScreenFromCallKit(callerKey, callExtra, callId: callId);
  } else {
    DebugLogger.error('CALLKIT', '❌ callerKey is null! Нет данных для звонка!');
    _isProcessingCallKitAnswer = false; // Сбрасываем флаг при ошибке
    // Скрываем UI только при ошибке
    await FlutterCallkitIncoming.endAllCalls();
  }
}

/// Обработка отклонения звонка через CallKit
Future<void> _handleCallKitDecline(Map<String, dynamic>? body) async {
  DebugLogger.info('CALLKIT', '📥 DECLINE body: $body');
  
  // Сбрасываем флаг обработки CallKit
  _isProcessingCallKitAnswer = false;
  
  final callId = body?['id'] as String?;
  
  // Используем надёжный парсинг extra
  final extra = _extractExtraFromBody(body);
  String? callerKey = extra?['callerKey'] as String?;
  
  DebugLogger.info('CALLKIT', '📥 callerKey from extra: $callerKey');
  
  // Fallback: используем данные из буфера
  if (callerKey == null) {
    callerKey = incomingCallBuffer.lastCallerKey;
    DebugLogger.info('CALLKIT', '📥 callerKey from buffer: $callerKey');
  }
  
  DebugLogger.info(
    'CALLKIT',
    '❌ Звонок отклонён: callId=$callId, callerKey=$callerKey',
    context: {'call_id': callId, 'peer_pubkey': callerKey},
  );

  // Если CallKit отклонён системой в фоне сразу после показа — не сбрасываем звонок.
  if (!isAppInForeground && callId != null) {
    final ageMs = await CallIdStorage.getActiveCallAgeMs();
    if (ageMs != null && ageMs < 2000) {
      DebugLogger.warn('CALLKIT', '⚠️ Системный decline в фоне, пропускаю call-rejected',
          context: {'call_id': callId, 'peer_pubkey': callerKey, 'age_ms': ageMs});
      return;
    }
  }
  
  // Скрываем нативный UI СРАЗУ
  await FlutterCallkitIncoming.endAllCalls();
  
  // Очищаем буфер
  incomingCallBuffer.clearLastIncomingCall();
  
  // Отправляем call-rejected (WebSocket или HTTP fallback)
  // ВАЖНО: sendSignalingMessage сам использует HTTP fallback если WS не подключён!
  if (callerKey != null) {
    websocketService.sendSignalingMessage(
      callerKey,
      'call-rejected',
      callId != null ? {'call_id': callId} : {},
    );
    DebugLogger.info('CALLKIT', '✅ Отправлен call-rejected к $callerKey');
  } else {
    DebugLogger.error('CALLKIT', '❌ callerKey null, не могу отправить call-rejected');
  }
}

/// Открыть CallScreen после принятия звонка через CallKit
/// autoAnswer=true означает что звонок уже принят через нативный UI
void _openCallScreenFromCallKit(
  String callerKey,
  Map<String, dynamic>? extra, {
  bool autoAnswer = true,
  String? callId,
}) {
  // Получаем offer data если есть
  Map<String, dynamic>? offerData;
  final offerJson = extra?['offerData'] as String?;
  if (offerJson != null) {
    try {
      offerData = json.decode(offerJson) as Map<String, dynamic>;
    } catch (_) {}
  }
  
  DebugLogger.info('CALLKIT', 'Открываю CallScreen, offer: ${offerData != null}, autoAnswer: $autoAnswer');
  
  final resolvedCallId = callId ??
      (offerData != null ? CallIdStorage.extractCallId(offerData, callerKey) : null);

  // Если приложение заблокировано (PIN) — сохраняем звонок как pending
  // CallScreen откроется после разблокировки
  if (authService.requiresUnlock) {
    DebugLogger.info('CALLKIT', '🔒 Приложение заблокировано, сохраняю pending call');
    _pendingCall = PendingCallData(
      callerKey: callerKey,
      offerData: offerData,
      autoAnswer: autoAnswer,
      callId: resolvedCallId,
    );
    return;
  }
  
  // Открываем CallScreen сразу с autoAnswer
  _navigateToCallScreen(callerKey, offerData, autoAnswer: autoAnswer, callId: resolvedCallId);
}

/// Навигация на CallScreen (используется напрямую и после разблокировки)
void _navigateToCallScreen(
  String callerKey,
  Map<String, dynamic>? offerData, {
  bool autoAnswer = false,
  String? callId,
}) {
  final resolvedCallId = callId ??
      (offerData != null ? CallIdStorage.extractCallId(offerData, callerKey) : null);
  // Проверяем что нет уже активного звонка
  if (CallStateService.instance.isCallActive.value) {
    DebugLogger.warn('CALLKIT', 'Уже есть активный звонок, игнорирую');
    _isProcessingCallKitAnswer = false; // Сбрасываем флаг
    return;
  }
  
  // КРИТИЧНО: Если Navigator ещё не инициализирован (приложение запускается из killed state),
  // сохраняем pending call — он будет обработан в _checkActiveCallOnStart() или при первом frame
  if (navigatorKey.currentState == null) {
    DebugLogger.warn('CALLKIT', '⚠️ Navigator ещё null, сохраняю pending call');
    _pendingCall = PendingCallData(
      callerKey: callerKey,
      offerData: offerData,
      autoAnswer: autoAnswer,
      callId: resolvedCallId,
    );
    _isProcessingCallKitAnswer = false;
    return;
  }
  
  // Очищаем буфер после использования
  incomingCallBuffer.clearLastIncomingCall();
  
  DebugLogger.info('CALLKIT', '📞 Навигация на CallScreen для $callerKey, hasOffer=${offerData != null}, autoAnswer=$autoAnswer');
  
  // ВАЖНО: При возврате из background, Navigator может быть не готов к навигации.
  // Ждём следующий кадр чтобы гарантировать что UI восстановлен.
  // Также добавляем fallback таймер на случай если приложение в background и кадры не рендерятся.
  bool callbackExecuted = false;
  
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (callbackExecuted) return; // Защита от дублей
    callbackExecuted = true;
    
    // Ещё раз проверяем состояние
    if (CallStateService.instance.isCallActive.value) {
      DebugLogger.warn('CALLKIT', 'Звонок уже активен после postFrame, пропускаю');
      _isProcessingCallKitAnswer = false;
      return;
    }
    
    if (navigatorKey.currentState == null) {
      // Если Navigator всё ещё null — сохраняем pending call для обработки при resumed
      DebugLogger.warn('CALLKIT', '⚠️ Navigator null после postFrame, сохраняю pending call');
      _pendingCall = PendingCallData(
        callerKey: callerKey,
        offerData: offerData,
        autoAnswer: autoAnswer,
        callId: resolvedCallId,
      );
      _isProcessingCallKitAnswer = false;
      return;
    }
    
    DebugLogger.info('CALLKIT', '📞 Открываю CallScreen (postFrame)');
    navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (context) => CallScreen(
        contactPublicKey: callerKey,
        offer: offerData,
        autoAnswer: autoAnswer,
        callId: resolvedCallId,
      ),
    ));
    
    // Скрываем CallKit UI после успешной навигации
    FlutterCallkitIncoming.endAllCalls();
    
    // Очищаем persistent storage после успешной навигации
    PendingCallStorage.instance.clear();
    
    // Сбрасываем флаг после успешной навигации
    Future.delayed(const Duration(milliseconds: 100), () {
      _isProcessingCallKitAnswer = false;
    });
  });
  
  // Fallback: если callback не выполнился за 2 секунды (приложение в background),
  // pending call уже сохранён в storage через _handleCallKitAccept
  Future.delayed(const Duration(seconds: 2), () {
    if (!callbackExecuted) {
      DebugLogger.warn('CALLKIT', '⏰ PostFrame callback не выполнился за 2с, pending call уже в storage');
      callbackExecuted = true;
      // RAM fallback на случай если storage не работает
      _pendingCall = PendingCallData(
        callerKey: callerKey,
        offerData: offerData,
        autoAnswer: autoAnswer,
        callId: resolvedCallId,
      );
      _isProcessingCallKitAnswer = false;
    }
  });
}

/// Обработать отложенный звонок после разблокировки
void processPendingCallAfterUnlock() {
  final pending = _pendingCall;
  _pendingCall = null;
  
  if (pending == null) return;
  
  if (!pending.isValid) {
    DebugLogger.warn('CALLKIT', '⏰ Pending call устарел (>${30}s), игнорирую');
    return;
  }
  
  DebugLogger.info('CALLKIT', '🔓 Обработка pending call после разблокировки, autoAnswer=${pending.autoAnswer}');
  _navigateToCallScreen(
    pending.callerKey,
    pending.offerData,
    autoAnswer: pending.autoAnswer,
    callId: pending.callId,
  );
}

/// Проверка активных CallKit звонков при возврате из background
/// Fallback на случай если pending call был потерян, но CallKit показывает активный звонок
Future<void> _checkActiveCallOnResumed() async {
  // Если уже есть активный звонок или обрабатывается ответ — выходим
  if (CallStateService.instance.isCallActive.value || _isProcessingCallKitAnswer) {
    return;
  }
  
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.isEmpty) return;
    
    DebugLogger.info('LIFECYCLE', '📞 Найден активный CallKit звонок при resumed');
    
    // Блокируем дубли
    _isProcessingCallKitAnswer = true;
    
    // activeCalls() теперь возвращает List<CallKitParams> (callkit 3.x).
    final call = _callKitParamsToBody(calls.first);

    // Парсим extra
    final extra = _extractExtraFromBody(call);
    String? callerKey = extra?['callerKey'] as String?;

    // Fallback на буфер
    if (callerKey == null) {
      callerKey = incomingCallBuffer.lastCallerKey;
    }
    
    if (callerKey != null) {
      DebugLogger.info('LIFECYCLE', '📞 Открываю CallScreen для активного звонка (resumed)');
      final callId = call['id'] as String?;
      
      Map<String, dynamic> callExtra = extra ?? {};
      if (callExtra['offerData'] == null) {
        final bufferOffer = incomingCallBuffer.lastOfferData;
        if (bufferOffer != null) {
          callExtra['offerData'] = json.encode(bufferOffer);
        }
      }
      callExtra['callerKey'] = callerKey;
      
      _openCallScreenFromCallKit(callerKey, callExtra, callId: callId);
    } else {
      DebugLogger.warn('LIFECYCLE', '⚠️ callerKey is null при resumed, пропускаю');
      _isProcessingCallKitAnswer = false;
    }
  } catch (e) {
    DebugLogger.error('LIFECYCLE', 'Ошибка проверки CallKit при resumed: $e');
    _isProcessingCallKitAnswer = false;
  }
}
