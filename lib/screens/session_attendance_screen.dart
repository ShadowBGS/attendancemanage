import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../db/database.dart';
import '../db/database_provider.dart';

class SessionAttendanceScreen extends StatefulWidget {
  final String courseCode;
  final String courseName;
  final int sessionLocalId;
  final String sessionServerId;

  const SessionAttendanceScreen({
    super.key,
    required this.courseCode,
    required this.courseName,
    required this.sessionLocalId,
    required this.sessionServerId,
  });

  @override
  State<SessionAttendanceScreen> createState() => _SessionAttendanceScreenState();
}

class _SessionAttendanceScreenState extends State<SessionAttendanceScreen> {
  bool _loading = false;
  List<AttendanceWithStudent> _rows = const [];

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _refreshFromBackend();
  }

  String _backendBaseUrl() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    return overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
  }

  Future<void> _loadLocal() async {
    final db = DatabaseProvider.of(context);
    final rows = await db.getAttendanceWithStudentForSession(widget.sessionLocalId);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _refreshFromBackend() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final response = await http
          .get(
            Uri.parse(_backendBaseUrl())
                .resolve('/sessions/${widget.sessionServerId}/attendance'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return;

      final db = DatabaseProvider.of(context);

      for (final item in decoded) {
        if (item is! Map) continue;

        final attendanceId = item['attendance_id']?.toString();
        final status = item['status']?.toString() ?? 'present';
        final timestampIso = item['timestamp']?.toString();
        final verified = item['verified'] == true;

        final student = item['student'];
        if (attendanceId == null || student is! Map) continue;

        final studentId = student['student_id'];
        final firebaseUid = (student['firebase_uid']?.toString()) ?? 'unknown:$studentId';
        final name = student['name']?.toString() ?? 'Unknown';
        final email = student['email']?.toString() ?? '';
        final matricNo = student['matric_no']?.toString();
        final department = student['department']?.toString();

        final studentLocalId = await db.upsertUser(
          UsersCompanion(
            firebaseUid: Value(firebaseUid),
            email: Value(email.isNotEmpty ? email : 'unknown@example.com'),
            name: Value(name),
            role: const Value('student'),
            externalId: Value(matricNo),
            department: Value(department),
            profileCompleted: const Value(true),
            lastSyncedAt: Value(DateTime.now()),
          ),
        );

        final markedAt = timestampIso != null
            ? (DateTime.tryParse(timestampIso)?.toLocal() ?? DateTime.now())
            : DateTime.now();

        await db.upsertAttendanceFromServer(
          serverId: attendanceId,
          sessionLocalId: widget.sessionLocalId,
          studentLocalId: studentLocalId,
          status: status,
          markedAt: markedAt,
          faceVerified: verified,
        );
      }

      await _loadLocal();
    } catch (_) {
      // Ignore; local still shown.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.courseCode} · ${widget.courseName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Session ${widget.sessionServerId}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loading ? null : _refreshFromBackend,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('No attendance records yet'))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final status = row.record.status;
                        final subtitleBits = <String>[];
                        if (row.student.externalId != null && row.student.externalId!.isNotEmpty) {
                          subtitleBits.add(row.student.externalId!);
                        }
                        if (row.student.email.isNotEmpty) subtitleBits.add(row.student.email);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.withOpacity(0.1),
                            child: const Icon(Icons.person, color: Colors.green),
                          ),
                          title: Text(row.student.name),
                          subtitle: Text(subtitleBits.isNotEmpty ? subtitleBits.join(' · ') : 'Student'),
                          trailing: Text(
                            status,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: status == 'present' ? Colors.green : Colors.orange,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
