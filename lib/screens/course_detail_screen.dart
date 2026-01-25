import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../db/database_provider.dart';

import 'course_students_screen.dart';
import 'course_sessions_screen.dart';
import 'session_attendance_screen.dart';

class CourseDetailScreen extends StatefulWidget {
  final String courseCode;
  final String courseName;
  final int courseLocalId;
  final String? courseServerId;

  const CourseDetailScreen({
    super.key,
    required this.courseCode,
    required this.courseName,
    required this.courseLocalId,
    required this.courseServerId,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  bool _isLoading = false;
  int _enrolledStudents = 0;

  @override
  void initState() {
    super.initState();
    _loadCourseDetails();
  }

  Future<void> _loadCourseDetails() async {
    try {
      final db = DatabaseProvider.of(context);
      final localStudents = await db.getStudentsForCourse(widget.courseLocalId);
      if (mounted) setState(() => _enrolledStudents = localStudents.length);

      final serverId = widget.courseServerId;
      if (serverId == null || serverId.isEmpty) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final response = await http
          .get(
            Uri.parse(_backendBaseUrl()).resolve('/courses/$serverId/students'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && mounted) {
          setState(() => _enrolledStudents = decoded.length);
        }
      }
    } catch (_) {
      // Ignore; local count is still shown.
    }
  }

  String _backendBaseUrl() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    return overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _startClass() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('Not signed in.');
        return;
      }

      final idToken = await user.getIdToken();
      if (idToken == null) {
        _showError('Could not get authentication token.');
        return;
      }

      final serverCourseId = widget.courseServerId;
      if (serverCourseId == null || serverCourseId.isEmpty) {
        _showError('Course is not synced to server yet.');
        return;
      }

      final response = await http
          .post(
            Uri.parse(_backendBaseUrl()).resolve('/sessions/create'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'course_id': int.parse(serverCourseId),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        String msg = 'Failed to start class.';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['detail'] != null) msg = decoded['detail'].toString();
        } catch (_) {}
        _showError(msg);
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        _showError('Invalid server response.');
        return;
      }

      final serverSessionId = decoded['session_id']?.toString();
      final startIso = decoded['start_time']?.toString();
      final endIso = decoded['end_time']?.toString();
      if (serverSessionId == null || startIso == null) {
        _showError('Invalid session response.');
        return;
      }

      final startTime = DateTime.tryParse(startIso)?.toLocal() ?? DateTime.now();
      final endTime = endIso != null ? DateTime.tryParse(endIso)?.toLocal() : null;
      final now = DateTime.now();
      final status = (endTime != null && now.isAfter(endTime))
          ? 'completed'
          : ((endTime != null && now.isBefore(endTime)) ? 'active' : 'active');

      final db = DatabaseProvider.of(context);
      final localSessionId = await db.upsertSessionFromServer(
        serverId: serverSessionId,
        courseLocalId: widget.courseLocalId,
        startTime: startTime,
        endTime: endTime,
        status: status,
      );

      _showSuccess('Class started successfully!');

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionAttendanceScreen(
            courseCode: widget.courseCode,
            courseName: widget.courseName,
            sessionLocalId: localSessionId,
            sessionServerId: serverSessionId,
          ),
        ),
      );
    } catch (e) {
      _showError('Failed to start class: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editCourse() async {
    // TODO: Implement edit course modal/screen
    _showSuccess('Edit course coming soon!');
  }

  @override
  Widget build(BuildContext context) {
    const Color accentColor = Colors.blue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Course Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editCourse,
            tooltip: 'Edit Course',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Course Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor, accentColor.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      widget.courseCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.courseName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Course ID: ${widget.courseServerId ?? widget.courseLocalId}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Course Stats
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.people_outline,
                      label: 'Enrolled Students',
                      value: _enrolledStudents.toString(),
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.calendar_today_outlined,
                      label: 'Active Sessions',
                      value: '0',
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),

            // Course Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.list_outlined,
                    title: 'View Roster',
                    subtitle: 'See enrolled students',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CourseStudentsScreen(
                            courseLocalId: widget.courseLocalId,
                            courseServerId: widget.courseServerId,
                            courseCode: widget.courseCode,
                            courseName: widget.courseName,
                          ),
                        ),
                      );
                    },
                  ),
                  _ActionTile(
                    icon: Icons.history_outlined,
                    title: 'Session History',
                    subtitle: 'View past sessions',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CourseSessionsScreen(
                            courseLocalId: widget.courseLocalId,
                            courseServerId: widget.courseServerId,
                            courseCode: widget.courseCode,
                            courseName: widget.courseName,
                          ),
                        ),
                      );
                    },
                  ),
                  _ActionTile(
                    icon: Icons.settings_outlined,
                    title: 'Course Settings',
                    subtitle: 'Configure course options',
                    onTap: _editCourse,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Info Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accentColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: accentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tap "Start Class" to begin an attendance session.',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),

      // Start Class Button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _startClass,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                disabledBackgroundColor: const Color(0xFFFFFFFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              icon: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.play_circle_filled),
              label: const Text(
                'Start Class',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.blue),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}
