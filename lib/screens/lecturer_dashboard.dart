import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:drift/drift.dart' show Value;
import '../main.dart' show database;
import '../db/database_provider.dart';
import '../db/database.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';

import 'create_course_screen.dart';
import 'course_detail_screen.dart';
import 'class_startup_screen.dart';
import 'settings_screen.dart';
import 'lecturer_courses_screen.dart';
import 'lecturer_profile_screen.dart';
import 'database_viewer_screen.dart';

class LecturerDashboard extends StatefulWidget {
  const LecturerDashboard({super.key});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  static const Color _accentColor = AppColors.primaryBlue;
  String _userName = '';
  String _userEmail = '';
  int? _lecturerId;
  late SyncService _syncService;
  List<Course> _courses = [];
  bool _isInitialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _initializeSync();
    _performInitialLoad();
  }

  Future<void> _performInitialLoad() async {
    await Future.wait([
      _loadUserInfo(),
      _loadCourses(),
      _refreshCoursesFromBackend(),
    ]);
    if (mounted) {
      setState(() => _isInitialLoadDone = true);
    }
  }

  void _initializeSync() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
    
    _syncService = SyncService(database: database, baseUrl: baseUrl);
    _syncService.startSyncListener();
  }

  @override
  void dispose() {
    _syncService.stopSyncListener();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    try {
      final db = DatabaseProvider.of(context);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Try to get from local DB first
      final courses = _lecturerId != null
          ? await db.getCoursesByLecturer(_lecturerId!)
          : await db.getAllCourses();
      
      // Deduplicate courses by ID to prevent UI duplication
      final seen = <int>{};
      final uniqueCourses = courses.where((course) {
        if (seen.contains(course.id)) return false;
        seen.add(course.id);
        return true;
      }).toList();
      
      if (uniqueCourses.isNotEmpty && mounted) {
        setState(() => _courses = uniqueCourses);
      }
    } catch (e) {
      // Silently fail
    }
  }

  String _backendBaseUrl() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    return overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
  }

  Future<void> _refreshCoursesFromBackend() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final response = await http.get(
        Uri.parse(_backendBaseUrl()).resolve('/courses/my-courses'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final courses = (decoded is Map && decoded['courses'] is List)
          ? (decoded['courses'] as List)
          : const [];

      final db = DatabaseProvider.of(context);
      
      // Track processed course IDs to avoid duplicates in this sync operation
      final processedCourseIds = <String>{};
      
      for (final item in courses) {
        if (item is! Map) continue;
        final serverId = item['course_id']?.toString();
        final code = item['course_code']?.toString();
        final name = item['course_name']?.toString();
        final lecturerId = item['lecturer_id'] is int ? item['lecturer_id'] as int : null;
        if (serverId == null || code == null || name == null) continue;
        
        // Skip if already processed in this sync
        if (processedCourseIds.contains(serverId)) continue;
        processedCourseIds.add(serverId);

        await db.upsertCourseFromServer(
          serverId: serverId,
          code: code,
          name: name,
          description: item['description']?.toString(),
          lecturerId: lecturerId,
        );
      }

      await _loadCourses();
    } catch (e) {
      // Silently fail; local DB still works.
    }
  }

  Future<void> _handleRefresh() async {
    try {
      // Sync pending local changes to backend first
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _syncService.syncPendingChanges();
      }
    } catch (e) {
      // Silent fail - continue with refresh even if sync fails
    }
    
    // Then refresh data from backend and reload local
    await _refreshCoursesFromBackend();
    await _refreshSessionsFromBackend();
    await _loadCourses();
  }

  Future<void> _refreshSessionsFromBackend() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final response = await http.get(
        Uri.parse(_backendBaseUrl()).resolve('/sessions/my-sessions'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final sessions = (decoded is Map && decoded['sessions'] is List)
          ? (decoded['sessions'] as List)
          : const [];

      final db = DatabaseProvider.of(context);
      for (final item in sessions) {
        if (item is! Map) continue;
        final serverId = item['session_id']?.toString();
        final courseCode = item['course_code']?.toString();
        if (serverId == null || courseCode == null) continue;

        // Find course by code
        final course = await db.getCourseByCode(courseCode);
        if (course == null) continue;

        final startTime = DateTime.tryParse(item['start_time']?.toString() ?? '') ?? DateTime.now();
        final endTime = item['end_time'] != null ? DateTime.tryParse(item['end_time'].toString()) : null;
        final status = item['status']?.toString() ?? 'active';

        await db.upsertSessionFromServer(
          serverId: serverId,
          courseLocalId: course.id,
          startTime: startTime,
          endTime: endTime,
          status: status,
        );

        // Also fetch attendance records for this session
        await _refreshAttendanceForSession(serverId, idToken);
      }
    } catch (e) {
      print('Failed to refresh sessions: $e');
    }
  }

  Future<void> _refreshAttendanceForSession(String sessionServerId, String idToken) async {
    try {
      final response = await http.get(
        Uri.parse(_backendBaseUrl()).resolve('/attendance/session/$sessionServerId'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final records = (decoded is Map && decoded['attendance'] is List)
          ? (decoded['attendance'] as List)
          : const [];

      final db = DatabaseProvider.of(context);
      final session = await db.getSessionByServerId(sessionServerId);
      if (session == null) return;

      for (final item in records) {
        if (item is! Map) continue;
        final studentFirebaseUid = item['student_firebase_uid']?.toString();
        if (studentFirebaseUid == null) continue;

        // Get or create student user
        var student = await db.getUserByFirebaseUid(studentFirebaseUid);
        if (student == null) {
          // Create placeholder student user
          final studentId = await db.upsertUser(
            UsersCompanion.insert(
              firebaseUid: studentFirebaseUid,
              email: '',
              name: item['student_name']?.toString() ?? 'Student',
              role: 'student',
              externalId: Value(item['matric_number']?.toString()),
              department: const Value(null),
              profileCompleted: const Value(false),
              lastSyncedAt: Value(DateTime.now()),
            ),
          );
          student = await db.getUserById(studentId);
        }

        if (student == null) continue;

        final markedAt = DateTime.tryParse(item['marked_at']?.toString() ?? '') ?? DateTime.now();
        final status = item['status']?.toString() ?? 'present';

        await db.markAttendance(
          AttendanceRecordsCompanion.insert(
            serverId: Value(item['attendance_id']?.toString()),
            sessionId: session.id,
            studentId: student.id,
            status: status,
            markedAt: Value(markedAt),
            faceVerified: Value(item['face_verified'] == true),
            verificationMethod: Value(item['verification_method']?.toString() ?? 'qr'),
            synced: const Value(true),
          ),
        );
      }
    } catch (e) {
      print('Failed to refresh attendance for session $sessionServerId: $e');
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Read cached profile from local DB first for instant offline support
      final db = DatabaseProvider.of(context);
      final cached = await db.getUserByFirebaseUid(user.uid);
      if (cached != null && mounted) {
        setState(() {
          _userName = cached.name;
          _userEmail = cached.email;
        });
      }

      // Try to refresh from backend (will fail gracefully if offline)
      try {
        final idToken = await user.getIdToken();
        if (idToken == null) return;

        const overrideUrl = String.fromEnvironment('BACKEND_URL');
        final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';

        final response = await http.get(
          Uri.parse(baseUrl).resolve('/profile/info'),
          headers: {'Authorization': 'Bearer $idToken'},
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 && mounted) {
          final data = jsonDecode(response.body);
          setState(() {
            // Try backend name first, fall back to Firebase displayName, then email username
            final backendName = (data['name'] as String?)?.trim() ?? '';
            final displayName = (user.displayName ?? '').trim();
            final emailName = (data['email'] as String?)?.split('@').first ?? '';
            
            _userName = backendName.isNotEmpty 
                ? backendName 
                : (displayName.isNotEmpty ? displayName : emailName);
            _userEmail = data['email'] ?? user.email ?? 'user@example.com';

            final roleInfo = data['role_info'];
            final lecturerId = roleInfo is Map ? roleInfo['lecturer_id'] : null;
            _lecturerId = lecturerId is int ? lecturerId : null;
          });

          // Save updated profile to local DB
          await db.upsertUser(
            UsersCompanion.insert(
              firebaseUid: user.uid,
              email: data['email'] ?? user.email ?? '',
              name: data['name'] ?? user.displayName ?? '',
              role: 'lecturer',
              externalId: Value(data['external_id'] as String?),
              department: Value(data['department'] as String?),
              profileCompleted: Value(data['profile_completed'] as bool? ?? false),
              lastSyncedAt: Value(DateTime.now()),
            ),
          );
        }
      } catch (e) {
        // Network error - continue with cached data
      }
    } catch (e) {
      // Fall back to Firebase user info if no cache available
      final user = FirebaseAuth.instance.currentUser;
      if (mounted && user != null) {
        setState(() {
          _userName = user.displayName ?? user.email?.split('@').first ?? '';
          _userEmail = user.email ?? 'user@example.com';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen until initial data is loaded
    if (!_isInitialLoadDone) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          slivers: [
            // Modern Blue Header
            SliverAppBar(
              expandedHeight: 150,
              floating: false,
              pinned: true,
              backgroundColor: AppColors.primaryBlue,
              elevation: 0,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LECTURER PORTAL',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hello, ${_userName.isNotEmpty ? _userName.split(' ').first : "Dr. Smith"}!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primaryBlue,
                        AppColors.secondaryBlue,
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                // Database Viewer - Commented out for now (may be needed later)
                // IconButton(
                //   icon: const Icon(Icons.storage, color: Colors.white),
                //   tooltip: 'View Database',
                //   onPressed: () {
                //     Navigator.push(
                //       context,
                //       MaterialPageRoute(
                //         builder: (_) => const DatabaseViewerScreen(),
                //       ),
                //     );
                //   },
                // ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LecturerProfileScreen(),
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.white,
                    child: Icon(
                      Icons.person,
                      color: AppColors.primaryBlue,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'My Courses',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CreateCourseScreen()),
                            );
                            if (result == true && mounted) {
                              _loadCourses();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.add_circle,
                                  color: AppColors.primaryBlue,
                                  size: 10,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Add Course',
                                  style: TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LecturerCoursesScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'VIEW ALL',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _courses.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No courses yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a course to get started',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final course = _courses[index];
                          return _CourseCard(
                            code: course.code,
                            name: course.name,
                            students: '0', // TODO: calculate from enrollments
                            accentColor: _accentColor,
                            onDetails: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CourseDetailScreen(
                                    courseCode: course.code,
                                    courseName: course.name,
                                    courseLocalId: course.id,
                                    courseServerId: course.serverId,
                                  ),
                                ),
                              );
                            },
                            onStartClass: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext dialogContext) {
                                  return AlertDialog(
                                    title: const Text('Start Class'),
                                    content: Text('Start class for ${course.name}?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialogContext),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(dialogContext);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ClassStartupScreen(
                                                courseCode: course.code,
                                                courseName: course.name,
                                                courseLocalId: course.id,
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text('Start'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                        );
                        },
                        childCount: _courses.length,
                      ),
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton: null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _handleStartSession() {
    if (_courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please create a course first to start a session'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_courses.length == 1) {
      // Navigate directly to the single course
      final course = _courses.first;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CourseDetailScreen(
            courseCode: course.code,
            courseName: course.name,
            courseLocalId: course.id,
            courseServerId: course.serverId,
          ),
        ),
      );
    } else {
      // Show course selection dialog
      _showCourseSelectionDialog();
    }
  }

  void _showCourseSelectionDialog() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Course',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose which course to start an attendance session for:',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _courses.length,
                  itemBuilder: (context, index) {
                    final course = _courses[index];
                    final iconColor = _getIconColorForCourse(course.code);
                    
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CourseDetailScreen(
                              courseCode: course.code,
                              courseName: course.name,
                              courseLocalId: course.id,
                              courseServerId: course.serverId,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey.shade800 
                              : Colors.grey.shade200
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: iconColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.book,
                                color: iconColor,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: iconColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      course.code,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: iconColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    course.name,
                                    style: TextStyle(
                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.grey.shade400,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getIconColorForCourse(String code) {
    final colors = [
      const Color(0xFF0D47A1), // Blue
      const Color(0xFF7B1FA2), // Purple
      const Color(0xFFE65100), // Orange
      const Color(0xFF00796B), // Teal
    ];
    return colors[code.hashCode % colors.length];
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: false,
      builder: (context) {
        return _ProfileSheet(name: _userName, email: _userEmail);
      },
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final Color accentColor;
  final VoidCallback? onTap;
  const _ProfileAvatar({required this.accentColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: accentColor,
        child: const Icon(Icons.person, size: 20, color: Colors.white),
      ),
    );
  }
}

class _ProfileSheet extends StatelessWidget {
  final String name;
  final String email;

  const _ProfileSheet({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    email,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 34)),
          const SizedBox(height: 12),
          Text(
            'Hi, $name!',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final url = Uri.parse('https://myaccount.google.com');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open Google Account')),
                  );
                }
              }
            },
            child: const Text('Manage Account'),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () async {
              final navigator = Navigator.of(context, rootNavigator: true);
              navigator.pop(); // Close the bottom sheet
              
              // Sign out of Firebase and Google provider if used
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
              try {
                await GoogleSignIn.instance.signOut();
                await GoogleSignIn.instance.disconnect();
              } catch (_) {}
              
              // Let the auth state listener handle navigation; return to root route.
              navigator.popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final String code;
  final String name;
  final String students;
  final Color accentColor;
  final VoidCallback onDetails;
  final VoidCallback onStartClass;

  const _CourseCard({
    required this.code,
    required this.name,
    required this.students,
    required this.accentColor,
    required this.onDetails,
    required this.onStartClass,
  });

  // Get icon color based on course code prefix
  Color _getIconColor() {
    final colors = [
      const Color(0xFF0D47A1), // Blue
      const Color(0xFF7B1FA2), // Purple
      const Color(0xFFE65100), // Orange
      const Color(0xFF00796B), // Teal
    ];
    return colors[code.hashCode % colors.length];
  }

  IconData _getCourseIcon() {
    return Icons.book;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor();
    
    return GestureDetector(
      onTap: onDetails,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getCourseIcon(),
                    color: iconColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          code,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: iconColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                  size: 24,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: onStartClass,
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.play_arrow, size: 18, color: Colors.white),
                label: const Text(
                  'Start Class',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
