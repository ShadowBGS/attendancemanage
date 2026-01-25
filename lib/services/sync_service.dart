import 'dart:convert';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../db/database.dart';

/// Handles background sync of offline changes to server
class SyncService {
  final AppDatabase database;
  final String baseUrl;
  final Connectivity connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicSyncTimer;
  bool _isSyncing = false;

  SyncService({
    required this.database,
    required this.baseUrl,
    Connectivity? connectivity,
  }) : connectivity = connectivity ?? Connectivity();

  /// Start listening for connectivity changes and sync when online
  void startSyncListener() {
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      (result) {
        if (result.contains(ConnectivityResult.mobile) ||
            result.contains(ConnectivityResult.wifi)) {
          // Online detected, sync immediately
          syncPendingChanges();
        }
      },
    );

    // Also sync periodically every 30 seconds if online
    _periodicSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => syncPendingChanges(),
    );
  }

  /// Stop listening for changes
  void stopSyncListener() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
  }

  /// Sync all pending changes to server
  Future<void> syncPendingChanges() async {
    if (_isSyncing) return;

    try {
      _isSyncing = true;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final pending = await database.getPendingSyncItems();
      if (pending.isEmpty) return;

      for (final item in pending) {
        try {
          await _syncItem(item, idToken);
          await database.markSyncComplete(item.id);
        } catch (e) {
          // Increment retry count and log error
          await database.incrementSyncRetry(item.id, e.toString());
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync a single queue item to server
  Future<void> _syncItem(SyncQueueData item, String idToken) async {
    switch (item.entityType) {
      case 'session':
        await _syncSession(item, idToken);
      case 'attendance':
        await _syncAttendance(item, idToken);
      case 'course':
        await _syncCourse(item, idToken);
      default:
        throw Exception('Unknown entity type: ${item.entityType}');
    }
  }

  /// Sync session to /sync/push endpoint
  Future<void> _syncSession(SyncQueueData item, String idToken) async {
    final payload = jsonDecode(item.payload);
    final response = await http.post(
      Uri.parse(baseUrl).resolve('/sync/push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'ops': [
          {
            'op_id': 'session_${item.id}',
            'entity': 'session',
            'op': item.operation,
            'entity_id': payload['serverId'] ?? '',
            'payload': payload,
          }
        ]
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to sync session: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Sync attendance record to /sync/push endpoint
  Future<void> _syncAttendance(SyncQueueData item, String idToken) async {
    final payload = jsonDecode(item.payload);
    final response = await http.post(
      Uri.parse(baseUrl).resolve('/sync/push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'ops': [
          {
            'op_id': 'attendance_${item.id}',
            'entity': 'attendance',
            'op': item.operation,
            'entity_id': payload['serverId'] ?? '',
            'payload': payload,
          }
        ]
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to sync attendance: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Sync course to /sync/push endpoint
  Future<void> _syncCourse(SyncQueueData item, String idToken) async {
    final payload = jsonDecode(item.payload);
    final response = await http.post(
      Uri.parse(baseUrl).resolve('/sync/push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'ops': [
          {
            'op_id': 'course_${item.id}',
            'entity': 'course',
            'op': item.operation,
            'entity_id': payload['serverId'] ?? '',
            'payload': payload,
          }
        ]
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to sync course: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Pull latest data from server
  Future<void> pullLatestData(String idToken) async {
    try {
      final response = await http.get(
        Uri.parse(baseUrl).resolve('/sync/pull'),
        headers: {'Authorization': 'Bearer $idToken'},
      );

      if (response.statusCode == 200) {
        // TODO: Process changes from server and update local DB
        // This is where we'd merge server changes with local data
      }
    } catch (e) {
      // Silently fail - next sync will retry
    }
  }
}
