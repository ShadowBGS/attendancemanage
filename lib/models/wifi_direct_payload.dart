import 'dart:convert';

/// Encapsulates the data encoded in the session QR for WiFi Direct.
class WifiDirectPayload {
  final String sessionId;
  final String courseCode;
  final String courseName;
  final String ssid;
  final String psk;

  const WifiDirectPayload({
    required this.sessionId,
    required this.courseCode,
    required this.courseName,
    required this.ssid,
    required this.psk,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'courseCode': courseCode,
        'courseName': courseName,
        'ssid': ssid,
        'psk': psk,
      };

  String toEncodedString() => jsonEncode(toJson());

  static WifiDirectPayload fromJson(Map<String, dynamic> map) {
    return WifiDirectPayload(
      sessionId: map['sessionId']?.toString() ?? '',
      courseCode: map['courseCode']?.toString() ?? '',
      courseName: map['courseName']?.toString() ?? '',
      ssid: map['ssid']?.toString() ?? '',
      psk: map['psk']?.toString() ?? '',
    );
  }

  static WifiDirectPayload? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return fromJson(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
