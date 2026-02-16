import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import '../models/wifi_direct_payload.dart';

/// Handles WiFi Direct hosting (lecturer) and client join (student).
class WifiDirectSessionService {
  final FlutterP2pHost _host = FlutterP2pHost();
  StreamSubscription<String>? _messageSub;
  StreamSubscription<HotspotHostState>? _stateSub;
  StreamSubscription<List<P2pClientInfo>>? _clientsSub;

  final StreamController<AttendanceMessage> _attendanceController = StreamController.broadcast();
  final StreamController<List<P2pClientInfo>> _clientsController = StreamController.broadcast();

  WifiDirectPayload? _currentPayload;

  Stream<AttendanceMessage> get attendanceStream => _attendanceController.stream;
  Stream<List<P2pClientInfo>> get clientsStream => _clientsController.stream;
  WifiDirectPayload? get activePayload => _currentPayload;

  Future<WifiDirectPayload> startHostSession({
    required String courseCode,
    required String courseName,
    void Function(String status)? onStatus,
    Duration createTimeout = const Duration(seconds: 30),
  }) async {
    onStatus?.call('Initializing host interface...');
    await _host.initialize();
    // QR-based join does not require BLE advertising; avoid Bluetooth permissions.
    onStatus?.call('Checking permissions and services...');
    await _ensurePermissions(_host, requireBluetooth: false, requireStorage: false);

    HotspotHostState state;
    onStatus?.call('Creating hotspot...');

    try {
      state = await _host.createGroup(
        advertise: false,
        timeout: createTimeout,
      );
    } on TimeoutException {
      // Try one retry with a slightly longer timeout to tolerate slow devices
      onStatus?.call('Timed out waiting for hotspot state. Retrying...');
      try {
        await Future.delayed(const Duration(seconds: 1));
        state = await _host.createGroup(
          advertise: false,
          timeout: const Duration(seconds: 60),
        );
      } on TimeoutException catch (_) {
        // Surface a helpful error message
        throw TimeoutException('Failed to create Wi‑Fi hotspot. This can happen if the device does not support tethering, Wi‑Fi is disabled, hotspot/tethering is ON (must be OFF for WiFi Direct), or system prompts (e.g. confirm tethering) were not accepted. Please ensure Wi‑Fi is ON, mobile hotspot/tethering is OFF, and try again.');
      }
    }

    // Verify hotspot was actually created successfully
    if ((state.ssid ?? '').isEmpty && (state.preSharedKey ?? '').isEmpty) {
      throw Exception('Hotspot creation failed: No SSID or PSK received. This may indicate hostspot/tethering is enabled or WiFi is disabled.');
    }

    final String stateSsid = state.ssid ?? '';
    final String statePsk = state.preSharedKey ?? '';
    final String ssid = stateSsid.isNotEmpty ? stateSsid : 'ATT-${DateTime.now().millisecondsSinceEpoch}';
    final String psk = statePsk.isNotEmpty ? statePsk : '12345678';

    final payload = WifiDirectPayload(
      sessionId: _makeSessionId(),
      courseCode: courseCode,
      courseName: courseName,
      ssid: ssid,
      psk: psk,
    );
    _currentPayload = payload;

    _stateProber();
    _listenForClients();
    _listenForMessages();

    onStatus?.call('Hotspot created. Ready to accept clients.');
    return payload;
  }

  Future<void> stopHostSession() async {
    print('🛑 [WifiDirectSessionService] Stopping host session...');
    
    await _messageSub?.cancel();
    print('   ✓ Cancelled message subscription');
    
    await _stateSub?.cancel();
    print('   ✓ Cancelled state subscription');
    
    await _clientsSub?.cancel();
    print('   ✓ Cancelled clients subscription');
    
    _messageSub = null;
    _stateSub = null;
    _clientsSub = null;

    print('   🔌 Removing WiFi Direct group (hotspot)...');
    await _host.removeGroup();
    print('   ✅ WiFi Direct group removed');
    
    _currentPayload = null;

    if (!_clientsController.isClosed) {
      _clientsController.add(const []);
    }
    
    print('✅ [WifiDirectSessionService] Host session stopped');
  }

  void dispose() {
    print('🔴 [WifiDirectSessionService] Disposing...');
    unawaited(_messageSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_clientsSub?.cancel());
    _attendanceController.close();
    _clientsController.close();
    _host.dispose();
    print('✅ [WifiDirectSessionService] Disposed');
  }

  void _stateProber() {
    _stateSub?.cancel();
    _stateSub = _host.streamHotspotState().listen((event) {
      if (event.failureReason != null) {
        // no-op
      }
    });
  }

  void _listenForMessages() {
    _messageSub?.cancel();
    _messageSub = _host.streamReceivedTexts().listen((text) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) return;

        if (decoded['type']?.toString() == 'ack') return;

        final msg = AttendanceMessage.fromJson(decoded);
        if (msg.sessionId.isEmpty || msg.studentId.isEmpty) return;
        _attendanceController.add(msg);

        unawaited(
          _host.broadcastText(
            jsonEncode({
              'type': 'ack',
              'sessionId': msg.sessionId,
              'studentId': msg.studentId,
              if (msg.requestId != null && msg.requestId!.isNotEmpty) 'requestId': msg.requestId,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          ),
        );
      } catch (_) {
        // ignore malformed
      }
    });
  }

  void _listenForClients() {
    _clientsSub?.cancel();
    _clientsSub = _host.streamClientList().listen((clients) {
      _clientsController.add(clients);
    });
  }

  String _makeSessionId() => 'sess-${DateTime.now().millisecondsSinceEpoch}';
}

class WifiDirectClientService {
  final FlutterP2pClient _client = FlutterP2pClient();
  bool _initialized = false;

  Future<void> preflight({
    void Function(String status)? onStatus,
    Duration initializeTimeout = const Duration(seconds: 10),
    Duration permissionsTimeout = const Duration(seconds: 45),
  }) async {
    onStatus?.call('Initializing WiFi Direct...');
    if (!_initialized) {
      await _client.initialize().timeout(initializeTimeout);
      _initialized = true;
    }

    onStatus?.call('Checking Wi‑Fi/Location permissions...');
    // Credential-based connect does not require BLE; avoid Bluetooth permissions.
    await _ensurePermissions(_client, requireBluetooth: false, requireStorage: false)
        .timeout(permissionsTimeout);
    onStatus?.call('Ready to scan.');
  }

  Future<AttendanceSendResult> joinAndSend({
    required WifiDirectPayload payload,
    required String studentId,
    required String studentName,
    String? matricNumber,
    void Function(String status)? onStatus,
    Duration initializeTimeout = const Duration(seconds: 10),
    Duration permissionsTimeout = const Duration(seconds: 30),
    Duration connectTimeout = const Duration(seconds: 25),
    Duration sendTimeout = const Duration(seconds: 10),
    bool waitForAck = true,
    Duration ackTimeout = const Duration(seconds: 8),
  }) async {
    try {
      onStatus?.call('Initializing WiFi Direct...');
      if (!_initialized) {
        await _client.initialize().timeout(initializeTimeout);
        _initialized = true;
      }

      onStatus?.call('Checking device permissions...');
      // Credential-based connect does not require BLE; avoid Bluetooth permissions.
      await _ensurePermissions(_client, requireBluetooth: false, requireStorage: false)
          .timeout(permissionsTimeout);

      onStatus?.call('Joining ${payload.ssid}...');
      await _client.connectWithCredentials(
        payload.ssid,
        payload.psk,
        timeout: connectTimeout,
      );

      final requestId = 'req-${DateTime.now().millisecondsSinceEpoch}-$studentId';

      Completer<bool>? ackCompleter;
      StreamSubscription<String>? ackSub;
      Timer? ackTimer;
      void startAckListener() {
        ackCompleter = Completer<bool>();
        ackSub = _client.streamReceivedTexts().listen((text) {
          try {
            final decoded = jsonDecode(text);
            if (decoded is! Map<String, dynamic>) return;
            if (decoded['type']?.toString() != 'ack') return;
            final sid = decoded['sessionId']?.toString() ?? '';
            final uid = decoded['studentId']?.toString() ?? '';
            final rid = decoded['requestId']?.toString() ?? '';
            if (sid == payload.sessionId && uid == studentId && rid == requestId) {
              if (ackCompleter != null && !(ackCompleter!.isCompleted)) {
                ackCompleter!.complete(true);
              }
            }
          } catch (_) {
            // ignore
          }
        });
        ackTimer = Timer(ackTimeout, () {
          if (ackCompleter != null && !(ackCompleter!.isCompleted)) {
            ackCompleter!.complete(false);
          }
        });
      }

      void stopAckListener() {
        ackTimer?.cancel();
        unawaited(ackSub?.cancel());
      }

      final msg = AttendanceMessage(
        sessionId: payload.sessionId,
        studentId: studentId,
        studentName: studentName,
        matricNumber: matricNumber,
        timestamp: DateTime.now(),
        requestId: requestId,
      );

      // Give the system a brief moment after connect to stabilise the Wi‑Fi link.
      onStatus?.call('Connected — finalising network setup...');
      try {
        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {
        // ignore
      }

      // Attempt sending with retries to tolerate brief disconnects during OS-level connect handoff.
      const int maxAttempts = 3;
      String? lastError;
      bool sentOk = false;

      for (int attempt = 1; attempt <= maxAttempts && !sentOk; attempt++) {
        if (waitForAck) startAckListener();
        try {
          onStatus?.call('Sending attendance (attempt $attempt/$maxAttempts)...');
          await _client.broadcastText(jsonEncode(msg.toJson())).timeout(sendTimeout);

          if (waitForAck) {
            onStatus?.call('Waiting for lecturer confirmation...');
            final confirmed = await (ackCompleter?.future ?? Future<bool>.value(false));
            stopAckListener();
            if (confirmed) {
              sentOk = true;
              break;
            } else {
              lastError = 'No confirmation received from lecturer.';
            }
          } else {
            // No ACK required — success if no exception
            sentOk = true;
            break;
          }
        } on TimeoutException catch (e) {
          lastError = e.message ?? 'Operation timed out while sending.';
          stopAckListener();
        } catch (e) {
          lastError = e.toString();
          stopAckListener();
        }

        if (!sentOk && attempt < maxAttempts) {
          onStatus?.call('Send failed, retrying (${attempt + 1}/$maxAttempts)...');
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (sentOk) {
        return AttendanceSendResult(sent: true);
      }

      return AttendanceSendResult(
        sent: false,
        error: lastError ?? 'Failed to send attendance. The device may not have stayed connected long enough; ensure you accept the system connection prompt and remain connected.',
      );
    } on TimeoutException catch (e) {
      return AttendanceSendResult(sent: false, error: e.message ?? 'Operation timed out');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Future not completed')) {
        return AttendanceSendResult(
          sent: false,
          error: 'Connection was not completed. Tap Connect on the system prompt and keep the lecturer session running.',
        );
      }
      return AttendanceSendResult(sent: false, error: msg);
    } finally {
      // Best-effort disconnect to return device to normal state.
      unawaited(_client.disconnect());
    }
  }

  Future<void> dispose() async {
    await _client.disconnect();
    await _client.dispose();
    _initialized = false;
  }
}

Future<void> _ensurePermissions(
  dynamic iface, {
  bool requireBluetooth = true,
  bool requireStorage = true,
}) async {
  try {
    final bool? p2pOk = await _tryBool(iface.checkP2pPermissions, timeout: const Duration(seconds: 5));
    if (p2pOk == false) {
      await _tryVoid(
        iface.askP2pPermissions,
        timeout: const Duration(seconds: 60),
        label: 'requesting Wi‑Fi Direct permissions (respond to the system prompt)',
      );
    }

    if (requireBluetooth) {
      final bool? btPermOk = await _tryBool(iface.checkBluetoothPermissions, timeout: const Duration(seconds: 5));
      if (btPermOk == false) {
        await _tryVoid(
          iface.askBluetoothPermissions,
          timeout: const Duration(seconds: 60),
          label: 'requesting Bluetooth permissions (respond to the system prompt)',
        );
      }
    }

    if (requireStorage) {
      final bool? storageOk = await _tryBool(iface.checkStoragePermission, timeout: const Duration(seconds: 5));
      if (storageOk == false) {
        await _tryVoid(
          iface.askStoragePermission,
          timeout: const Duration(seconds: 60),
          label: 'requesting storage permission (respond to the system prompt)',
        );
      }
    }

    final bool? wifiOk = await _tryBool(iface.checkWifiEnabled, timeout: const Duration(seconds: 5));
    if (wifiOk == false) {
      await _tryVoid(iface.enableWifiServices, timeout: const Duration(seconds: 20), label: 'enabling Wi-Fi services');
    }

    final bool? locOk = await _tryBool(iface.checkLocationEnabled, timeout: const Duration(seconds: 5));
    if (locOk == false) {
      await _tryVoid(iface.enableLocationServices, timeout: const Duration(seconds: 20), label: 'enabling Location services');
    }

    if (requireBluetooth) {
      final bool? btOk = await _tryBool(iface.checkBluetoothEnabled, timeout: const Duration(seconds: 5));
      if (btOk == false) {
        await _tryVoid(iface.enableBluetoothServices,
            timeout: const Duration(seconds: 30), label: 'enabling Bluetooth services');
      }
    }
  } on TimeoutException {
    rethrow;
  } catch (e) {
    // Some devices/OS versions may still allow operations even if checks fail.
    debugPrint('WiFi Direct permission check warning: $e');
  }
}

Future<bool?> _tryBool(
  Future<bool> Function() fn, {
  required Duration timeout,
}) async {
  try {
    return await fn().timeout(timeout);
  } on NoSuchMethodError {
    return null;
  }
}

Future<void> _tryVoid(
  Future<void> Function() fn, {
  required Duration timeout,
  required String label,
}) async {
  try {
    await fn().timeout(timeout);
  } on NoSuchMethodError {
    // Method not implemented on this platform/device.
  } on TimeoutException catch (e) {
    throw TimeoutException('Timed out while $label', e.duration);
  }
}

class AttendanceMessage {
  final String sessionId;
  final String studentId;
  final String studentName;
  final String? matricNumber; // Student's matric/external ID for offline display
  final DateTime timestamp;
  final String? requestId;

  AttendanceMessage({
    required this.sessionId,
    required this.studentId,
    required this.studentName,
    this.matricNumber,
    required this.timestamp,
    this.requestId,
  });

  factory AttendanceMessage.fromJson(Map<String, dynamic> map) {
    return AttendanceMessage(
      sessionId: map['sessionId']?.toString() ?? '',
      studentId: map['studentId']?.toString() ?? '',
      studentName: map['studentName']?.toString() ?? '',
      matricNumber: map['matricNumber']?.toString(),
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      requestId: map['requestId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'studentId': studentId,
        'studentName': studentName,
        if (matricNumber != null) 'matricNumber': matricNumber,
        'timestamp': timestamp.toIso8601String(),
        if (requestId != null && requestId!.isNotEmpty) 'requestId': requestId,
      };
}

class AttendanceSendResult {
  final bool sent;
  final String? error;

  AttendanceSendResult({required this.sent, this.error});
}
