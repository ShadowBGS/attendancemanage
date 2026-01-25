import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../db/database.dart';
import '../db/database_provider.dart';

class CourseStudentsScreen extends StatefulWidget {
  final int courseLocalId;
  final String? courseServerId;
  final String courseCode;
  final String courseName;

  const CourseStudentsScreen({
    super.key,
    required this.courseLocalId,
    required this.courseServerId,
    required this.courseCode,
    required this.courseName,
  });

  @override
  State<CourseStudentsScreen> createState() => _CourseStudentsScreenState();
}

class _CourseStudentsScreenState extends State<CourseStudentsScreen> {
  bool _loading = false;
  List<User> _students = const [];

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
    final students = await db.getStudentsForCourse(widget.courseLocalId);
    if (!mounted) return;
    setState(() => _students = students);
  }

  Future<void> _refreshFromBackend() async {
    final serverCourseId = widget.courseServerId;
    if (serverCourseId == null || serverCourseId.isEmpty) return;
    if (_loading) return;

    setState(() => _loading = true);
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final response = await http
          .get(
            Uri.parse(_backendBaseUrl()).resolve('/courses/$serverCourseId/students'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return;

      final db = DatabaseProvider.of(context);
      for (final item in decoded) {
        if (item is! Map) continue;

        final studentId = item['student_id'];
        final firebaseUid = (item['firebase_uid']?.toString()) ?? 'unknown:$studentId';
        final name = item['name']?.toString() ?? 'Unknown';
        final email = item['email']?.toString() ?? '';
        final matricNo = item['matric_no']?.toString();
        final department = item['department']?.toString();

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

        await db.ensureEnrollment(
          studentLocalId: studentLocalId,
          courseLocalId: widget.courseLocalId,
        );
      }

      await _loadLocal();
    } catch (_) {
      // Ignore.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
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
                  'Enrolled Students',
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
              child: _students.isEmpty
                  ? const Center(child: Text('No students yet'))
                  : ListView.separated(
                      itemCount: _students.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = _students[index];
                        final subtitleBits = <String>[];
                        if (s.externalId != null && s.externalId!.isNotEmpty) {
                          subtitleBits.add(s.externalId!);
                        }
                        if (s.email.isNotEmpty) subtitleBits.add(s.email);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            child: const Icon(Icons.person, color: Colors.blue),
                          ),
                          title: Text(s.name),
                          subtitle: Text(subtitleBits.isNotEmpty ? subtitleBits.join(' · ') : 'Student'),
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
