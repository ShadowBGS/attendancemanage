import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

import '../models/wifi_direct_payload.dart';
import '../services/wifi_direct_session_service.dart';
import '../db/database_provider.dart';
import '../db/database.dart';

class WifiDirectHostScreen extends StatefulWidget {
  final String courseCode;
  final String courseName;
  final int courseLocalId;

  const WifiDirectHostScreen({
    super.key,
    required this.courseCode,
    required this.courseName,
    required this.courseLocalId,
  });

  @override
  State<WifiDirectHostScreen> createState() => _WifiDirectHostScreenState();
}

class _WifiDirectHostScreenState extends State<WifiDirectHostScreen> {
  final WifiDirectSessionService _service = WifiDirectSessionService();
  WifiDirectPayload? _payload;
  bool _loading = true;
  String? _status;
  final List<AttendanceMessage> _attendees = [];
  final List<AttendanceMessage> _pendingPersist = [];
  List<P2pClientInfo> _clients = const [];
  StreamSubscription<AttendanceMessage>? _sub;
  StreamSubscription<List<P2pClientInfo>>? _clientSub;
  int? _sessionLocalId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final payload = await _service.startHostSession(
        courseCode: widget.courseCode,
        courseName: widget.courseName,
        onStatus: (s) {
          if (!mounted) return;
          setState(() => _status = s);
        },
      );
      if (!mounted) return;

      setState(() {
        _payload = payload;
        _loading = false;
        _status = null;
      });

      // Subscribe immediately; broadcast streams do not buffer events.
      _clientSub = _service.clientsStream.listen((clients) {
        if (!mounted) return;
        setState(() => _clients = clients);
      });

      _sub = _service.attendanceStream.listen((msg) async {
        // Always update UI first.
        if (mounted) {
          setState(() {
            _attendees.removeWhere((m) => m.studentId == msg.studentId);
            _attendees.add(msg);
          });
        }

        // If the local DB session isn't created yet, queue persistence.
        if (_sessionLocalId == null) {
          _pendingPersist.removeWhere((m) => m.studentId == msg.studentId);
          _pendingPersist.add(msg);
          return;
        }

        // Persist to local DB (best effort; never block UI updates).
        try {
          if (!mounted) return;
          final db = DatabaseProvider.of(context);
          final sid = _sessionLocalId;

          final existing = await db.getUserByFirebaseUid(msg.studentId);
          int studentLocalId;
          if (existing != null) {
            studentLocalId = existing.id;
          } else {
            studentLocalId = await db.upsertUser(
              UsersCompanion.insert(
                firebaseUid: msg.studentId,
                email: '',
                name: msg.studentName.isNotEmpty ? msg.studentName : msg.studentId,
                role: 'student',
                externalId: const Value(null),
                department: const Value(null),
                profileCompleted: const Value(false),
                lastSyncedAt: const Value(null),
              ),
            );
          }

          if (sid != null) {
            await db.markAttendance(
              AttendanceRecordsCompanion.insert(
                serverId: const Value(null),
                sessionId: sid,
                studentId: studentLocalId,
                status: 'present',
                markedAt: Value(msg.timestamp),
                faceVerified: const Value(false),
                verificationMethod: const Value('qr'),
                synced: const Value(false),
              ),
            );
          }
        } catch (_) {
          // Ignore DB errors here; live UI already updated.
        }
      });

      // Create local session (after listeners are attached).
      final db = DatabaseProvider.of(context);
      final sessionId = await db.insertSession(
        SessionsCompanion.insert(
          serverId: const Value(null),
          courseId: widget.courseLocalId,
          sessionType: 'lecture',
          startTime: DateTime.now(),
          endTime: const Value(null),
          location: const Value(null),
          status: 'active',
          synced: const Value(false),
        ),
      );
      if (!mounted) return;
      setState(() => _sessionLocalId = sessionId);

      // Flush any attendance received before session creation.
      for (final msg in List<AttendanceMessage>.from(_pendingPersist)) {
        try {
          final existing = await db.getUserByFirebaseUid(msg.studentId);
          int studentLocalId;
          if (existing != null) {
            studentLocalId = existing.id;
          } else {
            studentLocalId = await db.upsertUser(
              UsersCompanion.insert(
                firebaseUid: msg.studentId,
                email: '',
                name: msg.studentName.isNotEmpty ? msg.studentName : msg.studentId,
                role: 'student',
                externalId: const Value(null),
                department: const Value(null),
                profileCompleted: const Value(false),
                lastSyncedAt: const Value(null),
              ),
            );
          }

          await db.markAttendance(
            AttendanceRecordsCompanion.insert(
              serverId: const Value(null),
              sessionId: sessionId,
              studentId: studentLocalId,
              status: 'present',
              markedAt: Value(msg.timestamp),
              faceVerified: const Value(false),
              verificationMethod: const Value('qr'),
              synced: const Value(false),
            ),
          );
        } catch (_) {
          // Ignore; this is best-effort.
        }
      }
      _pendingPersist.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start session: $e')),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clientSub?.cancel();
    _service.stopHostSession();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Direct Session'),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_status ?? 'Starting host session...'),
                ],
              ),
            )
          : payload == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not start session'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.courseCode} · ${widget.courseName}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              QrImageView(
                                data: payload.toEncodedString(),
                                version: QrVersions.auto,
                                size: 220,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Students: Scan this QR to join',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'SSID: ${payload.ssid}\nPSK: ${payload.psk}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Chip(label: Text('Session: ${payload.sessionId}')),
                          const SizedBox(width: 8),
                          Chip(label: Text('Attendees: ${_attendees.length}')),
                          const SizedBox(width: 8),
                          Chip(label: Text('Connected: ${_clients.length}')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Live Attendees',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _attendees.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No one has joined yet.'),
                            )
                          : ListView.separated(
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: _attendees.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final a = _attendees[index];
                                return ListTile(
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(a.studentName.isNotEmpty ? a.studentName : a.studentId),
                                  subtitle: Text(
                                    'ID: ${a.studentId} · ${_formatTime(a.timestamp)}',
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
    );
  }

  String _formatTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
