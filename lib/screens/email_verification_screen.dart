import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String role;
  final User user;
  
  const EmailVerificationScreen({
    super.key,
    required this.role,
    required this.user,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
  int _resendCountdown = 0;
  bool _isLoading = false;
  bool _emailVerified = false;
  late StreamSubscription _idTokenRefreshStream;

  @override
  void initState() {
    super.initState();
    _sendVerificationEmail();
    _startEmailVerificationCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idTokenRefreshStream.cancel();
    super.dispose();
  }

  /// Send verification email to user
  Future<void> _sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        print('✉️ Verification email sent to ${user.email}');
        _startResendCountdown();
      }
    } on FirebaseAuthException catch (e) {
      _showError('Failed to send verification email: ${e.message}');
    } catch (e) {
      _showError('Error: $e');
    }
  }

  /// Start countdown timer for resend button
  void _startResendCountdown() {
    _timer?.cancel();
    setState(() => _resendCountdown = 60);
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  /// Start checking if email is verified (polls every 2 seconds)
  void _startEmailVerificationCheck() {
    _idTokenRefreshStream = FirebaseAuth.instance.idTokenChanges().listen((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        if (user.emailVerified) {
          print('✅ Email verified!');
          if (mounted) {
            setState(() => _emailVerified = true);
            _completeVerification();
          }
        }
      }
    });

    // Also periodically check without waiting for token changes
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        if (user.emailVerified && !_emailVerified) {
          timer.cancel();
          if (mounted) {
            setState(() => _emailVerified = true);
            _completeVerification();
          }
        }
      }
    });
  }

  /// Called when email is verified successfully
  Future<void> _completeVerification() async {
    _timer?.cancel();
    
    // Small delay to show success state
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Email verified! Proceeding to next step...'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate back to auth screen which will bootstrap
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate verification completed
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  /// Manual verification check button
  Future<void> _checkVerification() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        if (user.emailVerified) {
          if (mounted) {
            setState(() => _emailVerified = true);
            _completeVerification();
          }
        } else {
          _showError('Email not verified yet. Please check your inbox.');
        }
      }
    } catch (e) {
      _showError('Error checking verification: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color themeColor = widget.role == 'student'
        ? const Color(0xFF673AB7)
        : Colors.blue;

    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF9FF),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                
                // Success/Verification Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      _emailVerified ? Icons.check_circle : Icons.mail_outline,
                      size: 56,
                      color: _emailVerified ? Colors.green : themeColor,
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Title
                Text(
                  _emailVerified ? 'Email Verified!' : 'Verify Your Email',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // Subtitle
                Text(
                  _emailVerified
                      ? 'Your email has been verified successfully.'
                      : 'We\'ve sent a verification link to:\n${widget.user.email}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),
                
                // Status Card
                if (!_emailVerified)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: themeColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Check your email inbox and spam folder.',
                                style: TextStyle(
                                  color: themeColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Click the verification link in the email to confirm your email address.',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 40),
                
                // Check Verification Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _checkVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            _emailVerified ? 'Continue' : 'I\'ve Verified My Email',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Resend Email Button
                if (!_emailVerified)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _resendCountdown > 0 ? null : _sendVerificationEmail,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _resendCountdown > 0 ? Colors.grey[300]! : themeColor,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        _resendCountdown > 0
                            ? 'Resend in $_resendCountdown seconds'
                            : 'Resend Verification Email',
                        style: TextStyle(
                          color: _resendCountdown > 0 ? Colors.grey : themeColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                
                const SizedBox(height: 20),
                
                // Logout Button
                if (!_emailVerified)
                  TextButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Text(
                      'Use a different email',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
