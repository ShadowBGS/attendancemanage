import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../db/database.dart';
import '../db/database_provider.dart';
import '../models/wifi_direct_payload.dart';
import 'session_attendance_screen.dart';
import 'lecturer_session_detail_screen.dart';

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
  TextEditingController _searchController = TextEditingController();
  List<Session> _filteredSessions = const [];

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _refreshFromBackend();
    _searchController.addListener(_filterSessions);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterSessions() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredSessions = _sessions);
    } else {
      setState(() {
        _filteredSessions = _sessions
            .where((s) => s.sessionType.toLowerCase().contains(query))
            .toList();
      });
    }
  }

  String _backendBaseUrl() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    return overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
  }

  Future<void> _loadLocal() async {
    try {
      final db = DatabaseProvider.of(context);
      var sessions = await db.getSessionsByCourse(widget.courseLocalId);
      
      // Debug: log all sessions to check what's in the database
      if (sessions.isEmpty) {
        final allSessions = await db.getAllSessions();
        print('CourseSessionsScreen: Looking for course ID ${widget.courseLocalId}');
        print('CourseSessionsScreen: Found ${allSessions.length} total sessions in database');
        for (var s in allSessions.take(5)) {
          print('  - Session ${s.id}: courseId=${s.courseId}, serverId=${s.serverId}');
        }
      }
      
      if (!mounted) return;
      sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
      setState(() {
        _sessions = sessions;
        _filteredSessions = sessions;
      });
    } catch (e) {
      print('Error loading sessions: $e');
      if (mounted) {
        setState(() {
          _sessions = [];
          _filteredSessions = [];
        });
      }
    }
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
    } catch (e) {
      print('Error refreshing sessions from backend: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<int> _getAttendanceCount(int sessionId) async {
    final db = DatabaseProvider.of(context);
    final attendance = await db.getAttendanceBySessionId(sessionId);
    return attendance.length;
  }

  IconData _getSessionIcon(int index) {
    final icons = [
      Icons.touch_app_outlined,
      Icons.calculate_outlined,
      Icons.touch_app_outlined,
      Icons.sentiment_satisfied_outlined,
    ];
    return icons[index % icons.length];
  }

  String _formatSessionDate(DateTime dt) {
    final d = dt.toLocal();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Blue Header
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: primaryBlue,
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text(
                          'Session History',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.search, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshFromBackend,
                child: _filteredSessions.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_note_outlined,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _sessions.isEmpty ? 'No sessions yet' : 'No sessions found',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredSessions.length,
                      itemBuilder: (context, index) {
                        final s = _filteredSessions[index];
                        final isActive = s.status == 'active';

                        return GestureDetector(
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
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Icon
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: primaryBlue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getSessionIcon(index),
                                    color: primaryBlue,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Session Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Session ${index + 1}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today_outlined,
                                            size: 16,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _formatSessionDate(s.startTime),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Student Count
                                FutureBuilder<int>(
                                  future: _getAttendanceCount(s.id),
                                  builder: (context, snapshot) {
                                    final count = snapshot.data ?? 0;
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$count Students',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: primaryBlue,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey,
                                          size: 24,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
