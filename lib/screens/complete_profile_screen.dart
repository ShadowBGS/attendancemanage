import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'lecturer_main_wrapper.dart';
import 'student_main_wrapper.dart';
import 'face_enrollment_screen.dart';
import '../db/database_provider.dart';
import '../db/database.dart';
import '../services/face_data_manager.dart';

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
  final TextEditingController _departmentController = TextEditingController();

  @override
  void dispose() {
    _externalIdController.dispose();
    _departmentController.dispose();
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                widget.role == 'student' ? "Matric Number" : "Lecturer ID",
              ),
              TextField(
                controller: _externalIdController,
                decoration: _inputDecoration(
                  widget.role == 'student' ? "e.g. 2024/CS/001" : "e.g. LEC/2024/001",
                  Icons.badge_outlined,
                ),
              ),

              const SizedBox(height: 24),

              // Department Text Field
              _buildInputLabel("Department"),
              TextField(
                controller: _departmentController,
                decoration: _inputDecoration(
                  "e.g. Computer Science",
                  Icons.account_balance_outlined,
                ),
              ),

              const SizedBox(height: 48),

              // Finish Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    final extId = _externalIdController.text.trim();
                    final dept = _departmentController.text.trim();
                    if (extId.isEmpty || dept.isEmpty) {
                      _showSnack('Matric number and department are required.');
                      return;
                    }

                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      _showSnack('Not signed in.');
                      return;
                    }
                    final idToken = await user.getIdToken();

                    print('📤 Sending profile completion: extId=$extId, dept=$dept');
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

                    print('✅ Profile complete response: ${resp.statusCode}');
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

                    // Save to local database
                    try {
                      final db = DatabaseProvider.of(context);
                      await db.upsertUser(
                        UsersCompanion.insert(
                          firebaseUid: user.uid,
                          email: user.email ?? '',
                          name: user.displayName ?? '',
                          role: widget.role,
                          externalId: drift.Value(extId),
                          department: drift.Value(dept),
                          profileCompleted: const drift.Value(true),
                          lastSyncedAt: drift.Value(DateTime.now()),
                        ),
                      );
                      print('✅ Local database updated successfully');
                    } catch (e) {
                      print('⚠️ Local DB save failed: $e');
                      _showSnack('Database error: $e');
                      return;
                    }

                    if (!mounted) return;
                    
                    // For students: Go to facial enrollment first
                    // For lecturers: Go directly to main wrapper
                    if (widget.role == 'student') {
                      final user = FirebaseAuth.instance.currentUser;
                      if (!mounted) return;
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FaceEnrollmentScreen(
                            studentName: user?.displayName ?? 'Student',
                            onComplete: () {
                              if (mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const StudentMainWrapper(),
                                  ),
                                  (_) => false,
                                );
                              }
                            },
                            onFaceCaptured: (imagePath, embedding) async {
                              // Store face embedding in database
                              try {
                                final db = DatabaseProvider.of(context);
                                final faceDataManager = FaceDataManager(db);
                                final currentUser =
                                    FirebaseAuth.instance.currentUser;
                                if (currentUser != null) {
                                  // Get the local user ID
                                  final localUser = await db
                                      .getUserByFirebaseUid(currentUser.uid);
                                  if (localUser != null) {
                                    await faceDataManager.storeFaceEmbedding(
                                      localUser.id,
                                      embedding,
                                    );
                                    print(
                                        '✓ Face embedding stored for enrollment');
                                  }
                                }
                              } catch (e) {
                                print('⚠️ Error storing face embedding: $e');
                              }
                            },
                          ),
                        ),
                        (_) => false,
                      );
                    } else {
                      // Lecturer goes directly to main wrapper
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LecturerMainWrapper(),
                        ),
                        (_) => false,
                      );
                    }
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
