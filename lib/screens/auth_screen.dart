import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../db/database_provider.dart';
import 'register_screen.dart';
import 'lecturer_main_wrapper.dart';
import 'student_main_wrapper.dart';
import 'complete_profile_screen.dart';
import 'email_verification_screen.dart';

class AuthScreen extends StatefulWidget {
  final String role;
  const AuthScreen({super.key, required this.role});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isObscured = true;
  bool _isLoading = false;

  static Future<void>? _googleInit;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _backendBaseUrl() {
    const overrideUrl = String.fromEnvironment('BACKEND_URL');
    if (overrideUrl.isNotEmpty) {
      return overrideUrl;
    }
    return 'https://att-back-0xvj.onrender.com';
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInit != null) return _googleInit!;
    _googleInit = GoogleSignIn.instance.initialize();
    return _googleInit!;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _bootstrapAndRoute() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Not signed in.');
      return;
    }

    // Check if a different user is logging in - if so, clear cached data
    try {
      final database = DatabaseProvider.of(context);
      final cachedUser = await database.getLatestUser();
      if (cachedUser != null && cachedUser.firebaseUid != user.uid) {
        print('🔄 Different user detected, clearing cached data...');
        await database.clearAllUserData();
      }
    } catch (e) {
      print('Error checking cached user: $e');
    }

    // Check if email needs verification (for email/password signups)
    if (!user.emailVerified) {
      print('📧 Email not verified, redirecting to verification screen');
      if (!mounted) return;
      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => EmailVerificationScreen(
            role: widget.role,
            user: user,
          ),
        ),
      );
      
      // If user didn't complete verification, stop here
      if (verified != true) return;
      
      // Reload user to get updated emailVerified status
      await user.reload();
    }

    final String baseUrl = _backendBaseUrl();
    final uri = Uri.parse('$baseUrl/auth/bootstrap');

    http.Response resp;
    try {
      final idToken = await user.getIdToken();
      resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'role': widget.role}),
      );
    } catch (e) {
      _showError(
        'Signed in, but backend is unreachable ($baseUrl). '
        'If you\'re on a real phone, use your PC\'s LAN IP via BACKEND_URL.',
      );
      return;
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String extra = '';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['detail'] != null) {
          extra = ': ${decoded['detail']}';
        }
      } catch (_) {
        if (resp.body.trim().isNotEmpty) {
          final body = resp.body.trim();
          extra = body.length <= 200 ? ': $body' : ': ${body.substring(0, 200)}...';
        }
      }
      _showError(
        'Signed in, but backend bootstrap failed (${resp.statusCode})$extra',
      );
      return;
    }

    bool profileCompleted = true;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['profile_completed'] is bool) {
        profileCompleted = decoded['profile_completed'] as bool;
      }
    } catch (_) {}

    if (!profileCompleted) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CompleteProfileScreen(
            role: widget.role,
            baseUrl: _backendBaseUrl(),
          ),
        ),
      );
      return;
    }

    _goToDashboard();
  }

  void _goToDashboard() {
    final Widget destination = widget.role == 'student'
        ? const StudentMainWrapper()
        : const LecturerMainWrapper();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Purple for Student (as in your image), Blue for Lecturer
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
          children: [
            const SizedBox(height: 20),
            // Welcome Message
            Text(
              "Welcome, ${widget.role[0].toUpperCase()}${widget.role.substring(1)}!",
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Sign in to manage your attendance system.",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            // Google Login Button
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: OutlinedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        try {
                          await _ensureGoogleInitialized();

                          final googleUser =
                              await GoogleSignIn.instance.authenticate();
                          final googleAuth = googleUser.authentication;
                          if (googleAuth.idToken == null) {
                            _showError(
                              'Google sign-in did not return a token. '
                              'Check Firebase Google sign-in setup.',
                            );
                            return;
                          }
                          final credential = GoogleAuthProvider.credential(
                            idToken: googleAuth.idToken,
                          );

                          await FirebaseAuth.instance
                              .signInWithCredential(credential);
                            await _bootstrapAndRoute();
                        } on FirebaseAuthException catch (e) {
                          _showError(e.message ?? 'Google sign-in failed.');
                        } on GoogleSignInException catch (e) {
                          if (e.code == GoogleSignInExceptionCode.canceled) {
                            _showError('Google sign-in was cancelled.');
                          } else {
                            _showError(e.description ?? 'Google sign-in failed.');
                          }
                        } catch (e) {
                          _showError('Google sign-in failed: $e');
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[200]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "G",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Continue with Google",
                            style:
                                TextStyle(color: Colors.black87, fontSize: 16),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 32),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("OR", style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 32),
            // Email Input
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                hintText: "Email",
                prefixIcon: const Icon(Icons.email_outlined),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Password Input
            TextField(
              controller: _passwordController,
              obscureText: _isObscured,
              decoration: InputDecoration(
                hintText: "Password",
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _isObscured = !_isObscured),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Main Login Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        try {
                          final email = _emailController.text.trim();
                          final password = _passwordController.text;

                          if (email.isEmpty || password.isEmpty) {
                            _showError('Enter email and password.');
                            return;
                          }

                          await FirebaseAuth.instance
                              .signInWithEmailAndPassword(
                            email: email,
                            password: password,
                          );
                          await _bootstrapAndRoute();
                        } on FirebaseAuthException catch (e) {
                          _showError(e.message ?? 'Email login failed.');
                        } catch (_) {
                          _showError('Email login failed.');
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
                child: const Text(
                  "Login with Email",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(color: Colors.grey),
                ),
                // Inside auth_screen.dart
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RegisterScreen(role: widget.role),
                      ),
                    );
                  },
                  child: Text(
                    "Register",
                    style: TextStyle(
                      color: themeColor,
                      fontWeight: FontWeight.bold,
                    ),
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
