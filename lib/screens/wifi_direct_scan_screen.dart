import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/wifi_direct_payload.dart';
import '../services/wifi_direct_session_service.dart';
import '../services/sync_service.dart';
import '../db/database_provider.dart';
import '../db/database.dart';
import 'attendance_result_screen.dart';
import '../theme/app_colors.dart';

class WifiDirectScanScreen extends StatefulWidget {
  const WifiDirectScanScreen({super.key});

  @override
  State<WifiDirectScanScreen> createState() => _WifiDirectScanScreenState();
}

class _WifiDirectScanScreenState extends State<WifiDirectScanScreen> {
  final MobileScannerController _controller = MobileScannerController(autoStart: false);
  final WifiDirectClientService _clientService = WifiDirectClientService();
  bool _handled = false;
  String? _status;
  bool _preflightDone = false;
  bool _preflightFailed = false;
  bool? _cameraPermissionGranted;

  @override
  void initState() {
    super.initState();
    unawaited(_preflight());
  }

  @override
  void dispose() {
    _controller.dispose();
    _clientService.dispose();
    super.dispose();
  }

  Future<void> _preflight() async {
    if (!mounted) return;
    setState(() {
      _status = 'Preparing device...';
      _preflightDone = false;
      _preflightFailed = false;
      _cameraPermissionGranted = null;
    });

    try {
      await _clientService.preflight(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _status = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _preflightDone = true;
        _preflightFailed = false;
        _status = 'Camera permission required to scan.';
      });

      // Start camera only after MobileScanner is mounted (prevents black preview on some devices).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await _controller.start();
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _cameraPermissionGranted = false;
            _status = 'Camera failed to start: $e';
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preflightDone = true;
        _preflightFailed = true;
        _status = 'Permission setup failed: $e';
      });
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_preflightDone || _preflightFailed) return;
    if (_cameraPermissionGranted == false) return;
    if (_handled) return;
    final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
    final raw = barcode?.rawValue ?? barcode?.displayValue;
    if (raw == null) return;
    final payload = WifiDirectPayload.tryParse(raw);
    if (payload == null) {
      _showSnack('Invalid QR payload');
      return;
    }

    setState(() => _handled = true);
    _controller.stop();
    await _attemptJoin(payload);
  }

  Future<void> _attemptJoin(WifiDirectPayload payload) async {
    setState(() => _status = 'Connecting to ${payload.ssid}...');
    final user = FirebaseAuth.instance.currentUser;
    final studentId = user?.uid ?? 'guest-${DateTime.now().millisecondsSinceEpoch}';
    final studentName = user?.displayName ?? user?.email ?? 'Guest';
    
    // Get student's matric number from local database for offline display
    String? matricNumber;
    try {
      final db = DatabaseProvider.of(context);
      if (user != null) {
        final localUser = await db.getUserByFirebaseUid(user.uid);
        matricNumber = localUser?.externalId;
      }
    } catch (e) {
      // If we can't get matric, continue anyway
    }

    final result = await _clientService.joinAndSend(
      payload: payload,
      studentId: studentId,
      studentName: studentName,
      matricNumber: matricNumber,
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _status = status);
      },
    );

    if (!mounted) return;
    
    // If successfully sent, sync to pull latest data from backend
    if (result.sent && user != null) {
      try {
        final db = DatabaseProvider.of(context);
        
        // Trigger sync to pull latest attendance data from backend
        const overrideUrl = String.fromEnvironment('BACKEND_URL');
        final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
        final sync = SyncService(database: db, baseUrl: baseUrl);
        
        // Sync pending changes and pull latest from server
        unawaited(sync.syncPendingChanges());
      } catch (e) {
        // Sync will retry later
      }
    }
    
    // Navigate to result screen
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceResultScreen(
          success: result.sent,
          courseCode: payload.courseCode ?? 'N/A',
          courseName: payload.courseName ?? '',
          timestamp: result.sent ? DateTime.now() : null,
          errorMessage: result.sent ? null : (result.error ?? 'Unable to mark attendance'),
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Camera View
          if (!_preflightDone)
            Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          else if (_preflightFailed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 40, color: Theme.of(context).textTheme.bodyLarge?.color),
                    const SizedBox(height: 12),
                    Text(
                      _status ?? 'Permission setup failed',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _preflight,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              onScannerStarted: (_) {
                if (!mounted) return;
                setState(() {
                  _cameraPermissionGranted = true;
                  _status = 'Scanning automatically...';
                });
              },
              errorBuilder: (context, error, child) {
                if (mounted && error.errorCode == MobileScannerErrorCode.permissionDenied) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _cameraPermissionGranted = false;
                      _status = 'Camera permission denied';
                    });
                  });
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 40, color: Theme.of(context).textTheme.bodyLarge?.color),
                        const SizedBox(height: 12),
                        Text(
                          'Camera error: ${error.errorCode.name}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _controller.stop();
                            await _controller.start();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry Camera'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // Top Controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close Button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: Theme.of(context).cardColor,
                        size: 24,
                      ),
                    ),
                  ),

                  // Flash/Torch Button
                  IconButton(
                    onPressed: () => _controller.toggleTorch(),
                    icon: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.flash_on,
                        color: Theme.of(context).cardColor,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Scanning Frame and Instructions
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Scanning Frame
                CustomPaint(
                  size: const Size(300, 300),
                  painter: _ScanningFramePainter(),
                ),

                const SizedBox(height: 40),

                // Instructions
                Text(
                  'Align class QR code within\nframe to scan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).cardColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  _status ?? 'Scanning automatically...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).cardColor.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for the scanning frame
class _ScanningFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const cornerRadius = 16.0;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, cornerRadius)
        ..arcToPoint(
          const Offset(cornerRadius, 0),
          radius: const Radius.circular(cornerRadius),
        )
        ..lineTo(cornerLength, 0),
      paint,
    );
    canvas.drawLine(const Offset(0, cornerRadius), const Offset(0, cornerLength), paint);

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, 0)
        ..lineTo(size.width - cornerRadius, 0)
        ..arcToPoint(
          Offset(size.width, cornerRadius),
          radius: const Radius.circular(cornerRadius),
        ),
      paint,
    );
    canvas.drawLine(Offset(size.width, cornerRadius), Offset(size.width, cornerLength), paint);

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLength)
        ..lineTo(0, size.height - cornerRadius)
        ..arcToPoint(
          Offset(cornerRadius, size.height),
          radius: const Radius.circular(cornerRadius),
        )
        ..lineTo(cornerLength, size.height),
      paint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, size.height)
        ..lineTo(size.width - cornerRadius, size.height)
        ..arcToPoint(
          Offset(size.width, size.height - cornerRadius),
          radius: const Radius.circular(cornerRadius),
        )
        ..lineTo(size.width, size.height - cornerLength),
      paint,
    );

    // Scanning line (optional animated element)
    final linePaint = Paint()
      ..color = AppColors.primaryBlue.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2 - 1, size.width, 2),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
