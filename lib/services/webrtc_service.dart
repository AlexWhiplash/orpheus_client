import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:permission_handler/permission_handler.dart';

const Map<String, dynamic> rtcConfiguration = {
  'iceServers': [
    {
      'urls': [
        'turn:194.87.151.56:3478',
        'turn:194.87.151.56:3478?transport=tcp',
        'turn:194.87.151.56:443?transport=tcp',
      ],
      'username': 'orpheus',
      'credential': 'TEST112',
    },
  ],
  'sdpSemantics': 'unified-plan',
  'iceTransportPolicy': 'all',
  'bundlePolicy': 'max-bundle',
};

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;

  final _debugLogController = StreamController<String>.broadcast();
  Stream<String> get onDebugLog => _debugLogController.stream;

  // Поток для уведомления о необходимости ICE restart
  final _iceRestartNeededController = StreamController<void>.broadcast();
  Stream<void> get onIceRestartNeeded => _iceRestartNeededController.stream;

  // Внутренняя очередь кандидатов (для решения Race Condition)
  final List<RTCIceCandidate> _queuedRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  void _log(String msg) {
    print(msg);
    _debugLogController.add(msg);
    // Также логируем в глобальный debug logger
    if (msg.contains('ERROR') || msg.contains('❌')) {
      DebugLogger.error('RTC', msg);
    } else if (msg.contains('✅') || msg.contains('TRACK') || msg.contains('Connected')) {
      DebugLogger.success('RTC', msg);
    } else {
      DebugLogger.info('RTC', msg);
    }
  }

  Future<void> initialize() async {
    _log("--- [WebRTC] Requesting Permissions... ---");
    // Только микрофон (обязателен). BLUETOOTH_CONNECT (звук в BT-гарнитуру) НЕ
    // просим здесь: у него пугающий системный диалог «устройства поблизости».
    // Он запрашивается отдельно, с поясняющим priming-экраном (см. call_screen).
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
    ].request();

    if (statuses[Permission.microphone]!.isGranted) {
      _localStream = await mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googNoiseSuppression': true,
          'googHighpassFilter': true,
        },
        'video': false
      });
    } else {
      _log("--- [WebRTC] ERROR: Mic Permission Denied ---");
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(Function(Map<String, dynamic> candidate) onCandidateCreated) async {
    _log("--- [WebRTC] Creating PeerConnection... ---");
    final pc = await createPeerConnection(rtcConfiguration);

    _registerPeerConnectionListeners(pc, onCandidateCreated);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }
    return pc;
  }

  Future<void> initiateCall({
    required Function(Map<String, dynamic> offer) onOfferCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    _log("--- [WebRTC] INITIATING CALL (OFFER) ---");
    try {
      if (_localStream == null) await initialize();

      _peerConnection = await _createPeerConnection(onCandidateCreated);

      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });

      await _peerConnection!.setLocalDescription(offer);
      _log("--- [WebRTC] Offer created successfully ---");
      onOfferCreated({'sdp': offer.sdp, 'type': offer.type});
    } catch (e) {
      _log("--- [WebRTC] ERROR in initiateCall: $e ---");
      rethrow;
    }
  }

  Future<void> answerCall({
    required Map<String, dynamic> offer,
    required Function(Map<String, dynamic> answer) onAnswerCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    _log("--- [WebRTC] ANSWERING CALL ---");
    try {
      if (_localStream == null) await initialize();

      _peerConnection = await _createPeerConnection(onCandidateCreated);
      await handleOffer(offer, onAnswerCreated: onAnswerCreated);
      _log("--- [WebRTC] Answer sent successfully ---");
    } catch (e) {
      _log("--- [WebRTC] ERROR in answerCall: $e ---");
      rethrow;
    }
  }

  void _registerPeerConnectionListeners(RTCPeerConnection pc, Function(Map<String, dynamic> candidate) onCandidateCreated) {
    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('--- [WebRTC] Connection State: $state ---');
      
      // При Disconnected или Failed - уведомляем о необходимости ICE restart
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _log('--- [WebRTC] ICE Disconnected - may need restart ---');
        // Ждём немного, возможно восстановится само
        Future.delayed(const Duration(seconds: 3), () {
          // Проверяем, не восстановилось ли соединение
          if (_peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
            _iceRestartNeededController.add(null);
          }
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _log('--- [WebRTC] ICE Failed - restart needed ---');
        _iceRestartNeededController.add(null);
      }
    };
    
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      _log('--- [WebRTC] ICE Connection State: $state ---');
    };
    
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      
      // Логируем тип кандидата для диагностики TURN
      final candidateStr = candidate.candidate ?? '';
      String candidateType = 'unknown';
      if (candidateStr.contains('typ host')) {
        candidateType = 'host'; // Локальный IP
      } else if (candidateStr.contains('typ srflx')) {
        candidateType = 'srflx'; // STUN (внешний IP)
      } else if (candidateStr.contains('typ relay')) {
        candidateType = 'relay'; // TURN (relay сервер)
      } else if (candidateStr.contains('typ prflx')) {
        candidateType = 'prflx'; // Peer reflexive
      }
      _log("📤 ICE candidate [$candidateType]");
      
      onCandidateCreated({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      });
    };
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _log("--- [WebRTC] REMOTE TRACK RECEIVED ---");
      }
    };
  }

  Future<void> handleOffer(Map<String, dynamic> offerData, { required Function(Map<String, dynamic> answer) onAnswerCreated }) async {
    if (_peerConnection == null) return;

    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);

    // ВАЖНО: Устанавливаем флаг и применяем очередь
    _remoteDescriptionSet = true;
    await _drainCandidateQueue();

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    onAnswerCreated({'sdp': answer.sdp, 'type': answer.type});
  }

  Future<void> handleAnswer(Map<String, dynamic> answerData) async {
    if (_peerConnection == null) return;

    final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
    await _peerConnection!.setRemoteDescription(answer);

    // ВАЖНО: Устанавливаем флаг и применяем очередь
    _remoteDescriptionSet = true;
    await _drainCandidateQueue();
  }

  // БЕЗОПАСНОЕ ДОБАВЛЕНИЕ КАНДИДАТА
  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    try {
      final candidate = RTCIceCandidate(
          candidateData['candidate'],
          candidateData['sdpMid'],
          (candidateData['sdpMLineIndex'] as num).toInt()
      );

      if (_peerConnection != null && _remoteDescriptionSet) {
        await _peerConnection!.addCandidate(candidate);
        _log("✅ ICE Added immediately");
      } else {
        _log("⏳ ICE Queued (Waiting for SDP)");
        _queuedRemoteCandidates.add(candidate);
      }
    } catch (e) {
      _log("❌ ICE ERROR: $e");
    }
  }

  Future<void> _drainCandidateQueue() async {
    _log("--- [WebRTC] Draining Queue (${_queuedRemoteCandidates.length}) ---");
    for (final candidate in _queuedRemoteCandidates) {
      try {
        if (_peerConnection != null) {
          await _peerConnection!.addCandidate(candidate);
        }
      } catch (e) {
        _log("❌ ICE Queue Error: $e");
      }
    }
    _queuedRemoteCandidates.clear();
  }

  /// ICE Restart - восстановление соединения при смене сети
  /// Возвращает true если restart успешно инициирован
  Future<bool> restartIce({
    required Function(Map<String, dynamic> offer) onOfferCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    if (_peerConnection == null) {
      _log("--- [WebRTC] ICE Restart: No peer connection ---");
      return false;
    }

    try {
      _log("--- [WebRTC] ICE RESTART ---");
      
      // Сбрасываем флаг и очередь
      _remoteDescriptionSet = false;
      _queuedRemoteCandidates.clear();

      // ВАЖНО: Перерегистрируем onIceCandidate чтобы новые кандидаты отправлялись!
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) return;
        _log("📤 ICE Restart candidate generated");
        onCandidateCreated({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        });
      };

      // Создаём новый offer с iceRestart: true
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'iceRestart': true,
      });

      await _peerConnection!.setLocalDescription(offer);
      _log("--- [WebRTC] ICE Restart offer created ---");
      
      onOfferCreated({'sdp': offer.sdp, 'type': offer.type});
      return true;
    } catch (e) {
      _log("--- [WebRTC] ICE Restart ERROR: $e ---");
      return false;
    }
  }

  /// Обработка входящего ICE restart offer (renegotiation)
  Future<bool> handleIceRestartOffer({
    required Map<String, dynamic> offer,
    required Function(Map<String, dynamic> answer) onAnswerCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    if (_peerConnection == null) {
      _log("--- [WebRTC] ICE Restart Handle: No peer connection ---");
      return false;
    }

    try {
      _log("--- [WebRTC] HANDLING ICE RESTART OFFER ---");
      
      // Сбрасываем флаг и очередь для нового SDP
      _remoteDescriptionSet = false;
      _queuedRemoteCandidates.clear();

      // ВАЖНО: Перерегистрируем onIceCandidate чтобы новые кандидаты отправлялись!
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) return;
        _log("📤 ICE Restart answer candidate generated");
        onCandidateCreated({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        });
      };

      // Устанавливаем новый remote description
      final remoteOffer = RTCSessionDescription(offer['sdp'], offer['type']);
      await _peerConnection!.setRemoteDescription(remoteOffer);
      _remoteDescriptionSet = true;
      
      // Создаём answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      
      _log("--- [WebRTC] ICE Restart answer created ---");
      onAnswerCreated({'sdp': answer.sdp, 'type': answer.type});
      
      return true;
    } catch (e) {
      _log("--- [WebRTC] ICE Restart Handle ERROR: $e ---");
      return false;
    }
  }

  /// Получить текущее состояние ICE соединения
  RTCIceConnectionState? get iceConnectionState {
    // flutter_webrtc не предоставляет прямой доступ к iceConnectionState через геттер,
    // но мы можем отслеживать через onIceConnectionState
    return null;
  }

  Future<void> hangUp() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) => track.stop());
    await _remoteStream?.dispose();
    _remoteStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _remoteDescriptionSet = false;
    _queuedRemoteCandidates.clear();
  }
}