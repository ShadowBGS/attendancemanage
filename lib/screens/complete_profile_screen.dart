import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'lecturer_dashboard.dart';
import 'student_dashboard.dart';

class CompleteProfileScreen extends StatefulWidget {
  final String role;
  final String baseUrl;
  final String? prefillExternalId;
  const CompleteProfileScreen({
    super.key,
    required this.role,
    required this.baseUrl,
    this.prefillExternalId,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final TextEditingController _externalIdController = TextEditingController();
  String? selectedDepartment;
  final List<String> departments = [
    'Computer Science',
    'Engineering',
    'Business',
    'Arts',
  ];

  @override
  void dispose() {
    _externalIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.prefillExternalId != null && widget.prefillExternalId!.isNotEmpty &&
        _externalIdController.text.isEmpty) {
      _externalIdController.text = widget.prefillExternalId!;
    }
    final Color themeColor = widget.role == 'student'
        ? const Color(0xFF673AB7)
        : Colors.blue;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Success Icon/Illustration
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.stars_rounded, size: 80, color: themeColor),
              ),
              const SizedBox(height: 32),
              const Text(
                "Almost There!",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "We've verified your Google account. Now, let's link your university records.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 40),

              // ID Field
              _buildInputLabel(
                widget.role == 'student' ? "Student ID" : "Lecturer ID",
              ),
              TextField(
                controller: _externalIdController,
                decoration: _inputDecoration(
                  "e.g. 2024/CS/001",
                  Icons.badge_outlined,
                ),
              ),

              const SizedBox(height: 24),

              // Department Dropdown
              _buildInputLabel("Department"),
              DropdownButtonFormField<String>(
                initialValue: selectedDepartment,
                decoration: _inputDecoration(
                  "Select Department",
                  Icons.account_balance_outlined,
                ),
                items: departments
                    .map(
                      (dept) =>
                          DropdownMenuItem(value: dept, child: Text(dept)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => selectedDepartment = value),
              ),

              const SizedBox(height: 48),

              // Finish Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    final extId = _externalIdController.text.trim();
                    final dept = selectedDepartment?.trim() ?? '';
                    if (extId.isEmpty || dept.isEmpty) {
                      _showSnack('ID and department are required.');
                      return;
                    }

                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      _showSnack('Not signed in.');
                      return;
                    }
                    final idToken = await user.getIdToken();

                    final resp = await http.post(
                      Uri.parse(widget.baseUrl).resolve('/profile/complete'),
                      headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer $idToken',
                      },
                      body: jsonEncode({
                        'external_id': extId,
                        'department': dept,
                      }),
                    );

                    if (resp.statusCode < 200 || resp.statusCode >= 300) {
                      String extra = '';
                      try {
                        final decoded = jsonDecode(resp.body);
                        if (decoded is Map && decoded['detail'] != null) {
                          extra = ': ${decoded['detail']}';
                        }
                      } catch (_) {}
                      _showSnack('Profile update failed (${resp.statusCode})$extra');
                      return;
                    }

                    if (!mounted) return;
                    final Widget destination = widget.role == 'student'
                        ? const StudentDashboard()
                        : const LecturerDashboard();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => destination),
                      (_) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Finish Setup",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
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

  // --- Reusable UI Pieces ---
  Widget _buildInputLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
