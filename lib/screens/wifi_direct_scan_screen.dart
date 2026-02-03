import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/wifi_direct_payload.dart';
import '../services/wifi_direct_session_service.dart';

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

    final result = await _clientService.joinAndSend(
      payload: payload,
      studentId: studentId,
      studentName: studentName,
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _status = status);
      },
    );

    if (!mounted) return;
    if (result.sent) {
      setState(() => _status = 'Attendance sent!');
      _showSnack('Attendance sent successfully');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() => _status = 'Failed: ${result.error ?? 'Unknown error'}');
      _showSnack('Failed to send attendance: ${result.error ?? 'Unknown error'}');
      setState(() => _handled = false);
      _controller.start();
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Attendance QR'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: !_preflightDone
                ? const Center(child: CircularProgressIndicator())
                : _preflightFailed
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 40),
                              const SizedBox(height: 12),
                              Text(
                                _status ?? 'Permission setup failed',
                                textAlign: TextAlign.center,
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
                    : MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        onScannerStarted: (_) {
                          if (!mounted) return;
                          setState(() {
                            _cameraPermissionGranted = true;
                            _status = 'Ready. Point your camera at the QR.';
                          });
                        },
                        errorBuilder: (context, error, child) {
                          if (mounted && error.errorCode == MobileScannerErrorCode.permissionDenied) {
                            // Permission denied by user or system.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                _cameraPermissionGranted = false;
                                _status = 'Camera permission denied. Enable it in Settings to scan.';
                              });
                            });
                          }
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.camera_alt_outlined, size: 40),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Camera error: ${error.errorCode.name}',
                                    textAlign: TextAlign.center,
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
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Align the QR inside the frame',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status ?? 'Waiting for QR...',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      _controller.switchCamera();
                    },
                    icon: const Icon(Icons.cameraswitch_outlined),
                    label: const Text('Switch Camera'),
                  ),
                  if (_cameraPermissionGranted == false) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _preflight,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Request Permissions Again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
