import 'package:flutter/material.dart';
import '../widgets/role_card.dart';
import 'auth_screen.dart';

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  String selectedRole = 'lecturer';

  @override
  Widget build(BuildContext context) {
    final Color accentColor = selectedRole == 'student'
        ? const Color(0xFF673AB7)
        : Colors.blue;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Header (Restored)
                      _buildHeader(accentColor),
                      const SizedBox(height: 24),

                      // 2. Status Card (Restored)
                      _buildStatusCard(accentColor),
                      const SizedBox(height: 32),

                      const Text(
                        'Select Your Role',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. Role Cards (Using the custom widget)
                      RoleCard(
                        icon: Icons.school,
                        title: 'Lecturer',
                        subtitle: 'Start class sessions and manage attendance',
                        iconBackground: selectedRole == 'lecturer'
                            ? accentColor
                            : Colors.grey,
                        highlightColor: accentColor,
                        isSelected: selectedRole == 'lecturer',
                        onTap: () => setState(() => selectedRole = 'lecturer'),
                      ),
                      RoleCard(
                        icon: Icons.person,
                        title: 'Student',
                        subtitle: 'Scan QR codes and mark attendance',
                        iconBackground: selectedRole == 'student'
                            ? accentColor
                            : Colors.grey,
                        highlightColor: accentColor,
                        isSelected: selectedRole == 'student',
                        onTap: () => setState(() => selectedRole = 'student'),
                      ),

                      // 4. Feature List (Restored)
                      const SizedBox(height: 24),
                      _buildFeature('Works completely offline'),
                      const SizedBox(height: 12),
                      _buildFeature('GPS proximity verification'),
                      const SizedBox(height: 12),
                      _buildFeature('Real-time attendance updates'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 5. Continue Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AuthScreen(role: selectedRole),
                      ),
                    );
                  },
                  child: Text(
                    'Continue as ${selectedRole[0].toUpperCase()}${selectedRole.substring(1)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- RESTORED HELPER METHODS ---

  Widget _buildHeader(Color accentColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Smart Attendance',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text('Offline-First System', style: TextStyle(color: Colors.grey)),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
          child: const Icon(Icons.wifi_off, color: Colors.white, size: 24),
        ),
      ],
    );
  }

  Widget _buildStatusCard(Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_scanner, color: accentColor, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Ready to Connect',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Use Wi-Fi Direct for seamless tracking',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(String text) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 20),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
      ],
    );
  }
}
