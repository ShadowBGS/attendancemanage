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
    const Color primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Students Joined (${_rows.length})'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search name or matric no...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),

          // Student List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshFromBackend,
              child: _rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 200),
                        Center(child: Text('No attendance records yet')),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final initials = _getInitials(row.student.name);
                      final color = _getColorForIndex(index);
                      final matricNumber = row.student.externalId;
                      final program = row.student.department ?? 'Computer Science';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Student Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.student.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    matricNumber != null && matricNumber.isNotEmpty
                                        ? '$matricNumber · $program'
                                        : program,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Timestamp
                            Text(
                              _formatTime(row.record.markedAt),
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

  Color _getColorForIndex(int index) {
    final colors = [
      const Color(0xFF0D47A1),
      const Color(0xFF7B1FA2),
      const Color(0xFF00ACC1),
      const Color(0xFFFF6F00),
      const Color(0xFFD32F2F),
      const Color(0xFF388E3C),
    ];
    return colors[index % colors.length];
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
