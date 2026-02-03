import 'dart:async';

/// Skeleton for BLE-based proximity pings with backend validation.
/// Branch: feature/ble-online-pings
/// TODO: wire up flutter_blue_plus + HTTPS ping client.
class BlePingService {
  /// Lecturer: advertise session code for students to detect.
  Future<void> startAdvertising({required String sessionId}) async {
    // TODO: implement BLE advertise
  }

  Future<void> stopAdvertising() async {
    // TODO: implement
  }

  /// Student: scan advertiser and send periodic pings to backend.
  Stream<PingSample> scanAndPing({required String sessionId}) async* {
    // TODO: implement BLE scan + schedule HTTPS pings
  }
}

/// Represents a proximity sample sent to backend.
class PingSample {
  final String advertiserId;
  final int rssi;
  final DateTime timestamp;

  const PingSample({required this.advertiserId, required this.rssi, required this.timestamp});
}
