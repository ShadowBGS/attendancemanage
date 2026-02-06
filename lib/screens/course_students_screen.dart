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
  TextEditingController _searchController = TextEditingController();
  List<User> _filteredStudents = const [];

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _refreshFromBackend();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredStudents = _students);
    } else {
      setState(() {
        _filteredStudents = _students
            .where((s) =>
                s.name.toLowerCase().contains(query) ||
                (s.externalId?.toLowerCase().contains(query) ?? false) ||
                s.email.toLowerCase().contains(query))
            .toList();
      });
    }
  }

  String _backendBaseUrl() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    return overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
  }

  Future<void> _loadLocal() async {
    final db = DatabaseProvider.of(context);
    final students = await db.getStudentsForCourse(widget.courseLocalId);
    if (!mounted) return;
    setState(() {
      _students = students;
      _filteredStudents = students;
    });
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
                          'Enrolled Students',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshFromBackend,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                    
                    // Total Enrolled Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TOTAL ENROLLED',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[600],
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _students.length.toString(),
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.people_outline,
                                color: primaryBlue,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name or matric number',
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: primaryBlue.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Students List
                    if (_filteredStudents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _students.isEmpty ? 'No students enrolled yet' : 'No students found',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: _filteredStudents.length,
                          itemBuilder: (context, index) {
                            final s = _filteredStudents[index];
                            final initials = _getInitials(s.name);
                            final color = _getColorForIndex(index);

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
                                    width: 56,
                                    height: 56,
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
                                          s.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context).textTheme.bodyLarge?.color,
                                          ),
                                        ),
                                        if (s.externalId != null && s.externalId!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              s.externalId!,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF0D47A1),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        Text(
                                          s.email,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            )],
        ),
      ),
    );
  }
}
