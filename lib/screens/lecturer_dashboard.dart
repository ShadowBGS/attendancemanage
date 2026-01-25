import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show database, AuthGate;
import '../db/database_provider.dart';
import '../db/database.dart';
import '../services/sync_service.dart';

import 'create_course_screen.dart';
import 'course_detail_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';

class LecturerDashboard extends StatefulWidget {
  const LecturerDashboard({super.key});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  static const Color _accentColor = Colors.blue;
  String _userName = '';
  String _userEmail = '';
  int? _lecturerId;
  late SyncService _syncService;
  List<Course> _courses = [];

  @override
  void initState() {
    super.initState();
    _initializeSync();
    _loadUserInfo();
    _loadCourses();
    _refreshCoursesFromBackend();
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
      if (courses.isNotEmpty && mounted) {
        setState(() => _courses = courses);
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
      for (final item in courses) {
        if (item is! Map) continue;
        final serverId = item['course_id']?.toString();
        final code = item['course_code']?.toString();
        final name = item['course_name']?.toString();
        final lecturerId = item['lecturer_id'] is int ? item['lecturer_id'] as int : null;
        if (serverId == null || code == null || name == null) continue;

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

      final idToken = await user.getIdToken();
      if (idToken == null) return;

      const overrideUrl = String.fromEnvironment('BACKEND_URL');
      final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';

      final response = await http.get(
        Uri.parse(baseUrl).resolve('/profile/info'),
        headers: {'Authorization': 'Bearer $idToken'},
      );

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
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final greeting = _getGreeting();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 24,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: _accentColor.withOpacity(0.1),
              child: Icon(Icons.person, color: _accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, ${_userName.isNotEmpty ? _userName : "Lecturer"}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    "Lecturer Dashboard",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          _ProfileAvatar(
            accentColor: _accentColor,
            onTap: () => _showProfileSheet(context),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Hero card for starting new session
            GestureDetector(
              onTap: _handleStartSession,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_accentColor, _accentColor.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.wifi_tethering, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Start New Session",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Take attendance for any of your active courses.",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              "Your Courses",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _courses.isEmpty
                  ? const Center(child: Text('No courses yet'))
                  : ListView.builder(
                      itemCount: _courses.length,
                      itemBuilder: (context, index) {
                        final course = _courses[index];
                        return _CourseCard(
                          code: course.code,
                          name: course.name,
                          students: '0', // TODO: calculate from enrollments
                          accentColor: _accentColor,
                          onStart: () {
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
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateCourseScreen()),
          );
          // Refresh courses if one was created
          if (result == true && mounted) {
            _loadCourses();
          }
        },
        label: const Text('Create New Course'),
        icon: const Icon(Icons.add),
        backgroundColor: _accentColor,
      ),
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
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: _accentColor.withOpacity(0.1),
                        child: Text(
                          course.code.replaceAll(RegExp(r'[^0-9]'), ''),
                          style: TextStyle(
                            color: _accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        course.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(course.code),
                      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
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
              
              // Navigate to auth screen
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (route) => false,
              );
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
  final VoidCallback onStart;

  const _CourseCard({
    required this.code,
    required this.name,
    required this.students,
    required this.accentColor,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                code.replaceAll(RegExp(r'[^0-9]'), ''),
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '$students Students',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}
