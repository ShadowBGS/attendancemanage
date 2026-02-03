import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../db/database_provider.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _emailNotifications = true;
  bool _darkMode = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          _buildSection(
            'Account',
            [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Email'),
                subtitle: Text(user?.email ?? 'Not signed in'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email management coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Change Password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (user?.email != null) {
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(
                        email: user!.email!,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password reset email sent!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          const Divider(height: 1),
          _buildSection(
            'Notifications',
            [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Push Notifications'),
                subtitle: const Text('Receive notifications about sessions'),
                value: _notificationsEnabled,
                onChanged: (value) {
                  setState(() => _notificationsEnabled = value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        value ? 'Notifications enabled' : 'Notifications disabled',
                      ),
                    ),
                  );
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.email_outlined),
                title: const Text('Email Notifications'),
                subtitle: const Text('Receive email updates'),
                value: _emailNotifications,
                onChanged: (value) {
                  setState(() => _emailNotifications = value);
                },
              ),
            ],
          ),
          const Divider(height: 1),
          _buildSection(
            'Appearance',
            [
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark Mode'),
                subtitle: const Text('Use dark theme'),
                value: _darkMode,
                onChanged: (value) {
                  setState(() => _darkMode = value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dark mode coming in future update'),
                    ),
                  );
                },
              ),
            ],
          ),
          const Divider(height: 1),
          _buildSection(
            'Support',
            [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & FAQ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Help center coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Report a Problem'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Problem reporting coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: const Text('Sync Now'),
                subtitle: const Text('Push pending changes and pull latest data from server'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starting sync...')));
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) throw Exception('Not signed in');
                    final overrideUrl = String.fromEnvironment('BACKEND_URL');
                    final baseUrl = overrideUrl.isNotEmpty ? overrideUrl : 'https://att-back-0xvj.onrender.com';
                    final db = DatabaseProvider.of(context);
                    final sync = SyncService(database: db, baseUrl: baseUrl);
                    await sync.syncPendingChanges();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync completed')));
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: ${e.toString()}')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Privacy policy coming soon')),
                  );
                },
              ),
            ],
          ),
          const Divider(height: 1),
          _buildSection(
            'About',
            [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Version'),
                trailing: Text('1.0.0', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}
