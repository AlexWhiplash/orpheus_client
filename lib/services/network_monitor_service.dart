import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:rxdart/rxdart.dart';

/// Состояние сетевого соединения
enum NetworkState {
  online,
  offline,
  reconnecting,
}

/// Сервис мониторинга сетевого соединения.
/// Отслеживает смену сети (WiFi <-> Mobile) и уведомляет подписчиков.
class NetworkMonitorService {
  NetworkMonitorService._();
  static final NetworkMonitorService instance = NetworkMonitorService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Текущее состояние сети
  final _stateController = BehaviorSubject<NetworkState>.seeded(NetworkState.online);
  Stream<NetworkState> get stateStream => _stateController.stream;
  NetworkState get currentState => _stateController.value;

  /// Поток событий смены сети (для принудительного реконнекта)
  final _networkChangeController = StreamController<NetworkChangeEvent>.broadcast();
  Stream<NetworkChangeEvent> get onNetworkChange => _networkChangeController.stream;

  /// Последний известный тип соединения
  List<ConnectivityResult> _lastConnectivity = [];
  DateTime? _lastOfflineTime;

  /// Момент последней смены сетевого пути (networkSwitch/reconnected).
  /// Потребитель — GeoService: кэш страны, записанный до этой отметки,
  /// не считается свежим (VPN вкл/выкл меняет внешний IP).
  DateTime? _lastNetworkChangeAt;
  DateTime? get lastNetworkChangeAt => _lastNetworkChangeAt;

  /// Инициализация сервиса
  Future<void> init() async {
    DebugLogger.info('NETWORK', 'Инициализация NetworkMonitorService...');
    
    // Получаем начальное состояние
    _lastConnectivity = await _connectivity.checkConnectivity();
    _updateState(_lastConnectivity);
    
    // Подписываемся на изменения
    _subscription = _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    
    DebugLogger.success('NETWORK', 'NetworkMonitorService инициализирован: $_lastConnectivity');
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    DebugLogger.info('NETWORK', 'Изменение сети: $_lastConnectivity → $results');

    // Отметка для GeoService: ЛЮБОЙ сдвиг набора типов сети (в т.ч. VPN,
    // который connectivity_plus дописывает НЕ первым элементом и который
    // networkSwitch ниже не ловит — тот сравнивает только .first и его
    // семантику «форс-реконнект WS» расширять нельзя).
    if (!setEquals(_lastConnectivity.toSet(), results.toSet())) {
      _lastNetworkChangeAt = DateTime.now();
    }

    final wasOffline = _isOffline(_lastConnectivity);
    final isOffline = _isOffline(results);
    final isOnline = !isOffline;
    
    // Определяем тип изменения
    if (wasOffline && isOnline) {
      // Восстановление связи
      final offlineDuration = _lastOfflineTime != null 
          ? DateTime.now().difference(_lastOfflineTime!) 
          : Duration.zero;
      
      DebugLogger.success('NETWORK', '📶 Связь восстановлена (был offline ${offlineDuration.inSeconds}s)');
      _stateController.add(NetworkState.reconnecting);

      _networkChangeController.add(NetworkChangeEvent(
        type: NetworkChangeType.reconnected,
        newConnectivity: results,
        offlineDuration: offlineDuration,
      ));
      
      // Через небольшую задержку устанавливаем online (даём время на реконнект)
      Future.delayed(const Duration(seconds: 2), () {
        if (!_stateController.isClosed && _stateController.value == NetworkState.reconnecting) {
          _stateController.add(NetworkState.online);
        }
      });
      
    } else if (!wasOffline && isOffline) {
      // Потеря связи
      DebugLogger.warn('NETWORK', '📵 Потеря связи');
      _lastOfflineTime = DateTime.now();
      _stateController.add(NetworkState.offline);
      
      _networkChangeController.add(NetworkChangeEvent(
        type: NetworkChangeType.disconnected,
        newConnectivity: results,
      ));
      
    } else if (!wasOffline && isOnline && _connectivityTypeDiffers(_lastConnectivity, results)) {
      // Смена типа сети (WiFi <-> Mobile) без потери связи
      DebugLogger.info('NETWORK', '🔄 Смена типа сети');
      _stateController.add(NetworkState.reconnecting);

      _networkChangeController.add(NetworkChangeEvent(
        type: NetworkChangeType.networkSwitch,
        newConnectivity: results,
      ));
      
      Future.delayed(const Duration(seconds: 1), () {
        if (!_stateController.isClosed && _stateController.value == NetworkState.reconnecting) {
          _stateController.add(NetworkState.online);
        }
      });
    }
    
    _lastConnectivity = results;
  }

  void _updateState(List<ConnectivityResult> results) {
    if (_isOffline(results)) {
      _stateController.add(NetworkState.offline);
      _lastOfflineTime = DateTime.now();
    } else {
      _stateController.add(NetworkState.online);
    }
  }

  bool _isOffline(List<ConnectivityResult> results) {
    return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
  }

  bool _connectivityTypeDiffers(List<ConnectivityResult> a, List<ConnectivityResult> b) {
    // Сравниваем основной тип подключения
    final aType = a.isNotEmpty ? a.first : ConnectivityResult.none;
    final bType = b.isNotEmpty ? b.first : ConnectivityResult.none;
    return aType != bType;
  }

  /// Проверить текущее состояние сети
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return !_isOffline(results);
  }

  /// Принудительно обновить состояние
  Future<void> refresh() async {
    final results = await _connectivity.checkConnectivity();
    _handleConnectivityChange(results);
  }

  void dispose() {
    _subscription?.cancel();
    _stateController.close();
    _networkChangeController.close();
  }
}

/// Тип изменения сети
enum NetworkChangeType {
  reconnected,    // Восстановление связи после offline
  disconnected,   // Потеря связи
  networkSwitch,  // Смена типа сети (WiFi <-> Mobile)
}

/// Событие изменения сети
class NetworkChangeEvent {
  final NetworkChangeType type;
  final List<ConnectivityResult> newConnectivity;
  final Duration? offlineDuration;

  NetworkChangeEvent({
    required this.type,
    required this.newConnectivity,
    this.offlineDuration,
  });

  @override
  String toString() => 'NetworkChangeEvent($type, $newConnectivity)';
}



