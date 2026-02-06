import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:http/http.dart' as http;
import 'package:drift/drift.dart' as drift;

import 'firebase_options.dart';
import 'screens/role_selection.dart';
import 'screens/lecturer_main_wrapper.dart';
import 'screens/student_main_wrapper.dart';
import 'db/database.dart';
import 'db/database_provider.dart';
import 'theme/app_theme.dart';

// Global database instance
late final AppDatabase database;

// Global theme mode controller
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize local database
  database = AppDatabase();
  
  runApp(const SmartAttendanceApp());
}

class SmartAttendanceApp extends StatelessWidget {
  const SmartAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DatabaseProvider(
      database: database,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, mode, _) {
          print('🎨 MaterialApp rebuilding with theme mode: $mode');
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Smart Attendance',
            themeMode: mode,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<firebase_auth.User?>(
      stream: firebase_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        print('🔐 Auth state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, user: ${snapshot.data?.uid}');
        
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is logged in, show dashboard selector
        if (snapshot.hasData && snapshot.data != null) {
          print('✅ User logged in: ${snapshot.data!.email}');
          return const DashboardSelector();
        }

        // If not logged in, show role selection
        print('❌ No user logged in');
        return const RoleSelectionPage();
      },
    );
  }
}

class DashboardSelector extends StatefulWidget {
  const DashboardSelector({super.key});

  @override
  State<DashboardSelector> createState() => _DashboardSelectorState();
}

class _DashboardSelectorState extends State<DashboardSelector> {
  bool _isLoading = true;
  String? _role;
  bool _didCheckRole = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didCheckRole) {
      _didCheckRole = true;
      _checkUserRole();
    }
  }

  Future<void> _checkUserRole() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      print('👤 Checking user role for: ${user?.email}');
      if (user == null) {
        print('❌ No user in _checkUserRole');
        setState(() => _isLoading = false);
        return;
      }

      final db = DatabaseProvider.of(context);
      
      // Try to get from local cache first
      final cachedUser = await db.getUserByFirebaseUid(user.uid);
      print('💾 Cached user: ${cachedUser?.email}, role: ${cachedUser?.role}');
      
      if (cachedUser != null) {
        // Use cached data - even if profile not completed, we have the role
        print('✅ Found cached role: ${cachedUser.role}');
        setState(() {
          _role = cachedUser.role;
          _isLoading = false;
        });
        // Refresh from server in background (best effort)
        _refreshUserProfile();
        return;
      }

      // No cached user - must fetch from server for first time
      print('🌐 No cached user, fetching from server...');
      final success = await _refreshUserProfile();
      
      // If refresh failed and we still don't have role, show loading as false
      // so user sees role selection to complete profile
      if (!success && mounted) {
        print('⚠️ Failed to fetch user from server');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('❌ Error in _checkUserRole: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _refreshUserProfile() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final idToken = await user.getIdToken();
      if (idToken == null) return false;

      // Call backend to get user info
      const overrideUrl = String.fromEnvironment('BACKEND_URL');
      final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';

      print('🌐 Fetching profile from: $baseUrl/profile/info');
      final response = await http.get(
        Uri.parse(baseUrl).resolve('/profile/info'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      ).timeout(const Duration(seconds: 10)); // Add timeout for offline scenarios

      print('📡 Profile response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final role = data['role'] as String?;
        final profileCompleted = data['profile_completed'] as bool? ?? false;
        print('📦 Profile data: role=$role, profileCompleted=$profileCompleted');
        
        // Save to local database
        final db = DatabaseProvider.of(context);
        await db.upsertUser(
          UsersCompanion.insert(
            firebaseUid: user.uid,
            email: data['email'] ?? user.email ?? '',
            name: data['name'] ?? user.displayName ?? '',
            role: role ?? 'student',
            externalId: drift.Value(data['external_id'] as String?),
            department: drift.Value(data['department'] as String?),
            profileCompleted: drift.Value(profileCompleted),
            lastSyncedAt: drift.Value(DateTime.now()),
          ),
        );
        
        print('✅ Saved user to DB with role: $role');
        if (mounted) {
          setState(() {
            _role = role;
            _isLoading = false;
          });
        }
        return true;
      } else {
        print('⚠️ Profile fetch failed: ${response.statusCode}');
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return false;
      }
    } catch (e) {
      print('❌ Error refreshing profile: $e');
      // Network error or timeout - fail gracefully
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // If no role, must go to role selection
    if (_role == null) {
      return const RoleSelectionPage();
    }

    // Show appropriate dashboard based on role
    if (_role == 'lecturer') {
      return const LecturerMainWrapper();
    } else if (_role == 'student') {
      return const StudentMainWrapper();
    }

    // Fallback to role selection if role is unknown
    return const RoleSelectionPage();
  }
}