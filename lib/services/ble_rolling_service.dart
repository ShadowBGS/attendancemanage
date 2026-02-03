import 'dart:async';

/// Skeleton for BLE rolling-code advertising/scanning (offline proof collection).
/// Branch: feature/ble-offline-rolling
/// TODO: wire up flutter_blue_plus + HMAC rolling codes + local log persistence.
class BleRollingService {
  /// Lecturer: start advertising rolling codes derived from session seed.
  Future<void> startAdvertising({required String sessionId}) async {
    // TODO: implement BLE advertise with rotating payload
  }

  /// Lecturer: stop advertising.
  Future<void> stopAdvertising() async {
    // TODO: implement
  }

  /// Student: scan and log rolling codes + RSSI for offline proof.
  Stream<RollingObservation> scanRollingCodes() async* {
    // TODO: implement BLE scan and yield observations
  }
}

/// Captures a single rolling-code observation with RSSI and timestamp.
class RollingObservation {
  final String code;
  final int rssi;
  final DateTime timestamp;

  const RollingObservation({required this.code, required this.rssi, required this.timestamp});
}
