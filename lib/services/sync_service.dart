import 'dart:convert';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:drift/drift.dart' show Value;
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

      // After pushing local changes, pull server deltas to keep local DB in sync
      try {
        await pullLatestData(idToken);
      } catch (e) {
        // Ignore pull errors; will retry later
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
        // Process server changes and upsert into local DB
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final changes = decoded['changes'] as Map<String, dynamic>?;
        if (changes == null) return;

        // Courses
        if (changes['courses'] is List) {
          for (final raw in changes['courses'] as List) {
            try {
              final map = raw as Map<String, dynamic>;
              final serverId = map['course_id']?.toString() ?? '';
              final code = map['course_code']?.toString() ?? '';
              final name = map['course_name']?.toString() ?? '';
              final description = map['description']?.toString();
              if (serverId.isEmpty) continue;
              await database.upsertCourseFromServer(
                serverId: serverId,
                code: code,
                name: name,
                description: description,
                lecturerId: map['lecturer_id'] is int ? map['lecturer_id'] as int : null,
              );
            } catch (_) {}
          }
        }

        // Sessions
        if (changes['sessions'] is List) {
          for (final raw in changes['sessions'] as List) {
            try {
              final map = raw as Map<String, dynamic>;
              final serverId = map['session_id']?.toString() ?? '';
              final courseServerId = map['course_id']?.toString() ?? '';
              if (serverId.isEmpty || courseServerId.isEmpty) continue;

              final course = await database.getCourseByServerId(courseServerId);
              if (course == null) continue;

              final startTime = DateTime.tryParse(map['start_time']?.toString() ?? '') ?? DateTime.now();
              final endTime = map['end_time'] != null ? DateTime.tryParse(map['end_time'].toString() ?? '') : null;
              final status = map['status']?.toString() ?? 'active';

              await database.upsertSessionFromServer(
                serverId: serverId,
                courseLocalId: course.id,
                startTime: startTime,
                endTime: endTime,
                status: status,
              );
            } catch (_) {}
          }
        }

        // Users/Students
        if (changes['users'] is List) {
          for (final raw in changes['users'] as List) {
            try {
              final map = raw as Map<String, dynamic>;
              final firebaseUid = map['firebase_uid']?.toString();
              if (firebaseUid == null || firebaseUid.isEmpty) continue;
              await database.upsertUser(
                UsersCompanion.insert(
                  firebaseUid: firebaseUid,
                  email: map['email']?.toString() ?? '',
                  name: map['name']?.toString() ?? firebaseUid,
                  role: map['role']?.toString() ?? 'student',
                  externalId: Value(map['external_id']?.toString()),
                  department: Value(map['department']?.toString()),
                  profileCompleted: Value(map['profile_completed'] as bool? ?? false),
                  lastSyncedAt: Value(DateTime.now()),
                ),
              );
            } catch (_) {}
          }
        }

        // Enrollments
        if (changes['enrollments'] is List) {
          for (final raw in changes['enrollments'] as List) {
            try {
              final map = raw as Map<String, dynamic>;
              final studentId = (map['student_id'] as int?);
              final courseId = (map['course_id'] as int?);
              if (studentId == null || courseId == null) continue;

              // Backend provides numeric IDs - try to resolve to local entries
              // Note: This assumes backend may also send firebase_uid or course server id in payload in the future.
              // Currently, if we can't resolve, skip.
            } catch (_) {}
          }
        }

        // Attendance
        if (changes['attendance'] is List) {
          for (final raw in changes['attendance'] as List) {
            try {
              final map = raw as Map<String, dynamic>;
              final attendanceId = map['attendance_id']?.toString() ?? '';
              final sessionId = map['session_id']?.toString() ?? '';
              final student = map['student'] as Map<String, dynamic>?;
              if (attendanceId.isEmpty || sessionId.isEmpty || student == null) continue;

              final session = await database.getSessionByServerId(sessionId);
              if (session == null) continue;

              // Ensure student exists in local DB
              final firebaseUid = student['firebase_uid']?.toString();
              int? studentLocalId;
              if (firebaseUid != null && firebaseUid.isNotEmpty) {
                final existing = await database.getUserByFirebaseUid(firebaseUid);
                if (existing != null) {
                  studentLocalId = existing.id;
                } else {
                  studentLocalId = await database.upsertUser(
                    UsersCompanion.insert(
                      firebaseUid: firebaseUid,
                      email: student['email']?.toString() ?? '',
                      name: student['name']?.toString() ?? firebaseUid,
                      role: 'student',
                      externalId: const Value(null),
                      department: const Value(null),
                      profileCompleted: const Value(false),
                      lastSyncedAt: Value(DateTime.now()),
                    ),
                  );
                }
              }

              if (studentLocalId == null) continue;

              final markedAt = DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now();
              final status = map['status']?.toString() ?? 'present';
              final verified = map['verified'] as bool? ?? false;

              await database.upsertAttendanceFromServer(
                serverId: attendanceId,
                sessionLocalId: session.id,
                studentLocalId: studentLocalId,
                status: status,
                markedAt: markedAt,
                faceVerified: verified,
              );
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      // Silently fail - next sync will retry
    }
  }
}
