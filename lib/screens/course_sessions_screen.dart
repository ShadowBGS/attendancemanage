import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../db/database.dart';
import '../db/database_provider.dart';
import 'session_attendance_screen.dart';

class CourseSessionsScreen extends StatefulWidget {
  final int courseLocalId;
  final String? courseServerId;
  final String courseCode;
  final String courseName;

  const CourseSessionsScreen({
    super.key,
    required this.courseLocalId,
    required this.courseServerId,
    required this.courseCode,
    required this.courseName,
  });

  @override
  State<CourseSessionsScreen> createState() => _CourseSessionsScreenState();
}

class _CourseSessionsScreenState extends State<CourseSessionsScreen> {
  bool _loading = false;
  List<Session> _sessions = const [];

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
    final sessions = await db.getSessionsByCourse(widget.courseLocalId);
    if (!mounted) return;
    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    setState(() => _sessions = sessions);
  }

  Future<void> _refreshFromBackend() async {
    final serverCourseId = widget.courseServerId;
    if (serverCourseId == null || serverCourseId.isEmpty) return;
    if (_loading) return;

    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final response = await http
          .get(
            Uri.parse(_backendBaseUrl()).resolve('/courses/$serverCourseId/sessions'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return;

      final db = DatabaseProvider.of(context);
      for (final item in decoded) {
        if (item is! Map) continue;
        final serverSessionId = item['session_id']?.toString();
        final startIso = item['start_time']?.toString();
        final endIso = item['end_time']?.toString();
        if (serverSessionId == null || startIso == null) continue;

        final startTime = DateTime.tryParse(startIso)?.toLocal() ?? DateTime.now();
        final endTime = endIso != null ? DateTime.tryParse(endIso)?.toLocal() : null;
        final now = DateTime.now();
        final status = (endTime != null && now.isAfter(endTime))
            ? 'completed'
            : ((endTime != null && now.isBefore(endTime)) ? 'active' : 'active');

        await db.upsertSessionFromServer(
          serverId: serverSessionId,
          courseLocalId: widget.courseLocalId,
          startTime: startTime,
          endTime: endTime,
          status: status,
        );
      }

      await _loadLocal();
    } catch (_) {
      // Ignore.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
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
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Sessions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              child: _sessions.isEmpty
                  ? const Center(child: Text('No sessions yet'))
                  : ListView.separated(
                      itemCount: _sessions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = _sessions[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.withOpacity(0.1),
                            child: const Icon(Icons.event_note, color: Colors.orange),
                          ),
                          title: Text('Session ${s.serverId ?? s.id}'),
                          subtitle: Text('${_formatDate(s.startTime)} · ${s.status}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: s.serverId == null
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SessionAttendanceScreen(
                                        courseCode: widget.courseCode,
                                        courseName: widget.courseName,
                                        sessionLocalId: s.id,
                                        sessionServerId: s.serverId!,
                                      ),
                                    ),
                                  );
                                },
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
