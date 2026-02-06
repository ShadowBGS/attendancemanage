import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'wifi_direct_scan_screen.dart';
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
  int _currentNavIndex = 0;

  // Dashboard data
  int _totalSessions = 0;
  int _enrolledClasses = 0;
  List<Course> _myClasses = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfoAndDashboard();
    // Initialize sync service in background (non-blocking)
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

      final response = await http.get(
        Uri.parse(baseUrl).resolve('/profile/info'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
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
    } catch (_) {
      // Fall back to Firebase user info
      final user = FirebaseAuth.instance.currentUser;
      if (mounted && user != null) {
        setState(() {
          _userName = user.displayName ?? user.email?.split('@').first ?? '';
          _userEmail = user.email ?? 'user@example.com';
        });
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.primaryBlue,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    color: AppColors.primaryBlue,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Menu icon placeholder
                              SizedBox(width: 48, height: 48, child: Container()),
                              // Profile icon
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ProfileScreen(),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(30),
                                child: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Theme.of(context).cardColor,
                                  child: CircleAvatar(
                                    radius: 26,
                                    backgroundColor: AppColors.avatarBg,
                                    child: const Icon(Icons.person, size: 32, color: AppColors.avatarIcon),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STUDENT PORTAL',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Hello, '),
                                    TextSpan(
                                      text: _userName.isNotEmpty 
                                          ? _userName.split(' ')[0] 
                                          : 'Student',
                                    ),
                                    const TextSpan(text: '!'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                          childCount: _myClasses.length,
                        ),
                      ),
                    ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _handleScanQRCode,
                      icon: const Icon(Icons.qr_code_scanner),
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
    final cameraStatus = await Permission.camera.request();
    
    if (cameraStatus.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required to scan QR codes')),
        );
      }
      return;
    } else if (cameraStatus.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Camera Permission Required'),
            content: const Text('Camera permission is permanently denied. Please enable it in app settings.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  openAppSettings();
                  Navigator.pop(context);
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const WifiDirectScanScreen(),
        ),
      );
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

