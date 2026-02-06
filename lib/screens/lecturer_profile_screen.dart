import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show appThemeMode;
import '../theme/app_colors.dart';
import '../db/database_provider.dart';
import 'lecturer_courses_screen.dart';
import 'lecturer_dashboard.dart';
import 'edit_profile_screen.dart';

class LecturerProfileScreen extends StatefulWidget {
  const LecturerProfileScreen({super.key});

  @override
  State<LecturerProfileScreen> createState() => _LecturerProfileScreenState();
}

class _LecturerProfileScreenState extends State<LecturerProfileScreen> {
  static const Color _primaryBlue = Color(0xFF0D47A1);
  
  String _fullName = '';
  String _staffId = '';
  String _department = '';
  String _title = '';
  String _email = '';
  
  bool _notificationsEnabled = false;
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoaded) {
      _hasLoaded = true;
      _loadUserProfile();
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // First set Firebase data as fallback
      setState(() {
        _fullName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
        _email = user.email ?? '';
        _staffId = '22';
        _department = 'N/A';
        _title = 'Dr.';
      });

      // Try to load from database
      bool hasCompleteData = false;
      try {
        final database = DatabaseProvider.of(context);
        final cachedUser = await database.getUserByFirebaseUid(user.uid);
        
        if (cachedUser != null && mounted) {
          setState(() {
            _fullName = cachedUser.name.isNotEmpty ? cachedUser.name : _fullName;
            _staffId = cachedUser.externalId ?? 'N/A';
            _department = cachedUser.department ?? 'N/A';
            _email = cachedUser.email.isNotEmpty ? cachedUser.email : _email;
          });
          hasCompleteData = cachedUser.externalId != null && cachedUser.department != null;
        }
      } catch (e) {
        print('Database error: $e');
      }
      
      // If database doesn't have complete data, fetch from backend
      if (!hasCompleteData) {
        try {
          final idToken = await user.getIdToken();
          if (idToken != null) {
            const overrideUrl = String.fromEnvironment('BACKEND_URL');
            final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
            
            final response = await http.get(
              Uri.parse(baseUrl).resolve('/profile/info'),
              headers: {'Authorization': 'Bearer $idToken'},
            ).timeout(const Duration(seconds: 10));
            
            print('Profile API Status: ${response.statusCode}');
            if (response.statusCode == 200) {
              print('Profile API Body: ${response.body}');
            }
            
            if (response.statusCode == 200 && mounted) {
              final data = jsonDecode(response.body);
              setState(() {
                if (data['name'] != null) _fullName = data['name'];
                if (data['external_id'] != null) _staffId = data['external_id'];
                if (data['department'] != null) _department = data['department'];
                if (data['email'] != null) _email = data['email'];
              });
            }
          }
        } catch (e) {
          print('Backend fetch error: $e');
        }
      }
      
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading lecturer profile: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    print('🎨 Profile screen rebuilt. isDarkMode=$isDarkMode');
    
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
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 20, 24),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: AppColors.white),
                      ),
                      const Expanded(
                        child: Text(
                          'Profile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.white,
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

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    
                    // Profile Avatar
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.avatarBg,
                        border: Border.all(color: AppColors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 80,
                        color: AppColors.avatarIcon,
                      ),
                    ),

                    const SizedBox(height: 16),
                    
                    // Name
                    Text(
                      _fullName.isNotEmpty ? _fullName : 'Loading...',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // Staff ID
                    Text(
                      _staffId,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditProfileScreen(
                                  initialName: _fullName,
                                  initialStaffId: _staffId,
                                  initialDepartment: _department,
                                  email: _email,
                                ),
                              ),
                            );

                            if (result == true && mounted) {
                              setState(() => _isLoading = true);
                              await _loadUserProfile();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.edit, color: AppColors.white, size: 18),
                          label: const Text(
                            'Edit Profile',
                            style: TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Personal Info Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              'PERSONAL INFO',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
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
                                _InfoRow(
                                  icon: Icons.badge_outlined,
                                  iconColor: Colors.blue,
                                  label: 'Full Name',
                                  value: _fullName,
                                  showDivider: true,
                                ),
                                _InfoRow(
                                  icon: Icons.tag,
                                  iconColor: Colors.purple,
                                  label: 'Staff ID',
                                  value: _staffId,
                                  showDivider: true,
                                ),
                                _InfoRow(
                                  icon: Icons.school,
                                  iconColor: Colors.indigo,
                                  label: 'Department',
                                  value: _department,
                                  showDivider: true,
                                ),
                                _InfoRow(
                                  icon: Icons.email,
                                  iconColor: Colors.amber,
                                  label: 'Email',
                                  value: _email,
                                  showDivider: false,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // App Settings Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              'APP SETTINGS',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
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
                                _SettingRow(
                                  icon: Icons.notifications,
                                  iconColor: Colors.blue,
                                  label: 'Notifications',
                                  value: _notificationsEnabled,
                                  showDivider: true,
                                  onChanged: (value) {
                                    setState(() => _notificationsEnabled = value);
                                  },
                                ),
                                _SettingRow(
                                  icon: Icons.dark_mode,
                                  iconColor: Colors.purple,
                                  label: 'Dark Mode',
                                  value: isDarkMode,
                                  showDivider: false,
                                  onChanged: (value) {
                                    print('🌙 Dark mode toggle clicked: value=$value');
                                    appThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Support Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              'SUPPORT',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
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
                                _SupportRow(
                                  icon: Icons.help_center,
                                  iconColor: Colors.grey,
                                  label: 'Help Center',
                                  showDivider: true,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Help Center coming soon')),
                                    );
                                  },
                                ),
                                _SupportRow(
                                  icon: Icons.privacy_tip,
                                  iconColor: Colors.grey,
                                  label: 'Privacy Policy',
                                  showDivider: false,
                                  onTap: () {
                                    final url = Uri.parse(
                                      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ&start_radio=1&pp=ygUJcmljayByb2xsoAcB0gcJCZEKAYcqIYzv',
                                    );
                                    launchUrl(url, mode: LaunchMode.externalApplication).then((ok) {
                                      if (!ok && context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Could not open Privacy Policy')),
                                        );
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Logout Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
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
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: const Icon(Icons.logout, color: Colors.red, size: 24),
                          title: const Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Logout'),
                                content: const Text('Are you sure you want to logout?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Logout', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true && mounted) {
                              try {
                                await FirebaseAuth.instance.signOut();
                                await GoogleSignIn.instance.signOut();
                                await GoogleSignIn.instance.disconnect();
                              } catch (_) {}
                              
                              if (mounted) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Version
                    const Text(
                      'Version 2.4.0',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool showDivider;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7) ?? Colors.grey[600]!,
                ),
              ),
            ],
          ),
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

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool value;
  final bool showDivider;
  final ValueChanged<bool> onChanged;

  const _SettingRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.showDivider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFF0D47A1),
              ),
            ],
          ),
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

class _SupportRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool showDivider;
  final VoidCallback onTap;

  const _SupportRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(icon, color: iconColor, size: 24),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
          onTap: onTap,
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
