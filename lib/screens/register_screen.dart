import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'complete_profile_screen.dart';
import 'lecturer_dashboard.dart';
import 'student_dashboard.dart';

class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({super.key, required this.role});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isObscured = true;
  bool _isLoading = false;
  static Future<void>? _googleInit;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _idController.dispose();
    _departmentController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _backendBaseUrl() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    if (overrideUrl.isNotEmpty) return overrideUrl;
    return 'https://att-back-0xvj.onrender.com';
  }

  String _formatName(String firstName, String lastName) {
    // Trim and capitalize first letter of each name
    final first = firstName.trim();
    final last = lastName.trim();
    
    final formattedFirst = first.isEmpty 
        ? '' 
        : first[0].toUpperCase() + first.substring(1).toLowerCase();
    final formattedLast = last.isEmpty 
        ? '' 
        : last[0].toUpperCase() + last.substring(1).toLowerCase();
    
    return '$formattedFirst $formattedLast'.trim();
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInit != null) return _googleInit!;
    _googleInit = GoogleSignIn.instance.initialize();
    return _googleInit!;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToDashboard() {
    final Widget destination = widget.role == 'student'
        ? const StudentDashboard()
        : const LecturerDashboard();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color themeColor = widget.role == 'student'
        ? const Color(0xFF673AB7)
        : Colors.blue;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Account',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: themeColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Join as a ${widget.role} to start tracking attendance.',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 24),

            _buildSocialButton(
              'Sign up with Google',
              'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_Color_Icon.svg',
              onTap: _isLoading
                  ? null
                  : () async {
                      setState(() => _isLoading = true);
                      try {
                        await _ensureGoogleInitialized();
                        final googleUser = await GoogleSignIn.instance.authenticate();
                        final googleAuth = googleUser.authentication;
                        final idToken = googleAuth.idToken;
                        if (idToken == null) {
                          _showError('Google sign-in did not return a token.');
                          return;
                        }

                        final credential = GoogleAuthProvider.credential(idToken: idToken);
                        await FirebaseAuth.instance.signInWithCredential(credential);

                        final userIdToken = await FirebaseAuth.instance.currentUser?.getIdToken();
                        if (userIdToken == null) {
                          _showError('Could not get ID token.');
                          return;
                        }

                        final resp = await http.post(
                          Uri.parse(_backendBaseUrl()).resolve('/auth/bootstrap'),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer $userIdToken',
                          },
                          body: jsonEncode({'role': widget.role}),
                        );

                        if (resp.statusCode < 200 || resp.statusCode >= 300) {
                          _showError('Backend signup failed (${resp.statusCode}).');
                          return;
                        }

                        bool profileCompleted = false;
                        try {
                          final decoded = jsonDecode(resp.body);
                          if (decoded is Map && decoded['profile_completed'] is bool) {
                            profileCompleted = decoded['profile_completed'] as bool;
                          }
                        } catch (_) {}

                        if (!mounted) return;
                        if (!profileCompleted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CompleteProfileScreen(
                                role: widget.role,
                                baseUrl: _backendBaseUrl(),
                              ),
                            ),
                          );
                        } else {
                          _goToDashboard();
                        }
                      } on FirebaseAuthException catch (e) {
                        _showError(e.message ?? 'Google sign-up failed.');
                      } on GoogleSignInException catch (e) {
                        if (e.code == GoogleSignInExceptionCode.canceled) {
                          _showError('Google sign-in was cancelled.');
                        } else {
                          _showError(e.description ?? 'Google sign-in failed.');
                        }
                      } catch (e) {
                        _showError('Google sign-up failed: $e');
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
            ),

            const SizedBox(height: 24),

            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),

            const SizedBox(height: 24),

            _buildTextField(
              'First Name',
              Icons.person_outline,
              controller: _firstNameController,
            ),
            const SizedBox(height: 16),

            _buildTextField(
              'Last Name',
              Icons.person_outline,
              controller: _lastNameController,
            ),
            const SizedBox(height: 16),

            _buildTextField(
              widget.role == 'student'
                  ? 'Student ID / Matric Number'
                  : 'Lecturer ID / Employee Number',
              Icons.badge_outlined,
              controller: _idController,
            ),
            const SizedBox(height: 16),

            _buildTextField(
              'Department / School',
              Icons.apartment_outlined,
              controller: _departmentController,
            ),
            const SizedBox(height: 16),

            _buildTextField(
              'Institutional Email',
              Icons.email_outlined,
              controller: _emailController,
            ),
            const SizedBox(height: 16),

            _buildTextField(
              'Password',
              Icons.lock_outline,
              isPassword: true,
              obscure: _isObscured,
              onSuffixIconTap: () => setState(() => _isObscured = !_isObscured),
              controller: _passwordController,
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        try {
                          final firstName = _firstNameController.text.trim();
                          final lastName = _lastNameController.text.trim();
                          final fullName = _formatName(firstName, lastName);
                          final extId = _idController.text.trim();
                          final department = _departmentController.text.trim();
                          final email = _emailController.text.trim();
                          final password = _passwordController.text;

                          if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty || department.isEmpty) {
                            _showError('First name, last name, email, password, and department are required.');
                            return;
                          }

                          final cred = await FirebaseAuth.instance
                              .createUserWithEmailAndPassword(
                            email: email,
                            password: password,
                          );
                          await cred.user?.updateDisplayName(fullName);
                          // Ensure ID token reflects latest profile changes
                          await cred.user?.reload();
                          final idToken = await cred.user?.getIdToken(true);
                          if (idToken == null) {
                            _showError('Could not get ID token.');
                            return;
                          }

                          final resp = await http.post(
                            Uri.parse('${_backendBaseUrl()}/auth/bootstrap'),
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $idToken',
                            },
                            body: jsonEncode({'role': widget.role}),
                          );

                          if (resp.statusCode < 200 || resp.statusCode >= 300) {
                            _showError('Backend signup failed (${resp.statusCode}).');
                            return;
                          }

                          // Mark profile complete immediately for email sign-up.
                          final completeResp = await http.post(
                            Uri.parse(_backendBaseUrl()).resolve('/profile/complete'),
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $idToken',
                            },
                            body: jsonEncode({
                              'external_id': extId,
                              'department': department,
                              'name': fullName,
                            }),
                          );

                          if (completeResp.statusCode < 200 || completeResp.statusCode >= 300) {
                            _showError('Profile save failed (${completeResp.statusCode}).');
                            return;
                          }

                          if (!mounted) return;
                          _goToDashboard();
                        } on FirebaseAuthException catch (e) {
                          _showError(e.message ?? 'Registration failed.');
                        } catch (e) {
                          _showError('Registration failed: $e');
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Create Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Already have an account? ',
                  style: TextStyle(color: Colors.grey),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Login',
                    style: TextStyle(
                      color: themeColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String hint,
    IconData icon, {
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onSuffixIconTap,
    TextEditingController? controller,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: onSuffixIconTap,
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
      ),
    );
  }

  Widget _buildSocialButton(
    String label,
    String logoUrl, {
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[300]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          backgroundColor: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(
              logoUrl,
              height: 24,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.g_mobiledata, size: 30),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
