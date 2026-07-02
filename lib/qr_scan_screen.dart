// lib/qr_scan_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';

class QrScanScreen extends StatefulWidget {
  /// Для widget-тестов: позволяет подменить виджет камеры (mobile_scanner),
  /// чтобы тесты не падали на отсутствии platform plugin.
  ///
  /// Callback `onQrValue` нужно вызвать с распознанной строкой (publicKey).
  final Widget Function(BuildContext context, Future<void> Function(String value) onQrValue)? scannerBuilder;

  const QrScanScreen({super.key, this.scannerBuilder});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with TickerProviderStateMixin {
  bool _isScanned = false;
  bool _isProcessing = false;
  bool _cameraError = false;

  late AnimationController _scanLineController;
  late AnimationController _pulseController;
  late AnimationController _cornerController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _cornerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _pulseController.dispose();
    _cornerController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _onCapture(Result result) {
    if (_isScanned) return;
    final value = result.text;
    if (value.isEmpty) return;
    _handleQrValue(value);
  }

  Future<void> _handleQrValue(String value) async {
    if (_isScanned) return;

    setState(() {
      _isScanned = true;
      _isProcessing = true;
    });

    // Анимация успешного сканирования
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      Navigator.pop(context, value);
    }
  }

  /// Экран ошибки камеры (нет доступа / сбой инициализации) вместо чёрного тупика.
  Widget _buildCameraError(L10n l10n) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography, color: Colors.white54, size: 56),
          const SizedBox(height: 16),
          Text(
            l10n.cameraAccessDenied,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings),
            label: Text(l10n.openSettings),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final size = MediaQuery.of(context).size;
    final scanAreaSize = size.width * 0.75;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Камера (QR-декодирование на чистом Dart через zxing_lib, без Google ML Kit)
          if (widget.scannerBuilder != null)
            widget.scannerBuilder!(context, _handleQrValue)
          else if (_cameraError)
            // Отказ в доступе к камере / сбой инициализации: раньше был тупик —
            // чёрный экран с анимацией поверх (аудит UI-3).
            _buildCameraError(l10n)
          else
            QRCodeDartScanView(
              typeScan: TypeScan.live,
              formats: const [BarcodeFormat.qrCode],
              resolutionPreset: QRCodeDartScanResolutionPreset.high,
              onCapture: _onCapture,
              onCameraError: (error) {
                if (mounted) setState(() => _cameraError = true);
              },
            ),
          
          // Затемнение и рамка
          CustomPaint(
            size: Size.infinite,
            painter: _ScanOverlayPainter(
              scanAreaSize: scanAreaSize,
              screenSize: size,
            ),
          ),
          
          // Анимированная рамка сканирования
          Center(
            child: SizedBox(
              width: scanAreaSize,
              height: scanAreaSize,
              child: Stack(
                children: [
                  // Углы рамки
                  ..._buildCorners(scanAreaSize),
                  
                  // Scanning line
                  if (!_isProcessing)
                    AnimatedBuilder(
                      animation: _scanLineController,
                      builder: (context, child) {
                        return Positioned(
                          top: _scanLineController.value * (scanAreaSize - 4),
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFF6AD394).withOpacity(0.9),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6AD394).withOpacity(0.6),
                                  blurRadius: 15,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  
                  // Glow эффект при обнаружении
                  if (_isProcessing)
                    AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF6AD394).withOpacity(0.8),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6AD394).withOpacity(0.5 + 0.3 * _glowController.value),
                                blurRadius: 30,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 300),
                              builder: (context, value, child) {
                                return Transform.scale(
                                  scale: value,
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6AD394).withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Color(0xFF6AD394),
                                      size: 60,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          
          // Header
          SafeArea(
            child: Column(
              children: [
                // AppBar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _buildBackButton(),
                      const Spacer(),
                      _buildTitle(l10n),
                      const Spacer(),
                      const SizedBox(width: 48), // Балансировка
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // Подсказка внизу
                _buildHintSection(l10n),
                
                const SizedBox(height: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners(double size) {
    const cornerLength = 30.0;
    const cornerWidth = 4.0;
    
    return [
      // Top Left
      _buildAnimatedCorner(
        left: 0,
        top: 0,
        corners: [Corners.topLeft],
        cornerLength: cornerLength,
        cornerWidth: cornerWidth,
        delay: 0,
      ),
      // Top Right
      _buildAnimatedCorner(
        right: 0,
        top: 0,
        corners: [Corners.topRight],
        cornerLength: cornerLength,
        cornerWidth: cornerWidth,
        delay: 0.25,
      ),
      // Bottom Left
      _buildAnimatedCorner(
        left: 0,
        bottom: 0,
        corners: [Corners.bottomLeft],
        cornerLength: cornerLength,
        cornerWidth: cornerWidth,
        delay: 0.5,
      ),
      // Bottom Right
      _buildAnimatedCorner(
        right: 0,
        bottom: 0,
        corners: [Corners.bottomRight],
        cornerLength: cornerLength,
        cornerWidth: cornerWidth,
        delay: 0.75,
      ),
    ];
  }

  Widget _buildAnimatedCorner({
    double? left,
    double? right,
    double? top,
    double? bottom,
    required List<Corners> corners,
    required double cornerLength,
    required double cornerWidth,
    required double delay,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: _cornerController,
        builder: (context, child) {
          final adjustedValue = ((_cornerController.value + delay) % 1.0);
          final glowIntensity = 0.5 + 0.5 * sin(adjustedValue * 2 * pi);
          
          return CustomPaint(
            size: Size(cornerLength, cornerLength),
            painter: _CornerPainter(
              corners: corners,
              cornerWidth: cornerWidth,
              color: const Color(0xFF6AD394),
              glowIntensity: glowIntensity,
              isProcessing: _isProcessing,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBackButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.5),
            border: Border.all(
              color: Colors.white.withOpacity(0.1 + 0.1 * _pulseController.value),
            ),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        );
      },
    );
  }

  Widget _buildTitle(L10n l10n) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF6AD394).withOpacity(0.2 + 0.1 * _pulseController.value),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF6AD394).withOpacity(0.5 + 0.5 * _pulseController.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6AD394).withOpacity(0.3 * _pulseController.value),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.scanQrTitle.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHintSection(L10n l10n) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFB0BEC5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.qr_code,
                  color: const Color(0xFFB0BEC5).withOpacity(0.7 + 0.3 * _pulseController.value),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.pointCameraAtQr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.publicKeyAutoRecognized,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Overlay painter для затемнения
class _ScanOverlayPainter extends CustomPainter {
  final double scanAreaSize;
  final Size screenSize;

  _ScanOverlayPainter({
    required this.scanAreaSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.7);
    
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // Рисуем затемнение вокруг области сканирования
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16))),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum Corners { topLeft, topRight, bottomLeft, bottomRight }

// Corner painter
class _CornerPainter extends CustomPainter {
  final List<Corners> corners;
  final double cornerWidth;
  final Color color;
  final double glowIntensity;
  final bool isProcessing;

  _CornerPainter({
    required this.corners,
    required this.cornerWidth,
    required this.color,
    required this.glowIntensity,
    required this.isProcessing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final effectiveColor = isProcessing ? color : color.withOpacity(0.6 + 0.4 * glowIntensity);
    
    final paint = Paint()
      ..color = effectiveColor
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Glow
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3 * glowIntensity)
      ..strokeWidth = cornerWidth + 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (final corner in corners) {
      final path = Path();
      
      switch (corner) {
        case Corners.topLeft:
          path.moveTo(0, size.height);
          path.lineTo(0, 0);
          path.lineTo(size.width, 0);
          break;
        case Corners.topRight:
          path.moveTo(0, 0);
          path.lineTo(size.width, 0);
          path.lineTo(size.width, size.height);
          break;
        case Corners.bottomLeft:
          path.moveTo(0, 0);
          path.lineTo(0, size.height);
          path.lineTo(size.width, size.height);
          break;
        case Corners.bottomRight:
          path.moveTo(size.width, 0);
          path.lineTo(size.width, size.height);
          path.lineTo(0, size.height);
          break;
      }
      
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) => 
      oldDelegate.glowIntensity != glowIntensity || oldDelegate.isProcessing != isProcessing;
}
