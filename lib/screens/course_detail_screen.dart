import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../db/database_provider.dart';
import 'course_students_screen.dart';
import 'course_sessions_screen.dart';
import 'class_startup_screen.dart';
import 'edit_course_screen.dart';
import '../theme/app_colors.dart';
import 'course_settings_screen.dart';

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
  bool _isButtonLoading = false;
  bool _isInitialLoading = true;
  int _enrolledStudents = 0;
  int _totalSessions = 0;
  bool _didLoadInitialData = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadInitialData) {
      _didLoadInitialData = true;
      _loadCourseDetails();
    }
  }

  Future<void> _loadCourseDetails() async {
    if (!mounted) return;
    
    // Only show initial loading on first load, not on refresh
    final bool isRefresh = !_isInitialLoading;
    if (!isRefresh) {
      setState(() => _isInitialLoading = true);
    }
    
    try {
      final db = DatabaseProvider.of(context);
      final serverId = widget.courseServerId;
      
      // Try to fetch from backend first
      if (serverId != null && serverId.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final idToken = await user.getIdToken();
          if (idToken != null) {
            try {
              // Fetch students from backend
              final studentsResponse = await http
                  .get(
                    Uri.parse(_backendBaseUrl()).resolve('/courses/$serverId/students'),
                    headers: {'Authorization': 'Bearer $idToken'},
                  )
                  .timeout(const Duration(seconds: 10));

              // Fetch sessions from backend
              final sessionsResponse = await http
                  .get(
                    Uri.parse(_backendBaseUrl()).resolve('/courses/$serverId/sessions'),
                    headers: {'Authorization': 'Bearer $idToken'},
                  )
                  .timeout(const Duration(seconds: 10));

              if (mounted) {
                int studentsCount = _enrolledStudents;
                int sessionsCount = _totalSessions;
                
                if (studentsResponse.statusCode == 200) {
                  final studentsData = jsonDecode(studentsResponse.body);
                  if (studentsData is List) {
                    studentsCount = studentsData.length;
                  }
                }
                
                if (sessionsResponse.statusCode == 200) {
                  final sessionsData = jsonDecode(sessionsResponse.body);
                  if (sessionsData is List) {
                    sessionsCount = sessionsData.length;
                  } else if (sessionsData is Map && sessionsData['sessions'] is List) {
                    sessionsCount = (sessionsData['sessions'] as List).length;
                  }
                }
                
                setState(() {
                  _enrolledStudents = studentsCount;
                  _totalSessions = sessionsCount;
                });
                return; // Successfully fetched from backend
              }
            } catch (e) {
              print('⚠️ Error fetching from backend: $e');
              // Fall through to local DB
            }
          }
        }
      }
      
      // Fallback to local DB if backend fetch failed or no serverId
      final localStudents = await db.getStudentsForCourse(widget.courseLocalId);
      final sessions = await db.getSessionsByCourse(widget.courseLocalId);
      
      if (mounted) {
        setState(() {
          _enrolledStudents = localStudents.length;
          _totalSessions = sessions.length;
        });
      }
    } catch (e) {
      print('❌ Error loading course details: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
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
    setState(() => _isButtonLoading = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClassStartupScreen(
            courseCode: widget.courseCode,
            courseName: widget.courseName,
            courseLocalId: widget.courseLocalId,
          ),
        ),
      );
    } catch (e) {
      _showError('Failed to start class: $e');
    } finally {
      if (mounted) setState(() => _isButtonLoading = false);
    }
  }

  Future<void> _editCourse() async {
    if (!mounted) return;
    final db = DatabaseProvider.of(context);
    final course = await db.getCourseByLocalId(widget.courseLocalId);
    if (course == null) {
      _showError('Course not found');
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCourseScreen(course: course),
      ),
    );

    if (result == true && mounted) {
      // Reload course details
      await _loadCourseDetails();
      _showSuccess('Course updated successfully!');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while initial data is being fetched
    if (_isInitialLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // Blue Header
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back, color: AppColors.white),
                        ),
                        const Expanded(
                          child: Text(
                            'Course Details',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48), // Balance the back button
                      ],
                    ),
                  ),
                ),
              ),
              // Loading content
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading course details...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Blue Header with rounded bottom
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                // borderRadius: BorderRadius.only(
                //   bottomLeft: Radius.circular(30),
                //   bottomRight: Radius.circular(30),
                // ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsetsGeometry.all(8),
                  //padding: const EdgeInsets.fromLTRB(8, 12, 20, 24),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text(
                          'Course Details',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.white),
                        onPressed: _editCourse,
                        tooltip: 'Edit Course',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadCourseDetails,
                color: AppColors.primaryBlue,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                    // Course Header Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primaryBlue, Color.fromARGB(255, 199, 200, 201)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    // width: 80,
                    // height: 80,
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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
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
                      child: Column(
                        children: [
                          Icon(Icons.people_outline, color: AppColors.primaryBlue, size: 28),
                          const SizedBox(height: 8),
                          Text(
                            _enrolledStudents.toString(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Students',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
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
                      child: Column(
                        children: [
                          Icon(Icons.calendar_today_outlined, color: Colors.orange, size: 28),
                          const SizedBox(height: 8),
                          Text(
                            _totalSessions.toString(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sessions',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Course Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QUICK ACTIONS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
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
                    child: Column(
                      children: [
                        _ActionRow(
                          icon: Icons.list_outlined,
                          title: 'View Roster',
                          subtitle: 'See enrolled students',
                          showDivider: true,
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
                        _ActionRow(
                          icon: Icons.history_outlined,
                          title: 'Session History',
                          subtitle: 'View past sessions',
                          showDivider: true,
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
                        _ActionRow(
                          icon: Icons.settings_outlined,
                          title: 'Course Settings',
                          subtitle: 'Configure course options',
                          showDivider: false,
                          onTap: () async {
                            if (!mounted) return;
                            final db = DatabaseProvider.of(context);
                            final course = await db.getCourseByLocalId(widget.courseLocalId);
                            if (course == null) {
                              _showError('Course not found');
                              return;
                            }

                            final result = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CourseSettingsScreen(course: course),
                              ),
                            );

                            if (result == true && mounted) {
                              // Course was deleted or updated, go back
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Info Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primaryBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Start a class session to begin marking attendance.',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            
            // Start Class Button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isButtonLoading ? null : _startClass,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    disabledBackgroundColor: AppColors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  icon: _isButtonLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.play_circle_filled, color: Colors.white),
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
                ],
              ),
            ),
          ),
        )],
      ),
    ));
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool showDivider;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: const Color(0xFF0D47A1), size: 24),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: Colors.grey[200]),
          ),
      ],
    );
  }
}

