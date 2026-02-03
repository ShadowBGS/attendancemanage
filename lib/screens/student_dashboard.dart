import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'wifi_direct_scan_screen.dart';
import 'settings_screen.dart';
import '../db/database_provider.dart';
import '../db/database.dart';
import '../services/sync_service.dart';
import 'package:drift/drift.dart' show Value;

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  static const Color _accentColor = Color(0xFF673AB7);
  String _userName = '';
  String _userEmail = 'user@example.com';

  // Dashboard data
  int _totalSessions = 0;
  int _enrolledClasses = 0;
  List<Course> _myClasses = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    // Load dashboard counts from local DB
    Future.microtask(() => _loadDashboardData());
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Read cached profile from local DB first for instant UI
      final db = DatabaseProvider.of(context);
      final cached = await db.getUserByFirebaseUid(user.uid);
      if (cached != null && mounted) {
        setState(() {
          _userName = cached.name;
          _userEmail = cached.email;
        });
      }

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
          _userName = data['name'] ?? user.displayName ?? '';
          _userEmail = data['email'] ?? user.email ?? 'user@example.com';
        });

        // Persist fresh profile to local DB for future launches
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
        } catch (_) {
          // Ignore DB persistence errors; UI already updated.
        }

        // Refresh dashboard now that we have latest profile and local DB
        Future.microtask(() => _loadDashboardData());
      }
    } catch (e) {
      // Fall back to Firebase user info if backend call fails
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
    try {
      // Sync with backend first
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        const overrideUrl = String.fromEnvironment('BACKEND_URL');
        final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
        final db = DatabaseProvider.of(context);
        final sync = SyncService(database: db, baseUrl: baseUrl);
        await sync.syncPendingChanges();
      }
    } catch (e) {
      // Silent fail - continue with refresh even if sync fails
    }
    
    // Then refresh local data
    await _loadUserInfo();
    await _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome, $_userName!',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Student Dashboard',
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          _ProfileAvatar(
                            accentColor: _accentColor,
                            onTap: () => _showProfileSheet(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          _StatCard(
                            value: _totalSessions.toString(),
                            label: 'Total Sessions',
                            color: _accentColor,
                          ),
                          const SizedBox(width: 12),
                          _StatCard(
                            value: _enrolledClasses.toString(),
                            label: 'Enrolled Classes',
                            color: Colors.teal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'My Classes',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _myClasses.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('No enrolled classes')),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final c = _myClasses[index];
                            final item = _ClassCardData(code: c.code, name: c.name);
                            return _ClassCard(data: item, accentColor: _accentColor);
                          },
                          childCount: _myClasses.length,
                        ),
                      ),
                    ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WifiDirectScanScreen()),
          );
        },
        label: const Text(
          'Scan QR',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
        backgroundColor: _accentColor,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCardData {
  final String code;
  final String name;

  const _ClassCardData({required this.code, required this.name});
}

class _ClassCard extends StatelessWidget {
  final _ClassCardData data;
  final Color accentColor;

  const _ClassCard({required this.data, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.book_outlined, color: accentColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.code,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
                Text(
                  data.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}
