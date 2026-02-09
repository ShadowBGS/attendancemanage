import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'student_scan_startup_screen.dart';
import 'settings_screen.dart';
import 'my_classes_screen.dart';
import 'profile_screen.dart';
import 'student_course_detail_screen.dart';
import '../db/database_provider.dart';
import '../db/database.dart';
import '../services/sync_service.dart';
import 'package:drift/drift.dart' show Value;
import '../theme/app_colors.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  String _userName = '';
  String _userEmail = 'user@example.com';

  // Dashboard data
  int _totalSessions = 0;
  int _enrolledClasses = 0;
  List<Course> _myClasses = [];
  bool _isInitialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _performInitialLoad();
  }

  Future<void> _performInitialLoad() async {
    await _loadUserInfoAndDashboard();
    if (mounted) {
      setState(() => _isInitialLoadDone = true);
    }
    // Initialize sync in background after initial load
    Future.microtask(() => _initializeSync());
  }

  Future<void> _initializeSync() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      const overrideUrl = String.fromEnvironment('BACKEND_URL');
      final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
      final db = DatabaseProvider.of(context);
      
      final sync = SyncService(database: db, baseUrl: baseUrl);
      sync.startSyncListener();
      
      // Initial sync
      await sync.syncPendingChanges();
    } catch (e) {
      // Silent fail - sync will retry on next connection
    }
  }

  Future<void> _loadUserInfoAndDashboard() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Load from local DB cache first for instant UI
      final db = DatabaseProvider.of(context);
      final cachedUser = await db.getUserByFirebaseUid(user.uid);
      
      if (cachedUser != null && mounted) {
        setState(() {
          _userName = cachedUser.name;
          _userEmail = cachedUser.email;
        });
        
        // Load dashboard data from cache in parallel
        final localId = cachedUser.id;
        final classes = await db.getCoursesForStudent(localId);
        final enrollCount = await db.countEnrollmentsForStudent(localId);
        final sessions = await db.getSessionsForStudent(localId);
        
        if (mounted) {
          setState(() {
            _myClasses = classes;
            _enrolledClasses = enrollCount;
            _totalSessions = sessions.length;
          });
        }
      }

      // Fetch fresh data in background without blocking UI
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      const overrideUrl = String.fromEnvironment('BACKEND_URL');
      final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';

      // Fetch user profile
      final profileResponse = await http.get(
        Uri.parse(baseUrl).resolve('/profile/info'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 8));

      if (profileResponse.statusCode == 200 && mounted) {
        final data = jsonDecode(profileResponse.body);
        setState(() {
          _userName = data['name'] ?? user.displayName ?? '';
          _userEmail = data['email'] ?? user.email ?? 'user@example.com';
        });

        // Persist to local DB
        try {
          await db.upsertUser(
            UsersCompanion.insert(
              firebaseUid: user.uid,
              email: data['email'] ?? user.email ?? '',
              name: data['name'] ?? user.displayName ?? '',
              role: 'student',
              externalId: Value(data['external_id'] as String?),
              department: Value(data['department'] as String?),
              profileCompleted: Value(data['profile_completed'] as bool? ?? false),
              lastSyncedAt: Value(DateTime.now()),
            ),
          );
        } catch (_) {}
      }

      // Fetch student courses and enrollments
      try {
        final coursesResponse = await http.get(
          Uri.parse(baseUrl).resolve('/student/my-courses'),
          headers: {'Authorization': 'Bearer $idToken'},
        ).timeout(const Duration(seconds: 10));

        if (coursesResponse.statusCode == 200) {
          final coursesData = jsonDecode(coursesResponse.body);
          final enrolledCourses = coursesData['enrolled_courses'] as List? ?? [];
          
          // Get current user's local ID
          final currentUser = await db.getUserByFirebaseUid(user.uid);
          if (currentUser != null) {
            // Store courses and enrollments in local DB
            for (final courseJson in enrolledCourses) {
              try {
                final courseId = courseJson['course_id']?.toString() ?? '';
                final courseCode = courseJson['course_code']?.toString() ?? '';
                final courseName = courseJson['course_name']?.toString() ?? '';
                final lecturerId = courseJson['lecturer_id'] as int?;
                
                if (courseId.isEmpty) continue;
                
                // Upsert course
                await db.upsertCourseFromServer(
                  serverId: courseId,
                  code: courseCode,
                  name: courseName,
                  description: null,
                  lecturerId: lecturerId,
                );
                
                // Get the local course to create enrollment
                final localCourse = await db.getCourseByServerId(courseId);
                if (localCourse != null) {
                  await db.ensureEnrollment(
                    studentLocalId: currentUser.id,
                    courseLocalId: localCourse.id,
                  );
                }
              } catch (e) {
                print('Error storing course: $e');
              }
            }
            
            // Reload dashboard data from DB
            await _loadDashboardData();
          }
        }
      } catch (e) {
        print('Error fetching student courses: $e');
      }

      // Fetch student sessions
      try {
        final sessionsResponse = await http.get(
          Uri.parse(baseUrl).resolve('/student/my-sessions'),
          headers: {'Authorization': 'Bearer $idToken'},
        ).timeout(const Duration(seconds: 10));

        if (sessionsResponse.statusCode == 200) {
          final sessionsList = jsonDecode(sessionsResponse.body) as List? ?? [];
          
          // Store sessions in local DB
          for (final sessionJson in sessionsList) {
            try {
              final sessionId = sessionJson['session_id']?.toString() ?? '';
              final courseCode = sessionJson['course_code']?.toString() ?? '';
              final startTimeStr = sessionJson['start_time']?.toString() ?? '';
              final endTimeStr = sessionJson['end_time']?.toString();
              
              if (sessionId.isEmpty || startTimeStr.isEmpty) continue;
              
              final startTime = DateTime.tryParse(startTimeStr);
              final endTime = endTimeStr != null ? DateTime.tryParse(endTimeStr) : null;
              
              if (startTime == null) continue;
              
              // Find course by code (we should have it from the courses call above)
              final courses = await db.getAllCourses();
              final course = courses.where((c) => c.code == courseCode).firstOrNull;
              
              if (course != null) {
                await db.upsertSessionFromServer(
                  serverId: sessionId,
                  courseLocalId: course.id,
                  startTime: startTime,
                  endTime: endTime,
                  status: 'active',
                );
              }
            } catch (e) {
              print('Error storing session: $e');
            }
          }
          
          // Reload dashboard data from DB
          await _loadDashboardData();
        }
      } catch (e) {
        print('Error fetching student sessions: $e');
      }
      
      // Always reload dashboard data at the end to ensure UI updates
      await _loadDashboardData();
    } catch (_) {
      // Fall back to Firebase user info
      final user = FirebaseAuth.instance.currentUser;
      if (mounted && user != null) {
        setState(() {
          _userName = user.displayName ?? user.email?.split('@').first ?? '';
          _userEmail = user.email ?? 'user@example.com';
        });
      }
      // Try to load dashboard data even if backend fetch failed (use cached data)
      try {
        await _loadDashboardData();
      } catch (e) {
        print('Error loading dashboard data: $e');
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _loadUserInfoAndDashboard();
    
    // Sync in background without blocking refresh
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        const overrideUrl = String.fromEnvironment('BACKEND_URL');
        final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
        final db = DatabaseProvider.of(context);
        final sync = SyncService(database: db, baseUrl: baseUrl);
        await sync.syncPendingChanges();
        await sync.pullLatestData(await user.getIdToken() ?? '');
      }
    } catch (_) {
      // Silent fail
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen until initial data is loaded
    if (!_isInitialLoadDone) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading your dashboard...',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
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
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            slivers: [
              // Modern Blue Header (matches lecturer dashboard)
              SliverAppBar(
                expandedHeight: 150,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.primaryBlue,
                elevation: 0,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 24, right: 70, bottom: 14),
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STUDENT PORTAL',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hello, ${_userName.isNotEmpty ? _userName.split(' ').first : "Student"}!',
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
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ModernStatCard(
                              value: _totalSessions.toString(),
                              label: 'Total Sessions',
                              icon: Icons.bar_chart_rounded,
                              iconColor: AppColors.primaryBlue,
                              backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ModernStatCard(
                              value: _enrolledClasses.toString(),
                              label: 'Enrolled Courses',
                              icon: Icons.school_rounded,
                              iconColor: const Color(0xFF7B1FA2),
                              backgroundColor: const Color(0xFFF3E5F5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'My Courses',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.titleLarge?.color,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MyClassesScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'See all',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              _myClasses.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No enrolled classes',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyMedium?.color,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final c = _myClasses[index];
                            return _ModernClassCard(
                              course: c,
                              index: index,
                            );
                          },
                          childCount: _myClasses.length > 6 ? 6 : _myClasses.length,
                        ),
                      ),
                    ),
              // Scan QR Button - moved up and always visible
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _handleScanQRCode,
                      icon: const Icon(Icons.qr_code_scanner, size: 24),
                      label: const Text(
                        'Scan QR Code',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                        shadowColor: AppColors.primaryBlue.withOpacity(0.4),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _loadDashboardData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final db = DatabaseProvider.of(context);
      final cached = await db.getUserByFirebaseUid(user.uid);
      if (cached == null) return;

      final localId = cached.id;
      final classes = await db.getCoursesForStudent(localId);
      final enrollCount = await db.countEnrollmentsForStudent(localId);
      final sessions = await db.getSessionsForStudent(localId);

      if (!mounted) return;
      setState(() {
        _myClasses = classes;
        _enrolledClasses = enrollCount;
        _totalSessions = sessions.length;
      });
    } catch (_) {
      // ignore errors for now
    }
  }

  Future<void> _handleScanQRCode() async {
    // Navigate to the startup screen which will check permissions
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const StudentScanStartupScreen(),
        ),
      ).then((_) async {
        // Wait a moment for sync to complete, then refresh dashboard
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          _loadUserInfoAndDashboard();
        }
      });
    }
  }
}

class _ModernStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;

  const _ModernStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.headlineSmall?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                ],
              ),
            ],
          ),
        ),
      );
  }
}

class _ModernClassCard extends StatelessWidget {
  final Course course;
  final int index;

  const _ModernClassCard({
    required this.course,
    required this.index,
  });

  IconData _getIconForCourse() {
    return Icons.book;
  }

  Color _getColorForIndex() {
    final colors = [
      const Color(0xFFE3F2FD),
      const Color(0xFFE0F2F1),
      const Color(0xFFFFF3E0),
      const Color(0xFFF3E5F5),
      const Color(0xFFFCE4EC),
    ];
    return colors[index % colors.length];
  }

  Color _getIconColorForIndex() {
    final colors = [
      const Color(0xFF1976D2),
      const Color(0xFF00897B),
      const Color(0xFFF57C00),
      const Color(0xFF7B1FA2),
      const Color(0xFFC2185B),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StudentCourseDetailScreen(course: course),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _getColorForIndex(),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getIconForCourse(),
                    color: _getIconColorForIndex(),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.code,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _getIconColorForIndex(),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        course.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
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

